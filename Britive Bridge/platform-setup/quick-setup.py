#!/usr/bin/env python3
"""Britive Bridge - First-Time Setup Script

Interactive script that creates the required Britive platform objects for a new
Bridge deployment using the Britive Python SDK.

Prerequisites:
    pip install britive

Usage:
    python3 quick-setup.py

The script will prompt for:
    1. Britive tenant name and API token
    2. Bridge external URL
    3. Resource name

It then creates:
    - A Broker Pool with an active token
    - A Bridge Resource associated with the pool
    - A Response Template for clickable session URLs
    - An admin Profile with the required script parameters
"""

import getpass
import os
import sys
import tempfile
import time

import requests

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------

try:
    from britive.britive import Britive
except ImportError:
    print("Error: the 'britive' Python package is required.")
    print("Install it with:  pip install britive")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def prompt(label, default=None, secret=False):
    """Prompt the user for input with an optional default."""
    suffix = f" [{'****' if secret else default}]" if default else ""
    while True:
        value = getpass.getpass(f"  {label}{suffix}: ").strip() if secret else input(f"  {label}{suffix}: ").strip()
        if not value and default:
            return default
        if value:
            return value
        print("    (required)")


def header(step, title):
    print(f"\n{'=' * 60}")
    print(f"  Step {step}: {title}")
    print(f"{'=' * 60}\n")


def paragraph(*lines):
    for line in lines:
        print(f"  {line}")
    print()


def section_block(title):
    print(f"  {'=' * 50}")
    print(f"  {title}")
    print(f"  {'=' * 50}")
    print()


def print_env_block(tenant_subdomain, auth_token):
    section_block("Environment Variables for Bridge")
    print(f"  BRITIVE_BROKER_TENANT_SUBDOMAIN={tenant_subdomain}")
    if auth_token:
        print(f"  BRITIVE_BROKER_AUTH_TOKEN={auth_token}")
        print()
        print("  The token is a secret: clear your terminal scrollback after")
        print("  saving it, and avoid running this script where output is logged.")
    else:
        print("  BRITIVE_BROKER_AUTH_TOKEN=<check Britive UI for token value>")
    print()


def info(message):
    print(f"  -> {message}")


def success(message):
    print(f"  OK: {message}")


WARNING_COUNT = 0


def warn(message):
    global WARNING_COUNT
    WARNING_COUNT += 1
    print(f"  WARNING: {message}")


def error(message):
    print(f"  ERROR: {message}")


# ---------------------------------------------------------------------------
# Protocol definitions
# ---------------------------------------------------------------------------

ADMIN_PROFILE = {
    "name": "admin",
    "display": "Admin",
    "description": "Bridge admin UI access.",
}

# Bridge resource type icon (SVG).
BRIDGE_ICON_SVG = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 135.5 135.5">'
    "<defs>"
    '<linearGradient id="b" x1="-.7" x2="-.1" y1="1.1" y2="1.1" '
    'gradientTransform="matrix(137 70 102 -94 23.6 212.8)" '
    'gradientUnits="userSpaceOnUse" href="#a" spreadMethod="pad"/>'
    '<linearGradient id="a" x1="0" x2="1" y1="0" y2="0" '
    'gradientTransform="matrix(862 439 639 -592 2009.8 2360.3)" '
    'gradientUnits="userSpaceOnUse" spreadMethod="pad">'
    '<stop offset="0" stop-color="#ca1ecc"/>'
    '<stop offset=".5" stop-color="#8e41f7"/>'
    '<stop offset="1" stop-color="#3e5de0"/>'
    "</linearGradient>"
    "</defs>"
    '<path fill="url(#b)" d="M4.8 79.5a32 32 0 0 0 3.7 14.9 32 32 0 0 0 '
    "28.3 16.4h1.7a38 38 0 0 0 23.7-9.6c5.8-5 10-11.3 13.7-17.7a53 53 0 0 "
    "1 14.4-17 19 19 0 0 1 11-3.8l3.4.3a19 19 0 0 1 11.2 6.5 19 19 0 0 1 "
    "4.2 11.8 20 20 0 0 1-.6 5 19 19 0 0 1-6.9 10.3 19 19 0 0 1-11.2 "
    "3.7 19 19 0 0 1-5.3-.8 18 18 0 0 1-7.8-4.4l-1.7-1.3a5 5 0 0 "
    "0-2.3-.6l-1.5.3a6 6 0 0 0-2.8 1.9 5 5 0 0 0-1 3 6 6 0 0 0 2 "
    "4.3l3.6 2.9a30 30 0 0 0 16.8 5.3 29 29 0 0 0 18-6.4 30 30 0 0 0 "
    "8.5-10.1 28 28 0 0 0 2.8-12.5l-.3-4.3a28 28 0 0 0-4.5-12.3 31 31 0 "
    "0 0-9.7-9 27 27 0 0 0-14.5-4 35 35 0 0 0-5.4.4 27 27 0 0 0-9.4 "
    "3.4 43 43 0 0 0-7.7 5.9A81 81 0 0 0 66 79.6a52 52 0 0 1-11.8 "
    "14.6 27 27 0 0 1-17.5 6.1h-1a21 21 0 0 1-8.4-2 22 22 0 0 "
    "1-7-5.3c-3.3-3.8-5-8.9-5-13.8a21 21 0 0 1 20.8-21l3.3.3a23 23 0 0 "
    "1 12 6l1.4.9 1.7.4h.6a5 5 0 0 0 2.7-.8 6 6 0 0 0 1.9-2.2 5 5 0 0 "
    "0 .6-2.1 4 4 0 0 0-.5-2l-1.1-1.5a28 28 0 0 0-9.1-6.5l-4.2-1.8a20 "
    "20 0 0 1 5-7.2 27 27 0 0 1 7.7-5 23 23 0 0 1 8.7-1.6l3.7.2a25 25 "
    "0 0 1 8.1 2.6 25 25 0 0 1 6.6 5.2l1.4 2 1.6 2.3a6 6 0 0 0 2 1.7 5 "
    "5 0 0 0 2.5.6h.6a5 5 0 0 0 2.7-1.2 6 6 0 0 0 1.5-2.3l.4-1.7-.4-1."
    "8-.8-1.5a37 37 0 0 0-8.6-9.6 34 34 0 0 0-11.6-5.7 35 35 0 0 "
    "0-9.5-1.3 34 34 0 0 0-13 2.6 32 32 0 0 0-14.7 11.7c-2 2.9-3.4 "
    "5.8-5.2 9h-.5a30 30 0 0 0-19.8 9.3 33 33 0 0 0-6.7 10 30 30 0 0 "
    '0-2.3 11.7Z" data-name="Path 173" '
    'style="font-variation-settings:normal;-inkscape-stroke:none"/>'
    "</svg>"
)

# Resource type fields added to Bridge after broker registration.
BRIDGE_RESOURCE_TYPE_FIELDS = [
    {"name": "protocol", "paramType": "string", "isMandatory": True},
    {"name": "url", "paramType": "string", "isMandatory": True},
]

# Permission-level variable names (flat list of strings for the permission definition).
ADMIN_PERMISSION_VARIABLE_NAMES = [
    "PROTOCOL",
    "USERNAME",
    "BRIDGE_URL",
    "EXPIRATION",
    "TRANSACTION_ID",
]

# Profile-level variable mappings (system-defined values resolved at checkout time).
ADMIN_PROFILE_VARIABLES = [
    {"name": "PROTOCOL", "value": "resource.protocol", "isSystemDefined": True},
    {"name": "USERNAME", "value": "user.username", "isSystemDefined": True},
    {"name": "BRIDGE_URL", "value": "resource.url", "isSystemDefined": True},
    {"name": "EXPIRATION", "value": "profile.timeout", "isSystemDefined": True},
    {"name": "TRANSACTION_ID", "value": "profile.transactionId", "isSystemDefined": True},
]

ADMIN_CHECKOUT_SCRIPT = """\
#!/bin/sh
set -eu

TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 43)
NOW_EPOCH=$(date +%s)
# EXPIRATION (profile.timeout) is in milliseconds; expires_at is epoch seconds.
EXPIRES_AT=$((NOW_EPOCH + EXPIRATION / 1000))
cat <<EOF | /opt/britive-broker/scripts/bridge.sh checkout-create --stdin >/dev/null
{
  "transaction_id": "${TRANSACTION_ID}",
  "protocol": "admin",
  "username": "${USERNAME}",
  "expires_at": ${EXPIRES_AT},
  "token": "${TOKEN}"
}
EOF
URL="${BRIDGE_URL}/admin#token=${TOKEN}"
printf '{"token": "%s", "url": "%s"}\\n' "${TOKEN}" "${URL}"
"""

ADMIN_CHECKIN_SCRIPT = """\
#!/bin/sh
set -eu

/opt/britive-broker/scripts/bridge.sh checkout-delete "${TRANSACTION_ID}"
"""


def collect_tenant_credentials():
    header(1, "Britive Tenant Credentials")
    paragraph(
        "Provide your Britive tenant name and an API token.",
        "The tenant name is the subdomain of your Britive URL.",
        "Example: if your URL is https://acme.britive-app.com,",
        "the tenant name is 'acme'.",
    )

    tenant = prompt("Tenant name", default=os.environ.get("BRITIVE_TENANT"))
    token = prompt("API token", default=os.environ.get("BRITIVE_API_TOKEN"), secret=True)

    info("Connecting to Britive...")
    try:
        client = Britive(tenant=tenant, token=token)
        client.access_broker.pools.list()
        success(f"Connected to {tenant}.britive-app.com")
    except Exception as exc:
        error(f"Failed to connect: {exc}")
        sys.exit(1)

    return client, tenant


def create_broker_pool_and_token(client):
    header(2, "Create Broker Pool")

    pool_name = prompt("Broker pool name", default="Bridge")

    # Check if a pool with this name already exists
    pool_id = None
    auth_token = None
    try:
        existing_pools = client.access_broker.pools.list(name_filter=pool_name)
        for p in existing_pools:
            if p.get("name") == pool_name:
                pool_id = p.get("pool-id")
                break
    except Exception as exc:
        warn(f"Could not check for an existing pool ({exc}); attempting to create one.")

    if pool_id:
        success(f"Broker pool '{pool_name}' already exists: {pool_id}")
        warn("No new token will be generated — use the existing token from the Britive UI.")
        return pool_name, pool_id, None

    info(f"Creating broker pool '{pool_name}'...")
    try:
        pool = client.access_broker.pools.create(name=pool_name, description="Britive Bridge")
        pool_id = pool.get("pool-id")
        success(f"Broker pool created: {pool_id}")
    except Exception as exc:
        error(f"Failed to create broker pool: {exc}")
        sys.exit(1)

    info("Creating broker token...")
    try:
        token_result = client.access_broker.pools.create_token(
            pool_id, name="bridge-token", description="Auto-generated by Bridge setup script"
        )
        auth_token = token_result.get("token") or token_result.get("secret")
        success("Broker token created")
    except Exception as exc:
        error(f"Failed to create broker token: {exc}")
        sys.exit(1)

    info("Activating broker token...")
    try:
        client.access_broker.pools.update_token(pool_id, name="bridge-token", status="ACTIVE")
        success("Broker token activated")
    except Exception as exc:
        warn(f"Failed to activate token (you may need to activate it manually): {exc}")

    return pool_name, pool_id, auth_token


def collect_bridge_url(tenant_subdomain, auth_token):
    print_env_block(tenant_subdomain, auth_token)
    paragraph("Save these values. You will need them to start Bridge.")

    header(3, "Bridge External URL")
    paragraph(
        "This is the URL users will use to access Bridge.",
        "It must be reachable from their browser.",
    )

    # The scheme is stripped here because the resource's `url` param is stored
    # scheme-less; the response template re-adds it as `<scheme>://{{url}}`.
    while True:
        url = prompt("Bridge URL", default="https://localhost:8080")
        if "://" in url:
            return url.split("://", maxsplit=1)
        print("    (must include a scheme, e.g. https://bridge.example.com)")


def create_bridge_resource_type(client):
    header(5, "Create Bridge Resource Type")

    # Check if it already exists
    try:
        for rt in client.access_broker.resources.types.list():
            if rt.get("name") == "Bridge":
                bridge_type_id = rt.get("resourceTypeId")
                success(f"Resource type 'Bridge' already exists: {bridge_type_id}")
                return bridge_type_id
    except Exception as exc:
        warn(f"Could not check for an existing resource type ({exc}); attempting to create one.")

    info("Creating 'Bridge' resource type...")
    try:
        rt = client.access_broker.resources.types.create(
            name="Bridge",
            fields=BRIDGE_RESOURCE_TYPE_FIELDS,
        )
        bridge_type_id = rt.get("resourceTypeId")
        success(f"Resource type created: {bridge_type_id}")
    except Exception as exc:
        error(f"Failed to create resource type: {exc}")
        sys.exit(1)

    # Upload icon (retry briefly — the platform may need a moment after creation)
    info("Setting Bridge resource type icon...")
    icon_url = f"{client.base_url}/resource-manager/resource-types/{bridge_type_id}/icon-data"
    for attempt in range(5):
        try:
            client.put(
                icon_url,
                data=BRIDGE_ICON_SVG,
                headers={"Content-Type": "image/svg+xml"},
            )
            success("Resource type icon set")
            break
        except Exception as exc:
            if attempt < 4:
                time.sleep(2)
            else:
                warn(f"Could not set icon: {exc}")

    return bridge_type_id


def create_admin_permission(client, bridge_type_id, template_id):
    header(6, "Create Admin Permission")

    perms = client.access_broker.resources.permissions

    # Re-run safety: reuse an existing 'admin' permission for this resource type.
    try:
        for existing in perms.list(bridge_type_id) or []:
            if existing.get("name") == ADMIN_PROFILE["name"]:
                perm_id = existing.get("permissionId")
                success(f"Permission 'admin' already exists: {perm_id}")
                info("Scripts/variables left as-is — edit them in the Britive UI if needed.")
                return {"id": perm_id, "resource_type_id": bridge_type_id}
    except Exception as exc:
        warn(f"Could not check for an existing permission ({exc}); attempting to create one.")

    # Step 1: Create permission as draft (SDK)
    info("Creating draft permission...")
    try:
        perm = perms.create(
            resource_type_id=bridge_type_id,
            name=ADMIN_PROFILE["name"],
            description=ADMIN_PROFILE["description"],
        )
        perm_id = perm["permissionId"]
        success(f"Draft permission created: {perm_id}")
    except Exception as exc:
        warn(f"Failed to create draft permission: {exc}")
        return None

    # Step 2: Get presigned upload URLs (SDK, with retry for propagation delay)
    info("Getting script upload URLs...")
    urls = None
    for attempt in range(5):
        try:
            urls = perms.get_urls(perm_id)
            if isinstance(urls, dict) and "checkinURL" in urls:
                success("Upload URLs retrieved")
                break
            urls = None
        except Exception:
            pass
        if attempt < 4:
            time.sleep(2)

    if not urls:
        warn("Could not get script upload URLs.")
        return {"id": perm_id, "resource_type_id": bridge_type_id}

    # Step 3: Upload scripts to presigned S3 URLs via temp files
    info("Uploading checkout script...")
    checkout_tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".sh", delete=False)  # noqa: SIM115
    checkin_tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".sh", delete=False)  # noqa: SIM115
    try:
        checkout_tmp.write(ADMIN_CHECKOUT_SCRIPT)
        checkout_tmp.close()
        checkin_tmp.write(ADMIN_CHECKIN_SCRIPT)
        checkin_tmp.close()

        with open(checkout_tmp.name, "rb") as f:
            requests.put(urls["checkoutURL"], data=f, timeout=30).raise_for_status()
        success("Checkout script uploaded")

        info("Uploading checkin script...")
        with open(checkin_tmp.name, "rb") as f:
            requests.put(urls["checkinURL"], data=f, timeout=30).raise_for_status()
        success("Checkin script uploaded")
    except Exception as exc:
        warn(f"Failed to upload scripts: {exc}")
        warn("Permission left as a draft — re-run this script or upload scripts in the UI.")
        return {"id": perm_id, "resource_type_id": bridge_type_id}
    finally:
        os.unlink(checkout_tmp.name)
        os.unlink(checkin_tmp.name)

    # Step 4: Finalize permission with file metadata, variables, and response template.
    # SDK's update() filters out responseTemplates via valid_fields, so we use a direct PUT.
    info("Finalizing permission...")
    finalize_body = {
        "permissionId": perm_id,
        "name": ADMIN_PROFILE["name"],
        "resourceTypeId": bridge_type_id,
        "description": ADMIN_PROFILE["description"],
        "checkinFileName": f"{perm_id}_checkin",
        "checkinTimeLimit": 60,
        "checkoutFileName": f"{perm_id}_checkout",
        "checkoutTimeLimit": 60,
        "isDraft": False,
        "inlineFileExists": True,
        "editorType": "shell",
        "variables": ADMIN_PERMISSION_VARIABLE_NAMES,
    }
    if template_id:
        finalize_body["responseTemplates"] = [
            {"name": "Bridge", "templateId": template_id},
        ]

    try:
        perm_url = f"{client.base_url}/resource-manager/permissions/{perm_id}"
        client.put(perm_url, json=finalize_body)
        success(f"Permission 'admin' finalized: {perm_id}")
    except Exception as exc:
        warn(f"Failed to finalize permission: {exc}")

    return {"id": perm_id, "resource_type_id": bridge_type_id}


def create_bridge_resource(client, bridge_type_id, bridge_url, pool_id):
    header(7, "Create Bridge Resource")
    resource_name = prompt("Resource name", default="Admin")

    # Re-run safety: reuse an existing resource and refresh its URL — this is
    # the documented flow for deploying infra first and re-running with the
    # real DNS name.
    resource_id = None
    try:
        result = client.access_broker.resources.list(search_text=resource_name)
        items = result.get("data", result) if isinstance(result, dict) else result
        for res in items or []:
            if res.get("name") == resource_name:
                resource_id = res.get("resourceId")
                break
    except Exception as exc:
        warn(f"Could not check for an existing resource ({exc}); attempting to create one.")

    if resource_id:
        success(f"Resource '{resource_name}' already exists: {resource_id}")
        info(f"Updating its URL parameter to '{bridge_url}'...")
        try:
            client.put(
                f"{client.base_url}/resource-manager/resources/{resource_id}",
                json={
                    "name": resource_name,
                    "resourceType": {"id": bridge_type_id},
                    "description": f"Bridge deployment at {bridge_url}",
                    "paramValues": {"protocol": "admin", "url": bridge_url},
                },
            )
            success("Resource URL updated")
        except Exception as exc:
            warn(f"Could not update the resource URL ({exc}) — update it in the Britive UI.")
    else:
        info(f"Creating resource '{resource_name}'...")
        try:
            resource = client.access_broker.resources.create(
                name=resource_name,
                resource_type_id=bridge_type_id,
                description=f"Bridge deployment at {bridge_url}",
                param_values={"protocol": "admin", "url": bridge_url},
            )
            resource_id = resource.get("resourceId")
            success(f"Resource created: {resource_id}")
        except Exception as exc:
            error(f"Failed to create resource: {exc}")
            sys.exit(1)

    info("Associating resource with broker pool...")
    for attempt in range(5):
        try:
            client.access_broker.resources.add_broker_pools(resource_id, [pool_id])
            success("Resource associated with broker pool")
            break
        except Exception as exc:
            if attempt < 4:
                time.sleep(2)
            else:
                warn(f"Failed to associate resource with pool: {exc}")

    return resource_name, resource_id


def create_response_template(client, schema):
    header(4, "Create Response Template")

    # Re-run safety: reuse an existing template instead of duplicating it.
    try:
        for tmpl in client.access_broker.response_templates.list(search_text="Bridge") or []:
            if tmpl.get("name") == "Bridge":
                template_id = tmpl.get("templateId")
                success(f"Response template 'Bridge' already exists: {template_id}")
                return template_id
    except Exception as exc:
        warn(f"Could not check for an existing template ({exc}); attempting to create one.")

    info("Creating response template for clickable session URLs...")
    try:
        template = client.access_broker.response_templates.create(
            name="Bridge",
            description="Displays the Bridge session URL as a clickable link",
            template_data=f"{schema}://{{{{url}}}}",
            is_console_enabled=True,
        )
        template_id = template.get("templateId")
        success(f"Response template created: {template_id}")
        return template_id
    except Exception as exc:
        warn(f"Failed to create response template: {exc}")
        return None


def create_admin_profile(client, admin_permission):
    header(8, "Create Admin Profile")
    profile_name = f"Bridge {ADMIN_PROFILE['display']}"

    # Re-run safety: do not duplicate the profile.
    try:
        for prof in client.access_broker.profiles.list() or []:
            if prof.get("name") == profile_name:
                profile_id = prof.get("profileId") or prof.get("id")
                success(f"Profile '{profile_name}' already exists: {profile_id}")
                info("Association/permission left as-is — manage them in the Britive UI.")
                return {"name": profile_name, "id": profile_id, "protocol": ADMIN_PROFILE["name"]}
    except Exception as exc:
        warn(f"Could not check for an existing profile ({exc}); attempting to create one.")

    info(f"Creating profile '{profile_name}'...")
    try:
        profile = client.access_broker.profiles.create(
            name=profile_name,
            description=ADMIN_PROFILE["description"],
            expiration_duration=3600000,
        )
        profile_id = profile.get("profileId") or profile.get("id")
        success(f"  Profile created: {profile_id}")
    except Exception as exc:
        warn(f"  Failed to create profile: {exc}")
        return None

    try:
        client.access_broker.profiles.add_association(
            profile_id=profile_id,
            associations={"Resource-Type": ["Bridge"]},
        )
        success("  Resource type 'Bridge' associated")
    except Exception as exc:
        warn(f"  Failed to add resource association: {exc}")

    if admin_permission:
        try:
            client.access_broker.profiles.permissions.add_permissions(
                profile_id=profile_id,
                permission_id=admin_permission["id"],
                version="latest",
                resource_type_id=admin_permission["resource_type_id"],
                variables=ADMIN_PROFILE_VARIABLES,
            )
            success(f"  Permission 'admin' attached with {len(ADMIN_PROFILE_VARIABLES)} script parameters")
        except Exception as exc:
            warn(f"  Failed to add permission: {exc}")

    return {"name": profile_name, "id": profile_id, "protocol": ADMIN_PROFILE["name"]}


def print_summary(state):
    header(9, "Summary")

    print("  Created objects:")
    print(f"    Broker pool:       {state['pool_name']} ({state['pool_id']})")
    print(f"    Resource type:     Bridge ({state['bridge_type_id']})")
    print(f"    Resource:          {state['resource_name']} ({state['resource_id']})")
    if state["template_id"]:
        print(f"    Response template: Bridge ({state['template_id']})")
    print(f"    Admin profile:     {1 if state['created_profile'] else 0}")
    if state["created_profile"]:
        print(f"      - {state['created_profile']['name']} ({state['created_profile']['protocol']})")

    print()
    print_env_block(state["tenant_subdomain"], state["auth_token"])

    section_block("Next Steps")
    print("  1. Assign users or groups to the admin profile via")
    print("     policies so they can check out Bridge access.")
    print()
    if WARNING_COUNT:
        print(f"  Setup finished with {WARNING_COUNT} warning(s) — review the output")
        print("  above and resolve them before users check out Bridge access.")
        print()
    else:
        paragraph("Done! Users can now check out Bridge admin access at", state["bridge_url"])


# ---------------------------------------------------------------------------
# Main setup flow
# ---------------------------------------------------------------------------


def main():
    client, tenant = collect_tenant_credentials()
    pool_name, pool_id, auth_token = create_broker_pool_and_token(client)
    tenant_subdomain = tenant
    bridge_schema, bridge_url = collect_bridge_url(tenant_subdomain, auth_token)
    template_id = create_response_template(client, bridge_schema)
    bridge_type_id = create_bridge_resource_type(client)
    admin_permission = create_admin_permission(client, bridge_type_id, template_id)
    resource_name, resource_id = create_bridge_resource(client, bridge_type_id, bridge_url, pool_id)
    created_profile = create_admin_profile(client, admin_permission)
    print_summary(
        {
            "pool_name": pool_name,
            "pool_id": pool_id,
            "bridge_type_id": bridge_type_id,
            "resource_name": resource_name,
            "resource_id": resource_id,
            "template_id": template_id,
            "created_profile": created_profile,
            "tenant_subdomain": tenant_subdomain,
            "auth_token": auth_token,
            "bridge_url": bridge_url,
        }
    )


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n  Setup cancelled.\n")
        sys.exit(1)
