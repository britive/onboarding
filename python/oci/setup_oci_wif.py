#!/usr/bin/env python3
"""Create what the Britive OCI WIF application needs in an OCI identity domain:
a service user, a group that holds it, the identity propagation trust that lets
the Britive tenant act as that user, and optionally the Identity Domain
Administrator grant and the tenancy IAM policy.

The identity-domain part uses the domain's REST (SCIM) API, the same calls
Britive's guide gives as cURL; the policy uses the OCI SDK and ~/.oci/config.

Before running:
  1. In Britive, create the OCI WIF application (System Administration > Tenant
     Applications) to obtain the Britive Issuer URL, and download the WIF
     certificate (System Administration > Security > SAML Configurations >
     Download WIF Certificate).
  2. In the OCI identity domain, create a confidential application with the
     client-credentials grant and the Identity Domain Administrator role, and
     copy its client ID and secret.

Environment (or .env next to this file):
    OCI_DOMAIN_URL       https://idcs-....identity.oraclecloud.com (Identity > Domains > domain > Domain URL)
    OCI_CLIENT_ID        client ID of the confidential application
    OCI_CLIENT_SECRET    its client secret
    BRITIVE_ISSUER_URL   Britive Issuer URL shown by the OCI WIF application in Britive

Matches docs.britive.com/docs/prereq-oci-wif and the pages it links.
"""

import argparse
import base64
import json
import os
import sys
from pathlib import Path

import requests
from dotenv import load_dotenv

SCIM_JSON = "application/scim+json"
TIMEOUT = 30

POLICY_STATEMENTS = [
    "Allow group '{domain}'/'{group}' to inspect domains in tenancy",
    "Allow group '{domain}'/'{group}' to inspect compartments in tenancy",
    "Allow group '{domain}'/'{group}' to inspect policies in tenancy",
    "Allow group '{domain}'/'{group}' to inspect users in tenancy",
    "Allow group '{domain}'/'{group}' to inspect groups in tenancy",
    "Allow group '{domain}'/'{group}' to use users in tenancy where target.group.name != 'Administrators'",
    "Allow group '{domain}'/'{group}' to use groups in tenancy where target.group.name != 'Administrators'",
]


class IdentityDomain:
    """Minimal client for an OCI identity domain's admin (SCIM) API."""

    def __init__(self, domain_url: str, client_id: str, client_secret: str, dry_run: bool):
        self.base = domain_url.rstrip("/")
        self.dry_run = dry_run
        self.session = requests.Session()
        self.session.headers["Authorization"] = f"Bearer {self._token(client_id, client_secret)}"

    def _token(self, client_id: str, client_secret: str) -> str:
        # Client-credentials grant; the scope is Oracle's literal
        # urn:opc:idm:__myscopes__ (every scope the application was granted).
        response = requests.post(
            f"{self.base}/oauth2/v1/token",
            auth=(client_id, client_secret),
            data={"grant_type": "client_credentials", "scope": "urn:opc:idm:__myscopes__"},
            timeout=TIMEOUT,
        )
        if response.status_code != 200:
            sys.exit(f"token request failed ({response.status_code}): {response.text[:300]}")
        return response.json()["access_token"]

    def find(self, resource: str, scim_filter: str) -> dict | None:
        response = self.session.get(f"{self.base}/admin/v1/{resource}", params={"filter": scim_filter}, timeout=TIMEOUT)
        self._check(response, f"GET {resource}")
        resources = response.json().get("Resources") or []
        return resources[0] if resources else None

    def create(self, resource: str, body: dict) -> dict:
        if self.dry_run:
            print(f"  dry-run: would POST {resource} {json.dumps(body)[:200]}")
            return {"id": f"<dry-run {resource} id>"}
        response = self.session.post(f"{self.base}/admin/v1/{resource}", json=body,
                                     headers={"Content-Type": SCIM_JSON}, timeout=TIMEOUT)
        self._check(response, f"POST {resource}")
        return response.json()

    def patch(self, resource: str, resource_id: str, operations: list) -> None:
        if self.dry_run:
            print(f"  dry-run: would PATCH {resource}/{resource_id} {json.dumps(operations)[:200]}")
            return
        body = {"schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"], "Operations": operations}
        response = self.session.patch(f"{self.base}/admin/v1/{resource}/{resource_id}", json=body,
                                      headers={"Content-Type": SCIM_JSON}, timeout=TIMEOUT)
        self._check(response, f"PATCH {resource}/{resource_id}")

    @staticmethod
    def _check(response: requests.Response, what: str) -> None:
        if response.status_code >= 300:
            sys.exit(f"{what} failed ({response.status_code}): {response.text[:500]}")


def certificate_body(path: Path) -> str:
    """The certificate as base64 DER on one line, as the trust requires."""
    data = path.read_bytes()
    if b"-----BEGIN" in data:
        lines = [line.strip() for line in data.decode("ascii").splitlines()
                 if line.strip() and not line.startswith("-----")]
        return "".join(lines)
    return base64.b64encode(data).decode("ascii")


def ensure_service_user(domain: IdentityDomain, user_name: str, display_name: str) -> str:
    user = domain.find("Users", f'userName eq "{user_name}"')
    if user:
        print(f"service user {user_name} already exists ({user['id']})")
        return user["id"]
    user = domain.create("Users", {
        "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User",
                    "urn:ietf:params:scim:schemas:oracle:idcs:extension:user:User"],
        "userName": user_name,
        "displayName": display_name,
        "urn:ietf:params:scim:schemas:oracle:idcs:extension:user:User": {"serviceUser": True},
    })
    print(f"created service user {user_name} ({user['id']})")
    return user["id"]


def ensure_group(domain: IdentityDomain, group_name: str, user_id: str) -> str:
    group = domain.find("Groups", f'displayName eq "{group_name}"')
    if group:
        print(f"group {group_name} already exists ({group['id']})")
        group_id = group["id"]
        if any(member.get("value") == user_id for member in group.get("members") or []):
            print("  service user is already a member")
            return group_id
    else:
        group = domain.create("Groups", {
            "schemas": ["urn:ietf:params:scim:schemas:core:2.0:Group"],
            "displayName": group_name,
        })
        group_id = group["id"]
        print(f"created group {group_name} ({group_id})")
    domain.patch("Groups", group_id, [{"op": "add", "path": "members", "value": [{"value": user_id, "type": "User"}]}])
    print(f"added the service user to {group_name}")
    return group_id


def ensure_domain_admin_grant(domain: IdentityDomain, user_id: str) -> None:
    role = domain.find("AppRoles", 'displayName eq "Identity Domain Administrator"')
    if not role:
        sys.exit("AppRole 'Identity Domain Administrator' not found in this domain")
    existing = domain.find("Grants", f'grantee.value eq "{user_id}" and entitlement.attributeValue eq "{role["id"]}"')
    if existing:
        print("service user already holds Identity Domain Administrator")
        return
    domain.create("Grants", {
        "schemas": ["urn:ietf:params:scim:schemas:oracle:idcs:Grant"],
        "grantee": {"value": user_id, "type": "User"},
        "app": {"value": "IDCSAppId"},
        "entitlement": {"attributeName": "appRoles", "attributeValue": role["id"]},
        "grantMechanism": "ADMINISTRATOR_TO_USER",
    })
    print("granted Identity Domain Administrator to the service user")


def ensure_trust(domain: IdentityDomain, name: str, issuer: str, client_id: str, certificate: str, user_id: str) -> None:
    trust = domain.find("IdentityPropagationTrusts", f'name eq "{name}"')
    if trust:
        print(f"identity propagation trust {name} already exists ({trust['id']}); not modified")
        return
    domain.create("IdentityPropagationTrusts", {
        "schemas": ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"],
        "name": name,
        "issuer": issuer,
        "type": "JWT",
        "active": True,
        "allowImpersonation": True,
        "oauthClients": [client_id],
        "publicCertificate": certificate,
        # The rule must be exactly "sub eq *"; the value is the service user's ID.
        "impersonationServiceUsers": [{"rule": "sub eq *", "value": user_id}],
    })
    print(f"created identity propagation trust {name} for issuer {issuer}")


def ensure_policy(policy_name: str, domain_name: str, group_name: str, config_file: str, profile: str, dry_run: bool) -> str:
    """Tenancy IAM policy for the group, with the OCI SDK (~/.oci/config)."""
    try:
        import oci  # noqa: PLC0415 - optional dependency, only for --create-policy
    except ImportError:
        sys.exit("--create-policy needs the oci package: pip install -r requirements.txt")
    config = oci.config.from_file(config_file, profile)
    identity = oci.identity.IdentityClient(config)
    tenancy = config["tenancy"]
    statements = [s.format(domain=domain_name, group=group_name) for s in POLICY_STATEMENTS]
    existing = [p for p in oci.pagination.list_call_get_all_results(identity.list_policies, tenancy).data
                if p.name == policy_name]
    if existing:
        print(f"policy {policy_name} already exists ({existing[0].id})")
        return tenancy
    if dry_run:
        print(f"  dry-run: would create policy {policy_name} in {tenancy} with:\n    " + "\n    ".join(statements))
        return tenancy
    policy = identity.create_policy(oci.identity.models.CreatePolicyDetails(
        compartment_id=tenancy, name=policy_name, description="Britive OCI WIF integration", statements=statements,
    )).data
    print(f"created policy {policy_name} ({policy.id})")
    return tenancy


def main() -> None:
    load_dotenv(Path(__file__).with_name(".env"))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--domain-url", default=os.getenv("OCI_DOMAIN_URL"), help="identity domain URL (default: OCI_DOMAIN_URL)")
    parser.add_argument("--client-id", default=os.getenv("OCI_CLIENT_ID"), help="confidential application client ID (default: OCI_CLIENT_ID)")
    parser.add_argument("--issuer-url", default=os.getenv("BRITIVE_ISSUER_URL"), help="Britive Issuer URL (default: BRITIVE_ISSUER_URL)")
    parser.add_argument("--certificate-file", type=Path, required=True, help="Britive WIF certificate downloaded from the tenant (PEM or DER)")
    parser.add_argument("--user-name", default="britive-wif", help="service user name (default britive-wif)")
    parser.add_argument("--display-name", default="Britive WIF", help="service user display name")
    parser.add_argument("--group-name", default="BritiveWIFGroup", help="group name (default BritiveWIFGroup)")
    parser.add_argument("--trust-name", default="britive-wif", help="identity propagation trust name (default britive-wif)")
    parser.add_argument("--grant-domain-admin", action="store_true",
                        help="also grant the service user the Identity Domain Administrator role")
    parser.add_argument("--create-policy", action="store_true",
                        help="also create the tenancy IAM policy for the group, with the OCI SDK and ~/.oci/config")
    parser.add_argument("--policy-name", default="BritiveWIFPolicy", help="policy name (default BritiveWIFPolicy)")
    parser.add_argument("--domain-name", default="Default", help="identity domain name used in the policy statements (default Default)")
    parser.add_argument("--config", default="~/.oci/config", help="OCI CLI config file, for --create-policy")
    parser.add_argument("--profile", default="DEFAULT", help="profile in the config file, for --create-policy")
    parser.add_argument("--dry-run", action="store_true", help="read only; print what would be created")
    args = parser.parse_args()

    for name, value in (("--domain-url", args.domain_url), ("--client-id", args.client_id), ("--issuer-url", args.issuer_url)):
        if not value:
            parser.error(f"{name} (or its environment variable) is required")
    client_secret = os.getenv("OCI_CLIENT_SECRET")
    if not client_secret:
        parser.error("OCI_CLIENT_SECRET is required (environment or .env)")
    if not args.domain_url.startswith("https://"):
        parser.error("--domain-url must be the https:// URL of the identity domain")
    try:
        certificate = certificate_body(args.certificate_file)
    except OSError as exc:
        sys.exit(f"cannot read {args.certificate_file}: {exc}")

    domain = IdentityDomain(args.domain_url, args.client_id, client_secret, args.dry_run)
    user_id = ensure_service_user(domain, args.user_name, args.display_name)
    ensure_group(domain, args.group_name, user_id)
    if args.grant_domain_admin:
        ensure_domain_admin_grant(domain, user_id)
    ensure_trust(domain, args.trust_name, args.issuer_url, args.client_id, certificate, user_id)

    tenancy = None
    if args.create_policy:
        tenancy = ensure_policy(args.policy_name, args.domain_name, args.group_name, args.config, args.profile, args.dry_run)
    else:
        print("\nCreate this policy in the root compartment (Identity & Security > Policies) if it does not exist:")
        print("  " + "\n  ".join(s.format(domain=args.domain_name, group=args.group_name) for s in POLICY_STATEMENTS))

    print("\nBritive OCI WIF application fields:")
    print(f"  OCID of the tenancy:                 {tenancy or 'Identity & Security > Domains > Default > OCID'}")
    print("  Name of the tenant:                  your tenancy name")
    print(f"  Client ID of the confidential app:   {args.client_id}")
    print("  Region:                              the region identifier, e.g. us-phoenix-1")
    print(f"  Identity Domain URL:                 {args.domain_url}")
    print(f"  Britive Issuer URL (must match):     {args.issuer_url}")


if __name__ == "__main__":
    main()
