# Britive Bridge — Platform Setup

Run this **before** deploying Bridge with any of the deployment options. It
creates the Britive platform objects Bridge needs and prints the environment
variables the container expects.

## What it creates

`quick-setup.py` is an interactive script (Britive Python SDK) that creates:

- A **Broker Pool** with an active **token** (used as `BRITIVE_BROKER_AUTH_TOKEN`)
- A **Bridge Resource** associated with that pool
- A **Response Template** for clickable session URLs
- An **admin Profile** with the required script parameters (checkout/checkin)

At the end it prints the two env vars every deployment needs:

```
BRITIVE_BROKER_TENANT_SUBDOMAIN=<tenant>
BRITIVE_BROKER_AUTH_TOKEN=<token>
```

## Prerequisites

- Python 3.10+ (required by the `britive` SDK)
- An API token for your Britive tenant with permission to manage the Access
  Broker (pools, resources, response templates, profiles)
- The Britive SDK + `requests`:

  ```bash
  pip install -r requirements.txt
  # or: pip install britive requests
  ```

  > VS Code showing "could not be resolved" on `import requests` / `import
  > britive`? That's the editor pointing at an interpreter without these
  > installed — run *Python: Select Interpreter* and pick the env where you ran
  > the install above. It is not a code error.

## Usage

```bash
python3 quick-setup.py
```

You'll be prompted for:

1. **Tenant name** — the subdomain of your Britive URL (e.g. `acme` for
   `https://acme.britive-app.com`). Can also be supplied via `BRITIVE_TENANT`.
2. **API token** — entered hidden. Can also be supplied via `BRITIVE_API_TOKEN`.
3. **Bridge external URL** — the URL users will hit (e.g.
   `https://bridge.example.com`). This is the load balancer / ingress address
   from your chosen deployment option, so you may want to deploy infra first,
   grab the DNS name, then re-run or update the resource.
4. **Resource name** — defaults to `Admin`.

The script is **idempotent on names**: if a pool, resource type, response
template, permission, resource, or profile with the expected name already
exists, it is reused rather than duplicated. Re-running after infrastructure
deploy also **updates the existing resource's URL** to the one you enter — the
intended flow for replacing a placeholder URL with the real DNS name. Two
caveats: an existing pool's token is never reprinted (get it from the Britive
UI), and an existing permission's scripts/variables are left untouched.

## After it finishes

1. Save the printed `BRITIVE_BROKER_TENANT_SUBDOMAIN` and
   `BRITIVE_BROKER_AUTH_TOKEN` — you'll plug them into your deployment.
2. Assign users or groups to the **admin profile** via Britive policies so they
   can check out Bridge access.
3. Deploy Bridge using one of the options in the parent directory.

## Notes

- The broker token is shown **once** at creation time. If you lose it, generate
  a new one from the Britive UI (the script won't reprint an existing pool's
  token).
- Treat the token like a credential — do not commit it.
