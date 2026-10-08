# Britive onboarding

Deployment assets for connecting [Britive](https://www.britive.com) to your cloud accounts, identity providers and infrastructure: CloudFormation and Terraform templates, SDK scripts, container images and the guides that go with them. Everything here runs in **your** environment; the product side of each integration is documented in the [application onboarding guides](https://docs.britive.com/docs/application-onboarding-guides) on docs.britive.com, and each README below links the guide it implements.

Each directory is one deployment option with its own `README.md` and an example parameter file. Copy the example, fill in your values, deploy.

## Start here

| I want to | Go to |
| --------- | ----- |
| Connect one AWS account (POC, standalone, or a management account) | [`cloudformation/aws/single-account-stack/`](cloudformation/aws/single-account-stack/) or [`terraform/aws/single-account-stack/`](terraform/aws/single-account-stack/) |
| Connect every account in an AWS Organization | [`cloudformation/aws/organization-stackset/`](cloudformation/aws/organization-stackset/) or [`terraform/aws/organization-stackset/`](terraform/aws/organization-stackset/) |
| Broker IAM Identity Center permission sets, or account access manager entitlements | The same AWS stacks in the management account with the Identity Center / Account Access flags — see [`cloudformation/aws/`](cloudformation/aws/#aws-identity-center-and-aws-account-access) |
| Try Britive on AWS with disposable Linux, Windows and MySQL targets | [`cloudformation/aws/full-lab-setup/`](cloudformation/aws/full-lab-setup/) or [`terraform/aws/full-lab-setup/`](terraform/aws/full-lab-setup/) |
| Connect Google Cloud, keyless (workload identity federation) or with a key | [`terraform/google-cloud/`](terraform/google-cloud/) |
| Connect Snowflake | [`terraform/snowflake/`](terraform/snowflake/) |
| Connect OCI, Azure, or Google Cloud projects with a script | [`python/`](python/) |
| Give users just-in-time access to servers, databases and Kubernetes clusters | [`access-broker/`](access-broker/) |
| Let users reach brokered resources through a browser or native client without seeing credentials | [`bridge/`](bridge/) |
| Manage Britive itself as code: tags, profiles, policies | [`terraform/britive/`](terraform/britive/) |
| Bootstrap a new tenant or POC from one YAML file | [`python/britive/`](python/britive/) |

## What is where

| Directory | Contents |
| --------- | -------- |
| [`cloudformation/`](cloudformation/) | AWS integration: one template for the SAML provider and integration role, deployed as a single stack, a StackSet, or organization-wide; a demo lab; a sample SCP |
| [`terraform/`](terraform/) | The same AWS integration as a module; Google Cloud (WIF or key) with the optional Britive application; Google Workspace admin user; Snowflake role and user; Britive provider examples |
| [`python/`](python/) | Britive SDK scripts: AWS, Google Cloud, OCI, Google Workspace SCIM, tenant bootstrap |
| [`access-broker/`](access-broker/) | Access Broker 3.x: container image, Docker Compose, Linux VM, ECS Fargate, Kubernetes Helm chart |
| [`bridge/`](bridge/) | Britive Bridge v2: platform setup, custom image, ECS Fargate with NLB, Docker Compose |
| [`kubernetes/`](kubernetes/) | Kubernetes just-in-time access: quick-start cluster and RBAC |
| [`third-party-tool-integrations/`](third-party-tool-integrations/) | Checked-out credentials in DBeaver and MobaXterm with `pybritive` |
| [`session-recording/`](session-recording/) | Legacy session-recording proxy, kept for existing deployments; new deployments use Bridge |

## Before you deploy

- **A Britive tenant** and a user with the administrator rights the relevant guide lists; scripts and the Britive provider also need an [API token](https://docs.britive.com/docs/api-tokens-1).
- **Placeholders.** Every file uses `your-tenant`, `<account>`, `<region>` and `example.com`. Replace them in your copy. Never commit a token, an account ID, a hostname or a key: the repository's CI rejects known identifier patterns, but it cannot know yours.
- **Versions.** Templates are tested against the Access Broker, Bridge and provider versions named in each README. Anything older than Access Broker 3.x and Bridge v2 is out of support.

## Related documentation

- [Application onboarding guides](https://docs.britive.com/docs/application-onboarding-guides): prerequisites and console steps for every application type
- [Access Broker](https://docs.britive.com/docs/access-broker) and [Bridge](https://docs.britive.com/docs/bridge-extension) product documentation
- [Terraform provider](https://registry.terraform.io/providers/britive/britive/latest/docs), [Python SDK](https://github.com/britive/python-sdk) and [pybritive CLI](https://github.com/britive/python-cli)
- Broker checkout and check-in scripts for specific targets: [britive/access-broker-examples](https://github.com/britive/access-broker-examples)

## Support

Problems with an asset here: open a [GitHub issue](https://github.com/britive/onboarding/issues) with the directory and the error. Problems with your tenant or an integration: Britive support, through your usual support channel. Security findings: see [SECURITY.md](SECURITY.md); do not open a public issue.

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under the [MIT License](LICENSE).
