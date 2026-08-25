# CLAUDE.md — britive/onboarding

Guidance for coding agents. This repo is **public** on GitHub.

## What this repo is

Customer-facing onboarding assets: CloudFormation and Terraform templates,
deployment guides, and example scripts for standing up Britive integrations.
Everything here is read and run by customers, so clarity and correctness matter
more than brevity.

| Path | What |
|---|---|
| `cloudformation/aws/` | **AWS SAML integration** — SAML provider + integration role. Single account, StackSets, org-wide, and a demo lab. Not Bridge. |
| `Britive Bridge/` | **Bridge deployments**, split by major version — see below |
| `Access Broker/` | Broker deployments (ECS, EKS, GKE, AKS) |
| `terraform/`, `python/`, `bash/` | Provider examples, SDK scripts, helpers |
| `kubernetes/`, `session-recording/`, `third-party-tool-integrations/` | Topic-specific assets |

## The Bridge v1 / v2 split — read before touching `Britive Bridge/`

```
Britive Bridge/
├── platform-setup/     shared — creates broker pool + token (run FIRST)
├── custom-image/       shared image builder for BOTH versions
├── v1/                 Bridge v1.x - LEGACY, existing deployments only
└── v2/                 Bridge v2.x - current, use for all new work
```

**v1 is legacy.** Point anything new at `v2/`. `v1/` is kept so deployments
already running v1 stay reproducible.

**Never reference `britive/bridge:latest`.** That tag tracks the newest release
across major versions - it resolves to v2.1.0 today. A v1 template pointed at
it pulls a v2 image and crash-loops on the missing datastore, which is exactly
what the v1 templates used to default to. Pin explicitly: `v1.0.2` is the only
published v1 tag; v2 uses specific `v2.x` tags. The one remaining `latest` is
`custom-image/Dockerfile`'s `BASE_IMAGE` default, kept for backwards
compatibility, which is why every documented build passes `BASE_IMAGE`
explicitly.

**They are not interchangeable.** A v1 template cannot run a v2 image. Bridge
v2 additionally requires:

1. **A PostgreSQL datastore.** The task will not start without one.
2. **A permanent encryption key** (`openssl rand -base64 32`). Rotating it after
   go-live makes every stored checkout payload undecryptable.
3. **Configuration baked into the image.** Every protocol is off by default and
   the Bridge refuses to start unless at least one is enabled. The tenant is
   validated from the *file* before environment overrides apply, so
   `BRITIVE_TENANT` alone is not sufficient.

Because of (3), a config change is an image change: new tag, then update the
stack's `ImageUri`.

### The shared image builder

`custom-image/` serves both versions. v1 uses it bare; v2 adds two build args:

```bash
docker build \
  --build-arg BASE_IMAGE=britive/bridge:v2.1.0 \
  --build-arg BAKE_CONFIG=true \      # required for v2
  --build-arg WITH_RDS_CA=true \      # trust AWS RDS CAs for target_tls=true
  -t <registry>/britive/bridge:v2.1.0-r1 .
```

`BAKE_CONFIG` copies `custom-image/bridge.yaml` to
`/etc/britive-bridge/config.yaml`. The build fails if the tenant is still the
`your-tenant` placeholder.

## Conventions

- **One directory per deployment option**, each with its own `README.md` and a
  parameter file. Follow the structure of the directory you are adding to.
- **Parameter files are named `params.example.json`** under `Britive Bridge/`.
  Note `.gitignore` ignores `parameters.json` repo-wide — a file with that name
  will silently not be committed.
- Templates use the `britive_*` prefix under `cloudformation/aws/`, and
  descriptive names (`ecs-fargate-nlb.yaml`) under `Britive Bridge/`.
- `.claude/` is gitignored at every depth. Do not commit agent state.

## Never commit

Real hostnames, AWS account IDs, ARNs from live environments, tenant
subdomains, tokens, or private keys. Use `example.com`, `<account>`,
`<region>`, `your-tenant`. Templates copied out of a working deployment must be
scrubbed — that is where these leak from.

## Gotchas worth preserving in docs

Each of these fails in a way that does not point at its cause, so they are
documented deliberately in the affected READMEs:

- **Image architecture must match `CpuArchitecture`.** A mismatch shows up as a
  Fargate task that starts and immediately stops, with no application log line
  explaining why.
- **Stack updates must pass `UsePreviousValue=true` for every unchanged
  parameter.** Re-submitting a parameter file sends empty strings for `NoEcho`
  parameters, blanking the stored encryption key, broker token and SSH key.
- **ECS caps a service at 5 load-balancer registrations.** One goes to the web
  tier, leaving four native protocol listeners. Enabling a native protocol in
  `bridge.yaml` without a matching NLB listener yields a connect command that
  looks valid and never works.
- **`update-ca-certificates` warns** `does not contain exactly one certificate
  or CRL: skipping` for the RDS bundle. That is expected and harmless — it
  refers only to per-certificate hash symlinks; the certificates are still
  concatenated into `ca-certificates.crt`, which is what the Go proxy reads.
  Verify by **counting** certificates, never by grepping the trust store for
  subject text — that file contains no subject lines, so such a grep always
  fails and looks like a real problem.
- **During an ECS deployment both brokers stay registered** with the tenant for
  several minutes while the old task drains, and Britive load-balances across
  them. A checkout can be served by the draining task running the old image.

## Verifying changes

```bash
# CloudFormation templates
aws cloudformation validate-template --template-body file://<template>.yaml

# Shell scripts
bash -n <script>.sh && shellcheck -S warning <script>.sh

# Relative markdown links resolve (run from the repo root)
python3 - <<'PY'
import os, re, urllib.parse
bad = 0
for root, dirs, fs in os.walk('.'):
    if '/.git' in root: continue
    for f in (x for x in fs if x.endswith('.md')):
        p = os.path.join(root, f)
        for m in re.finditer(r'\[[^\]]*\]\(([^)]+)\)', open(p, encoding='utf-8').read()):
            l = m.group(1)
            if l.startswith(('http://', 'https://', '#', 'mailto:')): continue
            t = urllib.parse.unquote(l.split('#')[0])
            if t and not os.path.exists(os.path.normpath(os.path.join(root, t))):
                print('BROKEN', p, '->', l); bad += 1
print(bad, 'broken links')
PY
```

Docker images: build for the target platform and confirm what you expect is
actually in the image (`docker run --rm --entrypoint sh <img> -c '...'`) rather
than assuming the Dockerfile did it.

## Commits

Do not add `Co-Authored-By` trailers or tool attribution.
