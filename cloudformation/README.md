# CloudFormation

Templates for the resources Britive needs in AWS. Everything lives under
[`aws/`](aws/); start with [`aws/README.md`](aws/README.md).

| Option | Scope |
| ------ | ----- |
| [`aws/single-account-stack/`](aws/single-account-stack/) | One account: standalone, POC, or an organization's management account |
| [`aws/stackset-templates/`](aws/stackset-templates/) | Member accounts under one or more OUs, with auto-deployment |
| [`aws/organization-stackset/`](aws/organization-stackset/) | Management account and member accounts in one stack |
| [`aws/full-lab-setup/`](aws/full-lab-setup/) | Disposable demo: integration, sample roles, Linux/Windows/MySQL targets |

All four use (or embed) one template,
[`aws/britive_integration_resources.yaml`](aws/britive_integration_resources.yaml).
The Terraform equivalents are under [`../terraform/aws/`](../terraform/aws/).

Prerequisites and the product side of onboarding are documented at
<https://docs.britive.com/docs/application-onboarding-guides>.
