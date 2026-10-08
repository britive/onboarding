#!/usr/bin/env python3
"""Create the Google Workspace admin role Britive's service account needs for
directory sync (GCDS) in GCP key mode: read organization units, users and
groups, update groups. Matches docs.britive.com/docs/cis-custom-role-gcds.

Authentication: an OAuth client (desktop) JSON from the Google Cloud console
with the Admin SDK API enabled; a browser window opens for a Workspace super
administrator to consent. The identity needs the Role Management privilege.
"""

import argparse
import json
import sys

from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

SCOPES = ["https://www.googleapis.com/auth/admin.directory.rolemanagement"]

# Privilege names as the Admin SDK reports them (privileges.list), all under
# the Admin SDK Directory service.
PRIVILEGE_NAMES = [
    "ORGANIZATION_UNITS_RETRIEVE",
    "USERS_RETRIEVE",
    "GROUPS_RETRIEVE",
    "GROUPS_UPDATE",
]


def resolve_privileges(service, customer_id: str) -> list[dict]:
    """Look up the serviceId each privilege belongs to; names alone are not accepted."""
    wanted = set(PRIVILEGE_NAMES)
    found = {}

    def walk(items):
        for item in items:
            if item.get("privilegeName") in wanted:
                found[item["privilegeName"]] = item["serviceId"]
            walk(item.get("childPrivileges", []))

    walk(service.privileges().list(customer=customer_id).execute().get("items", []))
    missing = wanted - found.keys()
    if missing:
        raise RuntimeError(f"privileges not found in this Workspace: {', '.join(sorted(missing))}")
    return [{"privilegeName": name, "serviceId": found[name]} for name in PRIVILEGE_NAMES]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--client-secrets", required=True, help="OAuth client JSON (desktop app) from the Google Cloud console")
    parser.add_argument("--customer-id", default="my_customer", help="Workspace customer ID (default: my_customer = the signed-in domain)")
    parser.add_argument("--role-name", default="BritiveDirectoryRole", help="admin role name (default BritiveDirectoryRole)")
    args = parser.parse_args()

    flow = InstalledAppFlow.from_client_secrets_file(args.client_secrets, SCOPES)
    credentials = flow.run_local_server(port=0)
    service = build("admin", "directory_v1", credentials=credentials)

    try:
        privileges = resolve_privileges(service, args.customer_id)
        role = service.roles().insert(
            customer=args.customer_id,
            body={"roleName": args.role_name, "roleDescription": "Britive directory sync (GCDS)", "rolePrivileges": privileges},
        ).execute()
    except HttpError as exc:
        if exc.resp.status == 409:
            sys.exit(f"role {args.role_name} already exists")
        sys.exit(f"Admin SDK error: {exc}")
    except RuntimeError as exc:
        sys.exit(str(exc))

    print(json.dumps(role, indent=2))
    print("\nAssign the role to Britive's service account user in the Admin console, or with")
    print(f"roleAssignments.insert (roleId {role['roleId']}).")


if __name__ == "__main__":
    main()
