import argparse
import json
import logging
import os
import time

from britive.britive import Britive
from dotenv import load_dotenv


class ScanScim:
    def __init__(
        self,
        application_users_group_name: str,
        britive_group_prefix: str,
        application_id: str,
        identity_provider_id: str,
        britive_tenant: str = None,
        britive_token: str = None,
        token_federation_provider: str = None,
    ):
        self.application_users_group_name = application_users_group_name
        self.britive_group_prefix = britive_group_prefix
        self.application_id = application_id
        self.identity_provider_id = identity_provider_id
        self.britive_idp_name = 'Britive'
        self.b = Britive(
            tenant=britive_tenant,
            token=britive_token,
            token_federation_provider=token_federation_provider,
        )
        self.scan_users = {}
        self.scan_groups = {}
        self.tenant_users = {}
        self.tenant_groups = {}
        self.users_to_create = []
        self.users_to_disable = []
        self.users_to_enable = []
        self.tags_to_create = []
        self.entitlements_to_create = {}
        self.entitlements_to_remove = {}
        self.local_users = []

    def _group_matches(self, name: str):
        return (
            name.lower().startswith(self.britive_group_prefix.lower())
            or name.lower() == self.application_users_group_name.lower()
        )

    def collect_local_users(self):
        self.local_users = [
            u['username']
            for u in self.b.identity_management.users.list()
            if u['identityProvider']['name'] == self.britive_idp_name
        ]

    def _get_users_for_group(self, group_id: int) -> list:
        return [
            u['accountName']
            for u in self.b.application_management.groups.accounts(
                group_id=group_id, application_id=self.application_id
            )
        ]

    def _wait_for_task_to_complete(self, task_id: str, scan_type: str) -> None:
        logging.info(f'waiting for {scan_type} scan to complete')
        while True:
            response = self.b.application_management.scans.status(task_id=task_id)
            status = response['status'].lower()
            if status == 'success':
                logging.debug(f'{scan_type} scan complete')
                break
            if status == 'error':
                error = response['error']
                logging.debug(f'{scan_type} scan error: {error}')
                raise Exception(error)
            logging.debug(f'sleeping 10 seconds while waiting for {scan_type} scan to complete')
            time.sleep(10)

    def _get_env_task_id_given_org_task_id(self, task_id: str) -> str:
        env_scan_task_id = None
        for scan in self.b.application_management.scans.history(application_id=self.application_id):
            if scan['orgTaskId'] == task_id:
                env_scan_task_id = scan['taskId']
                break
        if not env_scan_task_id:
            raise Exception('unable to find environment scan task given org scan task id')
        return env_scan_task_id

    def scan_application(self):
        logging.info('scanning application')
        response = self.b.application_management.applications.scan(application_id=self.application_id)
        task_id = response['taskId']

        # this just waits for the org scan to complete
        self._wait_for_task_to_complete(task_id=task_id, scan_type='org')

        # now we need to wait for env scan task to be created
        time.sleep(10)
        env_scan_task_id = self._get_env_task_id_given_org_task_id(task_id=task_id)

        # and finally wait for the task to complete
        self._wait_for_task_to_complete(task_id=env_scan_task_id, scan_type='env')

    def collect_scan_data(self):
        logging.info('collecting scan data')

        self.collect_local_users()

        groups = [
            g
            for g in self.b.application_management.groups.list(
                application_id=self.application_id, include_associations=False
            )
            if g['type'] == 'group' and self._group_matches(name=g['name'])
        ]

        app_group = None
        for group in groups:
            if group['name'] == self.application_users_group_name:
                app_group = group
                break
        if not app_group:
            raise Exception('application users group not found')
        app_group_users = [
            u for u in self._get_users_for_group(group_id=app_group['appPermissionId']) if u not in self.local_users
        ]

        for group in groups:
            name = group['name']

            users = [u for u in self._get_users_for_group(group_id=group['appPermissionId']) if u in app_group_users]
            self.scan_groups[name] = {
                'description': group['description'],
                'users': users,
            }

        for account in self.b.application_management.accounts.list(
            application_id=self.application_id, include_associations=False
        ):
            if account['type'] != 'user':
                continue
            username = account['nativeName']
            if username not in app_group_users:
                continue

            self.scan_users[username] = {
                'username': username,
                'email': username,
                'firstName': account['firstName'],
                'lastName': account['lastName'],
            }

    def collect_tenant_data(self):
        logging.debug('collecting tenant data')
        for tag in self.b.identity_management.tags.list():
            name = tag['name']
            if not name.startswith(self.britive_group_prefix):
                continue
            if tag['userTagIdentityProviders'][0]['identityProvider']['name'] != self.britive_idp_name:
                continue
            self.tenant_groups[name] = {'id': tag['userTagId'], 'users': []}

        for user in self.b.identity_management.users.list(include_tags=True):
            if user['identityProvider']['id'] != self.identity_provider_id:
                continue
            username = user['username']
            self.tenant_users[username] = {
                'username': username,
                'email': user['email'],
                'firstName': user['firstName'],
                'lastName': user['lastName'],
                'userId': user['userId'],
                'status': user['status'],
            }

            user_tags = []
            for tag in user.get('userTags', []):
                name = tag['name']
                if not name.startswith(self.britive_group_prefix):
                    continue
                user_tags.append(name)
                self.tenant_groups[name]['users'].append(username)

            self.tenant_users[username]['tags'] = user_tags

    @staticmethod
    def _diff(source, compare):
        lower_compare = [i.lower() for i in compare]
        return [i for i in source if i.lower() not in lower_compare]

    def diff(self):
        logging.info('performing diff')
        self.users_to_create = self._diff(source=self.scan_users, compare=self.tenant_users)

        active_users = [u for u, v in self.tenant_users.items() if v['status'] == 'active']

        self.users_to_disable = self._diff(source=active_users, compare=self.scan_users)
        lower_scan_users = [i.lower() for i in self.scan_users]
        self.users_to_enable = [
            u for u, v in self.tenant_users.items() if v['status'] == 'inactive' and u.lower() in lower_scan_users
        ]

        self.tags_to_create = self._diff(source=self.scan_groups, compare=self.tenant_groups)

        for group, details in self.scan_groups.items():
            tag_users = self.tenant_groups.get(group, {}).get('users', [])
            entitlements_to_create = self._diff(source=details['users'], compare=tag_users)
            if len(entitlements_to_create) > 0:
                self.entitlements_to_create[group] = entitlements_to_create

        for tag, details in self.tenant_groups.items():
            scan_users = self.scan_groups.get(tag, {}).get('users', [])
            entitlements_to_remove = self._diff(source=details['users'], compare=scan_users)
            if len(entitlements_to_remove) > 0:
                self.entitlements_to_remove[tag] = entitlements_to_remove

    def create_users(self):
        logging.info('creating users')
        if len(self.users_to_create) == 0:
            logging.info('no users to create')
        for username in self.users_to_create:
            details = self.scan_users[username]

            tenant_user = self.tenant_users.get(username, None)
            if tenant_user:
                if tenant_user['status'] == 'active':
                    logging.info(f'user {username} already exists and is active - skipping')
                if tenant_user['status'] == 'inactive':
                    self.b.identity_management.users.enable(user_id=tenant_user['userId'])
                    logging.info(f'user {username} already exists and was inactive - made active')
                    continue

            response = self.b.identity_management.users.create(idp=self.identity_provider_id, **details)
            new_fields = {
                'userId': response['userId'],
                'status': response['status'],
            }
            self.tenant_users[username] = {**details, **new_fields}
            logging.info(f'created user {username} with user id {response["userId"]}')

    def create_tags(self):
        logging.info('creating tags')
        if len(self.tags_to_create) == 0:
            logging.info('no tags to create')
        for name in self.tags_to_create:
            response = self.b.identity_management.tags.create(name=name)
            self.tenant_groups[name] = {
                'id': response['userTagId'],
                'users': [],
            }
            logging.info(f'created tag {name} with tag id {response["userTagId"]}')

    def create_entitlements(self):
        logging.info('creating entitlements')
        if len(self.entitlements_to_create) == 0:
            logging.info('no entitlements to create')
        for tag_name, usernames in self.entitlements_to_create.items():
            tag_id = self.tenant_groups[tag_name]['id']
            for username in usernames:
                user_id = self.tenant_users[username]['userId']
                self.b.identity_management.tags.add_user(tag_id=tag_id, user_id=user_id)
                logging.info(f'added {username} to {tag_name}')

    def remove_entitlements(self):
        logging.info('removing entitlements')
        if len(self.entitlements_to_create) == 0:
            logging.info('no entitlements to remove')
        for tag_name, usernames in self.entitlements_to_remove.items():
            tag_id = self.tenant_groups[tag_name]['id']
            for username in usernames:
                user_id = self.tenant_users[username]['userId']
                self.b.identity_management.tags.remove_user(tag_id=tag_id, user_id=user_id)
                logging.info(f'removed {username} to {tag_name}')

    def disable_users(self):
        logging.info('disabling users')
        if len(self.users_to_disable) == 0:
            logging.info('no users to disable')
        for username in self.users_to_disable:
            user_id = self.tenant_users[username]['userId']
            self.b.identity_management.users.disable(user_id=user_id)
            logging.info(f'disabled user {username}')

    def enable_users(self):
        logging.info('enabling users')
        if len(self.users_to_enable) == 0:
            logging.info('no users to enable')
        for username in self.users_to_enable:
            user_id = self.tenant_users[username]['userId']
            self.b.identity_management.users.enable(user_id=user_id)
            logging.info(f'enabled user {username}')


def confirm():
    message = 'Proceed? (only "yes" is accepted) '
    while True:
        user_input = input(message).strip().lower()
        return user_input == 'yes'


def build_args():
    parser = argparse.ArgumentParser(description='Python script to simulate SCIM actions based on Britive scan data.')
    parser.add_argument(
        '-n',
        '--num-allowable-users-to-disable-before-error',
        default=10,
        type=int,
        help='Threshold on number of allowable Britive tenant users to disable before the script stop execution.',
    )

    parser.add_argument('--confirm', action=argparse.BooleanOptionalAction, default=True)

    parser.add_argument(
        '-f',
        '--log-file',
        help='Absolute path for where to emit log entries to file. Omitting means nothing will log to a file.',
    )

    return parser.parse_args()


def configure_logging(log_file: str):
    log_formatter = logging.Formatter('%(asctime)s %(levelname)-8s %(message)s')
    root_logger = logging.getLogger()
    root_logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

    if log_file:
        file_handler = logging.FileHandler(log_file)
        file_handler.setFormatter(log_formatter)
        root_logger.addHandler(file_handler)

    console_handler = logging.StreamHandler()
    console_handler.setFormatter(log_formatter)
    root_logger.addHandler(console_handler)


def process():
    load_dotenv()

    args = build_args()

    configure_logging(log_file=args.log_file)

    logging.info('starting processing')

    scan_scim = ScanScim(
        application_users_group_name='SSO-Britive',
        britive_group_prefix='britive-',
        application_id='6ipnod6fyq5co63fog2w',
        identity_provider_id='4thvwrd59luau6gc1lf7',
    )

    scan_scim.scan_application()
    scan_scim.collect_scan_data()
    scan_scim.collect_tenant_data()
    scan_scim.diff()

    logging.info(f'users to create: {json.dumps(scan_scim.users_to_create, default=str)}')
    logging.info(f'users to enable: {json.dumps(scan_scim.users_to_enable, default=str)}')
    logging.info(f'tags to create: {json.dumps(scan_scim.tags_to_create, default=str)}')
    logging.info(f'entitlements to create: {json.dumps(scan_scim.entitlements_to_create, default=str)}')
    logging.info(f'users to disable: {json.dumps(scan_scim.users_to_disable, default=str)}')
    logging.info(f'entitlements to remove: {json.dumps(scan_scim.entitlements_to_remove, default=str)}')

    if len(scan_scim.users_to_disable) > args.num_allowable_users_to_disable_before_error:
        raise Exception(
            'performing actions would result in more than '
            f'{args.num_allowable_users_to_disable_before_error} to be disabled so not '
            'performing any actions'
        )

    if args.confirm and not confirm():
        return

    scan_scim.create_users()
    scan_scim.enable_users()
    scan_scim.create_tags()
    scan_scim.create_entitlements()
    scan_scim.remove_entitlements()
    scan_scim.disable_users()


# lambda handler - in case this is run inside an AWS Lambda function - otherwise ignore/remove
def handler(event, context):
    try:
        process()
    except Exception as e:
        logging.error(str(e))


# run from command line
if __name__ == '__main__':
    handler(None, None)
