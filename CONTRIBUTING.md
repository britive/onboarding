# Contributing

This repository is public and read by Britive customers and prospects.
Clarity and correctness matter more than brevity.

## Layout rules

- **One directory per deployment option**, each with its own `README.md`
  covering prerequisites, deploy, verify and teardown, and a parameter or
  values example file (`params.example.json`, `terraform.tfvars.example`,
  `.env.example`, `values.example.yaml`).
- **Placeholders only.** `your-tenant`, `<account>`, `<region>`,
  `example.com`, `123456789012`. Never a real tenant subdomain, account ID,
  ARN, hostname, token, key or Slack URL. Templates copied out of a working
  deployment must be scrubbed; that is where leaks come from.
- **Pin versions.** Image tags, provider versions, package versions. Never
  `latest`.
- **Secrets never sit in tracked files or in plain environment entries on a
  task definition.** Use a secret store (Secrets Manager, Key Vault, Secret
  Manager, Kubernetes Secret) or an ignored `.env`.
- Commit messages are plain prose that explain why, with no tooling
  attribution lines.

## Before opening a pull request

```bash
.github/scripts/repo-checks.sh                 # whole repository
.github/scripts/changed-checks.sh origin/main  # the files you touched
```

The first needs `shellcheck` and `cfn-lint`; the second needs `ruff`,
`yamllint`, `terraform`, `tflint` and `helm`. CI runs both.

Verify what you built the way a customer would: deploy it, run a checkout,
tear it down. Say in the pull request what you ran and what it printed.

## What belongs here

Deployment assets: CloudFormation and Terraform templates, container images,
Helm charts, install scripts, SDK examples. Prerequisites and product steps
are documented at
<https://docs.britive.com/docs/application-onboarding-guides> and are linked,
not duplicated. Checkout/checkin scripts for resource types belong in
<https://github.com/britive/access-broker-examples>.
