#!/usr/bin/env python3
"""Bootstrap a Britive tenant from a YAML file: identity providers, users,
tags, applications with environments and profiles, notification mediums,
broker pools, and resource types with permissions, resources and profiles.

Environment (or .env next to this file): BRITIVE_TENANT, BRITIVE_API_TOKEN.
Input: a YAML file shaped like data_input-template.yaml (default
data_input.yaml next to this file, gitignored).

--dry-run prints what would be created and makes no write call.
"""

import argparse
import os
import secrets
import string
import sys
from pathlib import Path

import jmespath
import yaml
from colorama import Fore, Style
from dotenv import load_dotenv

from britive.britive import Britive

CAUTION = f"{Style.BRIGHT}{Fore.RED}"
WARN = f"{Style.BRIGHT}{Fore.YELLOW}"
INFO = f"{Style.BRIGHT}{Fore.BLUE}"
GREEN = f"{Style.BRIGHT}{Fore.GREEN}"
RESET = Style.RESET_ALL


class TenantBootstrap:
    def __init__(self, client: Britive | None, data: dict, dry_run: bool):
        self.br = client
        self.data = data
        self.dry_run = dry_run
        self._britive_idp_id = None

    # -- helpers -----------------------------------------------------------

    def _plan(self, message: str) -> bool:
        """Print the dry-run line and return True when no API call should follow."""
        if self.dry_run:
            print(f"{WARN}[dry-run] would {message}{RESET}")
        return self.dry_run

    @property
    def britive_idp_id(self) -> str:
        """ID of the tenant's local identity provider (named "Britive")."""
        if self._britive_idp_id is None:
            if self.dry_run:
                self._britive_idp_id = "simulated-britive-idp"
            else:
                idp = next((i for i in self.br.identity_management.identity_providers.list() if i["name"] == "Britive"), None)
                if not idp:
                    raise RuntimeError('identity provider "Britive" not found in the tenant')
                self._britive_idp_id = idp["id"]
        return self._britive_idp_id

    # -- entities ----------------------------------------------------------

    def idps(self) -> None:
        idps = jmespath.search("idps", self.data) or []
        print(f"{INFO}{len(idps)} identity providers{RESET}")
        for idp in idps:
            if self._plan(f"create identity provider {idp['name']}"):
                idp["id"] = f"simulated-{idp['name']}"
                continue
            response = self.br.identity_management.identity_providers.create(name=idp["name"], description=idp.get("description", ""))
            idp["id"] = response["id"]
            print(f"{GREEN}created identity provider {idp['name']}{RESET}")

    def users(self) -> None:
        users = jmespath.search("users", self.data) or []
        print(f"{INFO}{len(users)} users{RESET}")
        for user in users:
            if self._plan(f"create user {user['email']} on {user['idp']}"):
                continue
            idp_id = self.br.identity_management.identity_providers.get_by_name(user["idp"])["id"]
            # Random initial password; the user resets it through the invite
            # flow. Never printed.
            password = "".join(secrets.choice(string.ascii_letters + string.digits + "!#%&*-_") for _ in range(16))
            response = self.br.identity_management.users.create(
                idp=idp_id, email=user["email"], firstName=user["firstname"], lastName=user["lastname"],
                username=user["username"], status="active", password=password,
            )
            user["id"] = response["userId"]
            print(f"{GREEN}created user {user['email']}{RESET}")

    def tags(self) -> None:
        tags = jmespath.search("tags", self.data) or []
        print(f"{INFO}{len(tags)} tags{RESET}")
        for tag in tags:
            if self._plan(f"create tag {tag['name']}"):
                continue
            response = self.br.identity_management.tags.create(name=tag["name"], description=tag.get("description", ""), idp=self.britive_idp_id)
            tag["id"] = response["userTagId"]
            print(f"{GREEN}created tag {tag['name']}{RESET}")

    def applications(self) -> None:
        apps = jmespath.search("apps", self.data) or []
        print(f"{INFO}{len(apps)} applications{RESET}")
        catalog = {} if self.dry_run else {a["name"]: a["catalogAppId"] for a in self.br.application_management.applications.catalog()}
        for app in apps:
            if self._plan(f"create application {app['name']} of type {app['type']}"):
                app["id"] = f"simulated-{app['name']}"
                continue
            catalog_id = catalog.get(app["type"])
            if not catalog_id:
                raise RuntimeError(f"application type {app['type']!r} not in the catalog")
            response = self.br.application_management.applications.create(application_name=app["name"], catalog_id=catalog_id)
            app["id"] = response["appContainerId"]
            print(f"{GREEN}created application {app['name']}{RESET}")

    def profiles(self) -> None:
        apps = jmespath.search("apps", self.data) or []
        for app in apps:
            if "id" not in app:
                raise RuntimeError(f"application {app['name']} has no id; run --applications in the same invocation")
            for env in app.get("envs", []):
                if self._plan(f"create environment {env['name']} in {app['name']}"):
                    continue
                self.br.application_management.environments.create(application_id=app["id"], name=env["name"], description=env.get("description", ""))
                print(f"{GREEN}created environment {env['name']} in {app['name']}{RESET}")
            for profile in app.get("profiles", []):
                if self._plan(f"create profile {profile['name']} in {app['name']}"):
                    continue
                self.br.application_management.profiles.create(
                    application_id=app["id"], name=profile["name"], status="active",
                    expirationDuration=int(profile["Expiration"]),
                )
                print(f"{GREEN}created profile {profile['name']} in {app['name']}{RESET}")

    def notifications(self) -> None:
        mediums = jmespath.search("notification", self.data) or []
        print(f"{INFO}{len(mediums)} notification mediums{RESET}")
        for medium in mediums:
            if self._plan(f"create notification medium {medium['name']} ({medium['type']})"):
                continue
            self.br.global_settings.notification_mediums.create(
                notification_medium_type=medium["type"], name=medium["name"], url=medium["url"],
                token=medium.get("token"), description=medium.get("description"),
            )
            print(f"{GREEN}created notification medium {medium['name']}{RESET}")

    def broker_pools(self) -> None:
        pools = jmespath.search("brokerPools", self.data) or []
        print(f"{INFO}{len(pools)} broker pools{RESET}")
        for pool in pools:
            if self._plan(f"create broker pool {pool['name']}"):
                continue
            response = self.br.access_broker.pools.create(name=pool["name"], description=pool.get("description", ""))
            pool["id"] = response["pool-id"]
            print(f"{GREEN}created broker pool {pool['name']} ({pool['id']}){RESET}")

    def resource_types(self) -> None:
        types = jmespath.search("resourcesTypes", self.data) or []
        print(f"{INFO}{len(types)} resource types{RESET}")
        for rt in types:
            if self._plan(f"create resource type {rt['name']}"):
                rt["id"] = f"simulated-{rt['name']}"
            else:
                response = self.br.access_broker.resources.types.create(name=rt["name"], description=rt.get("description", ""))
                rt["id"] = response["resourceTypeId"]
                print(f"{GREEN}created resource type {rt['name']}{RESET}")

            for perm in rt.get("permissions", []):
                if not perm.get("name"):
                    print(f"{WARN}skipping permission without a name under {rt['name']}{RESET}")
                    continue
                if self._plan(f"create permission {perm['name']} under {rt['name']}"):
                    continue
                self.br.access_broker.resources.permissions.create(
                    resource_type_id=rt["id"], name=perm["name"], description=perm.get("description", ""),
                    variables=[v for v in perm.get("variables", []) if v],
                    checkout_file=perm.get("checkout") or None, checkin_file=perm.get("checkin") or None,
                )
                print(f"{GREEN}created permission {perm['name']} under {rt['name']}{RESET}")

            for resource in rt.get("resources", []):
                if self._plan(f"create resource {resource['name']} of type {rt['name']}"):
                    continue
                self.br.access_broker.resources.create(name=resource["name"], description=resource.get("description", ""), resource_type_id=rt["id"])
                print(f"{GREEN}created resource {resource['name']}{RESET}")

            for profile in rt.get("profiles", []):
                if self._plan(f"create resource profile {profile['name']} for type {rt['name']}"):
                    continue
                response = self.br.access_broker.profiles.create(
                    name=profile["name"], description=profile.get("description", ""),
                    expiration_duration=int(profile["Expiration"]),
                )
                self.br.access_broker.profiles.add_association(profile_id=response["profileId"], associations={"Resource-Type": rt["name"]})
                print(f"{GREEN}created resource profile {profile['name']}{RESET}")


def main() -> None:
    here = Path(__file__).parent
    load_dotenv(here / ".env")

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-i", "--idps", action="store_true", help="identity providers")
    parser.add_argument("-u", "--users", action="store_true", help="users")
    parser.add_argument("-t", "--tags", action="store_true", help="tags")
    parser.add_argument("-a", "--applications", action="store_true", help="applications")
    parser.add_argument("-p", "--profiles", action="store_true", help="environments and profiles (with --applications)")
    parser.add_argument("-n", "--notification", action="store_true", help="notification mediums")
    parser.add_argument("-b", "--broker-pools", action="store_true", help="broker pools")
    parser.add_argument("-r", "--resource-types", action="store_true", help="resource types, permissions, resources, resource profiles")
    parser.add_argument("--data-file", default=str(here / "data_input.yaml"), help="YAML input (default: data_input.yaml next to this script)")
    parser.add_argument("--dry-run", action="store_true", help="print the plan; make no write call")
    args = parser.parse_args()

    selected = [args.idps, args.users, args.tags, args.applications, args.profiles, args.notification, args.broker_pools, args.resource_types]
    if not any(selected):
        parser.error("nothing selected; pass one or more of -i -u -t -a -p -n -b -r")

    tenant, token = os.getenv("BRITIVE_TENANT"), os.getenv("BRITIVE_API_TOKEN")
    if not tenant or not token:
        parser.error("BRITIVE_TENANT and BRITIVE_API_TOKEN are required (environment or .env)")

    try:
        with open(args.data_file, encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
    except (OSError, yaml.YAMLError) as exc:
        sys.exit(f"{CAUTION}cannot read {args.data_file}: {exc}{RESET}")

    # A dry run never talks to the tenant, so it does not need (or validate) a client.
    client = None if args.dry_run else Britive(tenant=tenant, token=token)
    print(f"{INFO}tenant {tenant}{' (dry run)' if args.dry_run else ''}{RESET}")
    boot = TenantBootstrap(client, data, args.dry_run)

    steps = [
        (args.idps, boot.idps), (args.users, boot.users), (args.tags, boot.tags),
        (args.applications, boot.applications), (args.profiles, boot.profiles),
        (args.notification, boot.notifications), (args.broker_pools, boot.broker_pools),
        (args.resource_types, boot.resource_types),
    ]
    try:
        for enabled, step in steps:
            if enabled:
                step()
    except Exception as exc:  # noqa: BLE001 - surface any API error with context and a non-zero exit
        sys.exit(f"{CAUTION}failed: {exc}{RESET}")


if __name__ == "__main__":
    main()
