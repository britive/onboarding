#!/usr/bin/env python3
"""Create the service account and the custom role for a Britive **GCP
Standalone** application (one project), and bind the role on that project.

The role carries the 19 permissions Britive documents for the
projects-only integration (docs.britive.com/docs/creating-a-custom-role-for-gcp-standalone-application).
For an organization-level application or Workload Identity Federation use
terraform/google-cloud/ in this repository instead.

Authentication: Application Default Credentials (gcloud auth
application-default login), or --credentials <service-account-key.json>.
The identity needs iam.serviceAccounts.create, iam.roles.create and
resourcemanager.projects.setIamPolicy on the project.
"""

import argparse
import sys
import time

import google.auth
from google.oauth2 import service_account
from googleapiclient import discovery
from googleapiclient.errors import HttpError

SCOPES = ["https://www.googleapis.com/auth/cloud-platform"]

# docs.britive.com/docs/creating-a-custom-role-for-gcp-standalone-application
ROLE_PERMISSIONS = [
    "bigquery.datasets.get",
    "iam.roles.get",
    "iam.roles.list",
    "iam.serviceAccountKeys.create",
    "iam.serviceAccountKeys.delete",
    "iam.serviceAccountKeys.get",
    "iam.serviceAccountKeys.list",
    "iam.serviceAccounts.create",
    "iam.serviceAccounts.delete",
    "iam.serviceAccounts.disable",
    "iam.serviceAccounts.enable",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.list",
    "iam.serviceAccounts.setIamPolicy",
    "iam.serviceAccounts.undelete",
    "iam.serviceAccounts.update",
    "resourcemanager.projects.get",
    "resourcemanager.projects.getIamPolicy",
    "resourcemanager.projects.setIamPolicy",
]


class BritiveGcpProject:
    def __init__(self, project_id: str, service_account_name: str, display_name: str, role_id: str, credentials_file: str | None):
        self.project_id = project_id
        self.service_account_name = service_account_name
        self.display_name = display_name
        self.role_id = role_id
        if credentials_file:
            credentials = service_account.Credentials.from_service_account_file(credentials_file, scopes=SCOPES)
        else:
            credentials, _ = google.auth.default(scopes=SCOPES)
        self.iam = discovery.build("iam", "v1", credentials=credentials)
        self.crm = discovery.build("cloudresourcemanager", "v1", credentials=credentials)

    @property
    def service_account_email(self) -> str:
        return f"{self.service_account_name}@{self.project_id}.iam.gserviceaccount.com"

    def ensure_service_account(self) -> None:
        name = f"projects/{self.project_id}/serviceAccounts/{self.service_account_email}"
        try:
            self.iam.projects().serviceAccounts().get(name=name).execute()
            print(f"service account {self.service_account_email} exists")
            return
        except HttpError as exc:
            if exc.resp.status != 404:
                raise
        self.iam.projects().serviceAccounts().create(
            name=f"projects/{self.project_id}",
            body={"accountId": self.service_account_name, "serviceAccount": {"displayName": self.display_name}},
        ).execute()
        print(f"created service account {self.service_account_email}")

    def ensure_role(self) -> str:
        role_name = f"projects/{self.project_id}/roles/{self.role_id}"
        body = {
            "roleId": self.role_id,
            "role": {
                "title": "Britive Integration (projects only)",
                "description": "Permissions Britive needs to scan a project and manage service account keys",
                "includedPermissions": ROLE_PERMISSIONS,
                "stage": "GA",
            },
        }
        try:
            self.iam.projects().roles().create(parent=f"projects/{self.project_id}", body=body).execute()
            print(f"created role {role_name}")
            time.sleep(5)  # let the new role propagate before binding it
        except HttpError as exc:
            if exc.resp.status != 409:
                raise
            self.iam.projects().roles().patch(name=role_name, body=body["role"], updateMask="includedPermissions,title,description").execute()
            print(f"role {role_name} exists; permissions refreshed")
        return role_name

    def ensure_binding(self, role_name: str) -> None:
        member = f"serviceAccount:{self.service_account_email}"
        # Version 3 keeps conditional bindings intact; the etag guards against
        # overwriting a concurrent change.
        policy = self.crm.projects().getIamPolicy(resource=self.project_id, body={"options": {"requestedPolicyVersion": 3}}).execute()
        policy["version"] = 3
        for binding in policy.get("bindings", []):
            if binding["role"] == role_name and "condition" not in binding:
                if member in binding["members"]:
                    print(f"{member} already has {role_name}")
                    return
                binding["members"].append(member)
                break
        else:
            policy.setdefault("bindings", []).append({"role": role_name, "members": [member]})
        self.crm.projects().setIamPolicy(resource=self.project_id, body={"policy": policy}).execute()
        print(f"granted {role_name} to {member}")

    def run(self) -> None:
        self.ensure_service_account()
        role_name = self.ensure_role()
        self.ensure_binding(role_name)
        print("\nNext: create a JSON key for the service account and upload it when creating the")
        print("GCP Standalone application in Britive (System Administration > Tenant Applications):")
        print(f"  gcloud iam service-accounts keys create britive-key.json --iam-account {self.service_account_email}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-p", "--project-id", required=True, help="project the application will manage")
    parser.add_argument("-s", "--service-account-name", default="britive-service", help="service account ID (default britive-service)")
    parser.add_argument("-d", "--display-name", default="Britive Service", help="service account display name")
    parser.add_argument("-r", "--role-id", default="BritiveIntegrationRole", help="custom role ID (default BritiveIntegrationRole)")
    parser.add_argument("--credentials", help="service account key file; default: Application Default Credentials")
    args = parser.parse_args()
    try:
        BritiveGcpProject(args.project_id, args.service_account_name, args.display_name, args.role_id, args.credentials).run()
    except HttpError as exc:
        sys.exit(f"Google API error: {exc}")


if __name__ == "__main__":
    main()
