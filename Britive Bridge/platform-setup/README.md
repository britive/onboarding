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

- Python 3.8+
- An API token for your Britive tenant with permission to manage the Access
  Broker (pools, resources, response templates, profiles)
- The Britive SDK:

  ```bash
  pip install britive requests
  ```

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

The script is **idempotent on names**: if a pool / resource type already exists
it reuses it rather than creating a duplicate.

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
