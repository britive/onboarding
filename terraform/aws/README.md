# Britive AWS integration — Terraform

Terraform equivalents of the CloudFormation templates in
[`../../cloudformation/aws/`](../../cloudformation/aws/). All three stacks
call one module, [`modules/britive-integration`](modules/britive-integration/),
which creates what Britive needs in an account: the SAML identity provider,
the integration role, and the optional session-invalidation, Access Builder
and AI-scanning permissions.

Prerequisites and the product side of onboarding are documented at
<https://docs.britive.com/docs/application-onboarding-guides>; each README
here links the outputs to the fields of the Britive application.

| Stack | Use it for | Scope |
| ----- | ---------- | ----- |
| [`single-account-stack/`](single-account-stack/) | One account: a standalone account, a POC, or the management account of an organization. `deploy_sample_roles = true` adds four demonstration JIT roles | 1 account |
| [`organization-stackset/`](organization-stackset/) | A whole AWS Organization: the management account directly plus every member account through a service-managed StackSet with auto-deployment | Management + member accounts |
| [`full-lab-setup/`](full-lab-setup/) | A disposable demo: integration, sample roles, and Linux/Windows/MySQL targets in their own VPC | 1 sandbox account |

There is no Terraform equivalent of the CloudFormation `stackset-templates/`
option (member accounts only); `organization-stackset/` covers that case and
the management account together.

## Common inputs

```hcl
tenant_name                        = "your-tenant"               # omit .britive-app.com
saml_metadata_document_xml_content = file("britive-saml-metadata.xml")  # or pass with -var on the command line
deploy_aws_invalidation_feature    = true

# management account only: the AWS Identity Center / AWS Account Access application types
deploy_identity_center         = false
deploy_account_access          = false
account_access_application_arn = ""      # arn:aws:account-access:<region>:<account>:application/<id>
```

The Identity Center and Account Access flags add their permissions to the
management account's integration role, as Britive's guides prescribe; the
prerequisites (enabling the account access manager, the trust policy Account
Access roles need) and the application fields are in
[`../../cloudformation/aws/README.md`](../../cloudformation/aws/README.md#aws-identity-center-and-aws-account-access).

The SAML metadata comes from **System Administration → Security → SAML
Configurations → Download SAML Metadata**. It identifies your tenant, so keep
the file out of version control (`.gitignore` already excludes `*.xml` under
`terraform/` and `cloudformation/`), but it holds only a public signing
certificate.

## Relationship to the CloudFormation templates

Each stack creates the same IAM resources as its CloudFormation counterpart:
the same names (`britive-<tenant>`, `britive-<tenant>-integration-role`), the
same managed policies and trust policy, the same optional invalidation
permissions. Variable names follow the CloudFormation parameter names and the
outputs carry the same values, so a Britive application configured from one
can be reproduced from the other. The organization stack even deploys the
CloudFormation member-account template as its StackSet body.

## Checks

```bash
for d in modules/britive-integration single-account-stack organization-stackset full-lab-setup; do
  terraform -chdir=$d init -backend=false >/dev/null && terraform -chdir=$d validate && tflint --chdir=$d
done
```
