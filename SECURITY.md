# Security

## Reporting a vulnerability

Report problems in these templates and scripts privately through GitHub's
vulnerability reporting for this repository:
<https://github.com/britive/onboarding/security/advisories/new>. Do not open
a public issue or pull request for a security problem.

For a vulnerability in the Britive product itself, contact your Britive
account team or <https://support.britive.com>.

## What counts

- A template or script that grants more access than its README states
- A default that exposes a service to the internet, stores a secret in plain
  text, or logs a credential
- A real tenant name, account ID, token or key committed to this repository

## What this repository is

Examples and deployment assets for Britive customers. They are reviewed, but
they are not a supported product: run them in a non-production account
first, read what a template creates before deploying it, and keep every
secret in a secret store. The `.github/scripts/repo-checks.sh` script, run on
every change, rejects identifiers that should never be published.
