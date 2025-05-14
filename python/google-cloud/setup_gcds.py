#!/usr/bin/env python3
import json

# import google.auth
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

# OAuth 2.0 credentials JSON file path
CREDENTIALS_FILE = "path/to/credentials.json"

# Scopes required for the Admin SDK
SCOPES = ["https://www.googleapis.com/auth/admin.directory.rolemanagement"]


# Authenticate and initialize the Admin SDK service
def authenticate():
    creds = None
    if CREDENTIALS_FILE:
        flow = InstalledAppFlow.from_client_secrets_file(CREDENTIALS_FILE, SCOPES)
        creds = flow.run_local_server(port=0)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(CREDENTIALS_FILE, SCOPES)
            creds = flow.run_local_server(port=0)
    return creds


def create_custom_role(service, customer_id, role_name, role_privileges):
    role_body = {
        "roleName": role_name,
        "rolePrivileges": role_privileges,
    }

    request = service.roles().insert(customer=customer_id, body=role_body)
    response = request.execute()
    return response


def main():
    creds = authenticate()
    service = build("admin", "directory_v1", credentials=creds)

    # Replace these variables with your details
    customer_id = ""  # Use 'my_customer' or the actual customer ID
    custom_role_name = "BritiveDirectoryRole"
    custom_role_privileges = [
        {"privilegeName": "ORG_UNITS_READ", "serviceId": "admin"},
        {"privilegeName": "USER_READ", "serviceId": "admin"},
        {"privilegeName": "GROUP_READ", "serviceId": "admin"},
        {"privilegeName": "GROUP_UPDATE", "serviceId": "admin"},
    ]

    custom_role = create_custom_role(
        service, customer_id, custom_role_name, custom_role_privileges
    )
    print(f"Custom role created: {json.dumps(custom_role, indent=2)}")


if __name__ == "__main__":
    main()
