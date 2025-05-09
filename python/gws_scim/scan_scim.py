#! env python3
import argparse
import json
import logging
import os
import time
from dataclasses import dataclass, field

try:
    import tomllib as toml
except ModuleNotFoundError:
    import toml
from britive.britive import Britive

log_formatter = logging.Formatter('%(asctime)s %(levelname)-8s %(message)s')

console_handler = logging.StreamHandler()
console_handler.setFormatter(log_formatter)

root_logger = logging.getLogger()
root_logger.addHandler(console_handler)

with open('scan_config.toml') as config_file:
    scim_groups = toml.loads(config_file.read())

root_logger.setLevel(scim_groups.pop('log_level', os.getenv('LOG_LEVEL', 'INFO')))
britive = scim_groups.pop('britive', {})

b = Britive(
    tenant=britive.get('tenant', os.getenv('BRITIVE_TENANT')),
    token=britive.get('token', os.getenv('BRITIVE_API_TOKEN')),
    token_federation_provider=britive.get('federation_provider'),
)


class ExceedsUserDisablementCount(Exception):
    pass


class MissingApplicationGroups(Exception):
    pass


class MissingApplicationId(Exception):
    pass


class MissingEnvironmentScan(Exception):
    pass


class ScanError(Exception):
    pass


@dataclass
class TenantData:
    groups: dict = field(init=False, default_factory=dict)
    users: dict = field(init=False, default_factory=dict)

    def __post_init__(self):
        logging.debug('collecting tenant data')
        self._tags = b.identity_management.tags.list()
        self._users = b.identity_management.users.list(include_tags=True)
        self.app_id = britive.get('app_id')
        self.app_groups = {
            a['name']: {'desc': a['description'], 'id': a['appPermissionId']}
            for a in b.application_management.groups.list(
                application_id=self.app_id, include_associations=False, filter_expression='type eq group'
            )
        }
        self.britive_idp = b.identity_management.identity_providers.get_by_name('Britive')['id']
        self.idp_id = britive.get('idp_id', self.britive_idp)
        self.local_users = [u['username'] for u in self._users if u['identityProvider']['id'] == self.britive_idp]
        self._collect_tenant_data()

    def _collect_tenant_data(self):
        group_prefixes = tuple(p for k, v in scim_groups.items() for p in v.get('prefixes', []))
        for tag in self._tags:
            name = tag['name']
            if (not name.startswith(group_prefixes)) and name not in scim_groups:
                continue
            if tag['userTagIdentityProviders'][0]['identityProvider']['id'] != self.britive_idp:
                continue
            self.groups[name] = {'id': tag['userTagId'], 'users': []}
        for user in self._users:
            if user['identityProvider']['id'] != self.idp_id:
                continue

            username = user['username'].lower()
            user_tags = [
                tag['name']
                for tag in user.get('userTags', [])
                if tag['name'].startswith(group_prefixes) or tag['name'] in scim_groups
            ]

            for tag_name in user_tags:
                self.groups[tag_name]['users'].append(username)

            self.users[username] = {
                'username': username,
                'email': user['email'],
                'firstName': user['firstName'],
                'lastName': user['lastName'],
                'userId': user['userId'],
                'status': user['status'],
                'tags': user_tags,
            }


@dataclass
class ScanScim:
    name: str
    prefixes: tuple
    tenant: TenantData
    users: dict = field(default_factory=dict)
    groups: dict = field(default_factory=dict)

    def __post_init__(self):
        self.collect_scan_data()

    @staticmethod
    def _diff(source: dict | list, compare: dict | list) -> list:
        lower_compare = [i.lower() for i in compare]
        return [i for i in source if i.lower() not in lower_compare]

    def _get_users_for_group(self, group_id: int) -> list:
        return [
            u['accountName']
            for u in b.application_management.groups.accounts(group_id=group_id, application_id=self.tenant.app_id)
        ]

    def collect_scan_data(self) -> None:
        if not (app_group := self.tenant.app_groups.get(self.name)):
            raise MissingApplicationGroups('application user group(s) not found')

        groups = {k: v for k, v in self.tenant.app_groups.items() if k == self.name or k.startswith(self.prefixes)}
        app_group_users = [
            u for u in self._get_users_for_group(group_id=app_group['id']) if u not in self.tenant.local_users
        ]
        for name, details in groups.items():
            self.groups[name] = {
                'description': details['desc'],
                'users': [u for u in self._get_users_for_group(group_id=details['id']) if u in app_group_users],
            }
        for account in b.application_management.accounts.list(
            application_id=self.tenant.app_id, include_associations=False, filter_expression='type eq user'
        ):
            if (username := account['nativeName'].lower()) not in app_group_users:
                continue

            self.users[username] = {
                'username': username,
                'email': username,
                'firstName': account['firstName'],
                'lastName': account['lastName'],
            }

    def diff(self) -> dict:
        diff_output = {
            'users': {
                'create': [
                    (u, self.users[u], self.tenant.idp_id)
                    for u in self._diff(source=self.users, compare=self.tenant.users)
                ],
                'disable': self._diff(
                    source=[u for u, v in self.tenant.users.items() if v['status'] == 'active'], compare=self.users
                ),
                'enable': [u for u, v in self.tenant.users.items() if v['status'] == 'inactive' and u in self.users],
            },
            'tags': self._diff(source=self.groups, compare=self.tenant.groups),
            'entitlements': {
                'create': {},
                'remove': {},
            },
        }

        for group, details in self.groups.items():
            tenant_group_users = self.tenant.groups.get(group, {}).get('users', [])
            if entitlements_to_create := self._diff(source=details['users'], compare=tenant_group_users):
                diff_output['entitlements']['create'][group] = entitlements_to_create
            if entitlements_to_remove := self._diff(source=tenant_group_users, compare=details['users']):
                diff_output['entitlements']['remove'][group] = entitlements_to_remove

        logging.debug(json.dumps(diff_output, indent=2, default=str))
        return diff_output


def create_entitlements(entitlements: dict, tenant: TenantData) -> None:
    if not entitlements:
        logging.info('no entitlements to create')
        return
    logging.info('creating entitlements')
    for tag_name, usernames in entitlements.items():
        tag_id = tenant.groups[tag_name]['id']
        for username in usernames:
            user_id = tenant.users[username]['userId']
            b.identity_management.tags.add_user(tag_id=tag_id, user_id=user_id)
            logging.info(f'added {username} to {tag_name}')


def create_tags(tags: list, tenant: TenantData) -> None:
    if not tags:
        logging.info('no tags to create')
        return
    logging.info('creating tags')
    for name in tags:
        response = b.identity_management.tags.create(name=name)
        tenant.groups[name] = {
            'id': response['userTagId'],
            'users': [],
        }
        logging.info(f'created tag {name} with tag id {response["userTagId"]}')


def create_users(users: list, tenant: TenantData) -> None:
    if not users:
        logging.info('no users to create')
        return
    logging.info('creating users')
    for username, details, idp_id in users:
        tenant_user = tenant.users.get(username)
        if tenant_user:
            if tenant_user['status'] == 'active':
                logging.info(f'user {username} already exists and is active - skipping')
            if tenant_user['status'] == 'inactive':
                b.identity_management.users.enable(user_id=tenant_user['userId'])
                logging.info(f'user {username} already exists and was inactive - made active')
                continue
        response = b.identity_management.users.create(idp=idp_id, **details)
        new_fields = {
            'userId': response['userId'],
            'status': response['status'],
        }
        tenant.users[username] = {**details, **new_fields}
        logging.info(f'created user {username} with user id {response["userId"]}')


def enable_users(users: set, tenant: TenantData) -> None:
    if not users:
        logging.info('no users to enable')
        return
    logging.info('enabling users')
    for username in users:
        user_id = tenant.users[username]['userId']
        b.identity_management.users.enable(user_id=user_id)
        logging.info(f'enabled user {username}')


def disable_users(users: set, tenant: TenantData) -> None:
    if not users:
        logging.info('no users to disable')
        return
    logging.info('disabling users')
    for username in users:
        user_id = tenant.users[username]['userId']
        b.identity_management.users.disable(user_id=user_id)
        logging.info(f'disabled user {username}')


def process(
    confirm: bool = False,
    log_file: str = None,
    skip_scan: bool = False,
    user_cap: int = 10,
):
    if log_file:
        file_handler = logging.FileHandler(log_file)
        file_handler.setFormatter(log_formatter)
        root_logger.addHandler(file_handler)

    logging.info('starting processing')
    tenant = TenantData()
    action_items = []
    if not (app_id := britive.get('app_id')):
        raise MissingApplicationId('must supply an application ID')

    if not skip_scan:
        scan_application(app_id=app_id)

    logging.info('collecting scan data')
    for name, details in scim_groups.items():
        scan_scim = ScanScim(
            name=name,
            prefixes=tuple(p for p in details.get('prefixes', [])),
            tenant=tenant,
        )
        action_items.append(scan_scim.diff())

    users_to_create = []
    usernames_to_create = set()
    for user in (u for a in action_items for u in a['users']['create']):
        if user[0] not in usernames_to_create:
            usernames_to_create.add(user[0])
            users_to_create.append(user)
    logging.info(f'users to create: {json.dumps(usernames_to_create, default=list)}')
    users_to_enable = {u for a in action_items for u in a['users']['enable']}
    logging.info(f'users to enable: {json.dumps(users_to_enable, default=list)}')
    tags_to_create = [t for a in action_items for t in a['tags']]
    logging.info(f'tags to create: {json.dumps(tags_to_create, default=str)}')
    entitlements_to_create = {}
    for create_ents in [a['entitlements']['create'] for a in action_items]:
        for group, users in create_ents.items():
            entitlements_to_create.setdefault(group, set())
            entitlements_to_create[group] |= set(users)
    logging.info(f'entitlements to create: {json.dumps(entitlements_to_create, default=list)}')
    entitlements_to_remove = {}
    for remove_ents in [a['entitlements']['remove'] for a in action_items]:
        for group, users in remove_ents.items():
            entitlements_to_remove.setdefault(group, set())
            entitlements_to_remove[group] |= set(users)
    logging.info(f'entitlements to remove: {json.dumps(entitlements_to_remove, default=list)}')
    users_to_disable = set.intersection(*(set(a['users']['disable']) for a in action_items))
    logging.info(f'users to disable: {json.dumps(users_to_disable, default=list)}')

    if len(users_to_disable) > user_cap:
        raise ExceedsUserDisablementCount(
            f'performing actions would result in more than {user_cap} to be disabled so not performing any actions'
        )

    if confirm and input('Proceed (y/N)?\n').strip().lower() not in ['yes', 'y']:
        return

    create_users(users_to_create, tenant)
    enable_users(set(users_to_enable), tenant)
    create_tags(tags_to_create, tenant)
    create_entitlements(entitlements_to_create, tenant)
    remove_entitlements(entitlements_to_remove, tenant)
    disable_users(users_to_disable, tenant)


def remove_entitlements(entitlements: dict, tenant: TenantData) -> None:
    if not entitlements:
        logging.info('no entitlements to remove')
        return
    logging.info('removing entitlements')
    for tag_name, usernames in entitlements.items():
        tag_id = tenant.groups[tag_name]['id']
        for username in usernames:
            user_id = tenant.users[username]['userId']
            b.identity_management.tags.remove_user(tag_id=tag_id, user_id=user_id)
            logging.info(f'removed {username} to {tag_name}')


def scan_application(app_id: str) -> None:
    def _get_env_task_id_given_org_task_id(app_id: str, task_id: str) -> str:
        for scan in b.application_management.scans.history(
            application_id=app_id, filter_expression='scanType eq Environment'
        ):
            if scan['orgTaskId'] == task_id:
                return scan['taskId']
        raise MissingEnvironmentScan('unable to find environment scan task given org scan task id')

    def _wait_for_task_to_complete(task_id: str, scan_type: str) -> None:
        logging.info(f'waiting for {scan_type} scan to complete')
        while True:
            response = b.application_management.scans.status(task_id=task_id)
            status = response['status'].lower()
            if status == 'success':
                logging.debug(f'{scan_type} scan complete')
                break
            if status == 'error':
                error = response['error']
                logging.debug(f'{scan_type} scan error: {error}')
                raise ScanError(error)
            logging.debug(f'sleeping 10 seconds while waiting for {scan_type} scan to complete')
            time.sleep(10)

    logging.info('scanning applications')
    response = b.application_management.applications.scan(application_id=app_id)
    task_id = response['taskId']

    # this just waits for the org scan to complete
    _wait_for_task_to_complete(task_id=task_id, scan_type='org')

    # now we need to wait for env scan task to be created
    time.sleep(10)
    env_scan_task_id = _get_env_task_id_given_org_task_id(app_id=app_id, task_id=task_id)

    # and finally wait for the task to complete
    _wait_for_task_to_complete(task_id=env_scan_task_id, scan_type='env')


# UNCOMMENT THE FOLLOWING TO RUN INSIDE AN AWS LAMBDA FUNCTION

# def handler(event, context):
#     process()

# EVERYTHING BELOW HERE CAN BE REMOVED FOR LAMBDA USAGE


def main():
    parser = argparse.ArgumentParser(description='Python script to simulate SCIM actions based on Britive scan data.')
    parser.add_argument(
        '-u',
        '--user-cap',
        default=10,
        type=int,
        help='Threshold number of Britive users to allow automated disablement',
    )

    parser.add_argument('-c', '--confirm', action='store_true')

    parser.add_argument(
        '-s',
        '--skip-scan',
        action='store_true',
        help='Useful during debugging to skip repeatedly scanning the organization and environment(s)',
    )

    parser.add_argument(
        '-f',
        '--log-file',
        help='Absolute path for where to emit log entries to file - in addition to console logging.',
    )
    args = parser.parse_args()

    try:
        process(**vars(args))
    except Exception as e:
        logging.error(e)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt as kbe:
        raise SystemExit('...cancelled by user.') from kbe
