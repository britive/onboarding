from google.cloud import iam_v1
from google.oauth2 import service_account


# Run the following command to establish cli session with GCP admin account
# gcloud auth application-default login

# Replace these variables with your details
project_id = 'britive'
service_account_name = 'britive-service'
service_account_display_name = 'Britive Service'

# Initialize the IAM client
credentials = service_account.Credentials.from_service_account_file('./britive-service-account-key.json')
client = iam_v1.IAMClient(credentials=credentials)

# The service account's resource name
resource_name = f'projects/{project_id}'

# Create the service account
service_account = client.create_service_account(
    request={
        'name': resource_name,
        'account_id': service_account_name,
        'service_account': {
            'display_name': service_account_display_name
        }
    }
)

print(f'Service account {service_account.email} created.')
