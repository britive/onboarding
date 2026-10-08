## What this changes

<!-- One paragraph. Which directory, what a customer can now do that they could not before. -->

## How it was verified

<!-- The commands you ran and what they printed. "Deployed to a test account and ran a checkout" beats "should work". -->

## Checklist

- [ ] No real tenant name, account ID, ARN, hostname, token or key anywhere in the diff — placeholders only (`your-tenant`, `<account>`, `example.com`)
- [ ] Every new directory has a `README.md` with prerequisites, deploy, verify and teardown
- [ ] Image references are pinned to a version tag, never `latest`
- [ ] Secrets reach the runtime through a secret store or an ignored `.env`, never a tracked file or a plain environment entry on a task definition
- [ ] `.github/scripts/repo-checks.sh` passes locally
- [ ] Links into this repository from learn.britive.com still resolve, or the change lists which ones move
