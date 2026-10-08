# Service Control Policy for Britive-managed IAM paths

Britive's session-invalidation feature writes deny policies under
`arn:aws:iam::*:policy/britive/managed/*`, and Access Builder creates roles
under `arn:aws:iam::*:role/britive/managed/*`. Britive recommends an SCP in
the organization's management account so that **only the integration role**
can modify those paths — otherwise any principal with `iam:*` could remove an
invalidation policy or alter a Britive-managed role.
Reference: [Configuring for session invalidation](https://docs.britive.com/docs/configuring-for-session-invalidation).

[`britive-managed-policies-scp.json`](britive-managed-policies-scp.json)
contains both statements. Replace `<tenant>` with your tenant subdomain so the
condition names your integration role (`britive-<tenant>-integration-role`,
the name every template in this repository creates). Drop the second
statement if you do not use Access Builder.

```bash
sed 's/<tenant>/acme/g' britive-managed-policies-scp.json > scp.json

aws organizations create-policy \
  --name britive-managed-paths \
  --type SERVICE_CONTROL_POLICY \
  --description "Only the Britive integration role may modify Britive-managed policies and roles" \
  --content file://scp.json

aws organizations attach-policy --policy-id <p-xxxxxxxx> --target-id <root or OU id>
```

SCPs do not apply to the management account itself; the integration role
there is protected only by IAM. Attach the policy to the root or to the OUs
the StackSet deploys to.
