import os
import time
from britive.britive import Britive
from britive.helpers.utils import source_federation_token
import json
import argparse

# attempt to get the token from an env var (for local testing mostly)
# and if not available assume we are running in a github action
# so grab a workload federation token instead

github_token_start_time = 0


def build_britive_client():
    global b
    global github_token_start_time

    if github_action_env:
        now = int(time.time())
        if now - github_token_start_time > (4*60):  # if token is 4+ minutes old change it
            oidc_token = source_federation_token(provider='github-britive', tenant=tenant)
            b = Britive(tenant=tenant, token=oidc_token, query_features=False)
            if github_token_start_time > 0:
                print('refreshed oidc token')
            github_token_start_time = now


tenant = 'demo'
static_token_for_testing = os.getenv('BRITIVE_API_TOKEN', 'throwaway')
github_action_env = False

if 'BRITIVE_API_TOKEN' not in os.environ.keys():
    github_action_env = True
b = Britive(tenant=tenant, token=static_token_for_testing, query_features=False)


# tag names for profile policies
tag_cloudops = 'CloudOps'
tag_helpdesk = 'Help Desk'

def create_application(application_name):
    flush_print('creating aws application')
    # get the catalog of applications we can create
    apps = b.application_management.applications.catalog()
    catalog = {}
    for app in apps:
        catalog[app['key']] = app

    # find the catalog_id of the app we want to create (AWS 2.0)
    catalog_id = catalog['AWS-2.0']['catalogAppId']

    # create the application
    app_id = b.application_management.applications.create(
        catalog_id=catalog_id,
        application_name=application_name
    )['appContainerId']

    # update the application with the required details
    b.application_management.applications.update(
        application_id=app_id,
        showAwsAccountNumber=True,
        identityProvider=idp_name,
        roleName=integration_role_name,
        accountId=management_account_id
    )

    flush_print(f'created and configured aws application with id {app_id}')
    return app_id
