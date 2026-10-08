# Module: britive-integration

The resources Britive needs in an AWS account, in one place: the SAML identity
provider, the integration role with `IAMReadOnlyAccess` and
`AWSOrganizationsReadOnlyAccess`, and the optional permissions for session
invalidation, Access Builder and AI identity scanning. The three stacks in
[`../../`](../../) are thin callers of this module.

Product documentation: [Configuring the identity provider](https://docs.britive.com/docs/configuring-identity-provider),
[Configuring IAM roles](https://docs.britive.com/docs/configuring-iam-roles),
[Session invalidation](https://docs.britive.com/docs/configuring-for-session-invalidation).

```hcl
module "britive" {
  source = "../modules/britive-integration"

  tenant_name                        = "acme"
  saml_metadata_document_xml_content = file("britive-saml-metadata.xml")

  deploy_aws_invalidation_feature = true   # default
  deploy_access_builder           = false  # roles under role/britive/managed/*
  deploy_ai_identity_scanning     = false  # AmazonBedrockReadOnly
  deploy_sample_roles             = false  # four demo JIT roles
}
```

| Input | Default | Meaning |
| ----- | ------- | ------- |
| `tenant_name` | — | Tenant subdomain; names the provider `britive-<tenant>` and the role `britive-<tenant>-integration-role` |
| `saml_metadata_document_xml_content` | — | The metadata XML (contents, not a path) |
| `deploy_aws_invalidation_feature` | `true` | `iam:*Policy*` on `policy/britive/managed/*` in this account |
| `deploy_access_builder` | `false` | `iam:*Role*` on `role/britive/managed/*` in this account |
| `deploy_ai_identity_scanning` | `false` | Attach `AmazonBedrockReadOnly` |
| `max_session_duration` | `3600` | Integration role session length; enter the same value in hours as *Duration of backend connection* in Britive |
| `deploy_sample_roles` | `false` | `Readonly-admin-role`, `Poweruser-role`, `EC2-Fullaccess-role`, `S3-Fullaccess-role` |

Outputs map directly onto the fields of the Britive AWS application:
`account_id`, `saml_provider_name` (*Identity Provider Name*),
`integration_role_name` (*Integration Role Name*),
`backend_connection_duration_hours` (*Duration of backend connection*), plus
the ARNs and `sample_role_arns`.

Every role trusts the SAML provider for `sts:AssumeRoleWithSAML`,
`sts:SetSourceIdentity` and `sts:TagSession` with `SAML:aud` pinned to
`https://signin.aws.amazon.com/saml`. Roles you create for Britive to broker
need the same trust policy; a role without `sts:SetSourceIdentity` fails to
check out once a Source Identity attribute is configured on the application.

When session invalidation is enabled, apply the SCP in
[`../../../../cloudformation/aws/scp/`](../../../../cloudformation/aws/scp/)
from the organization's management account so only the integration role can
modify policies under `policy/britive/managed/*`.
