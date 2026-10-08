# Session Recording (legacy)

> **Legacy.** This Guacamole-based stack is superseded by
> [Britive Bridge](../Britive%20Bridge/v2/README.md) for all new deployments.
> Bridge records sessions itself, with no Guacamole, broker SSH server or token
> scripts to operate, and nothing here is being developed further.
>
> It is kept because
> [docs.britive.com](https://docs.britive.com/v1/docs/session-recording) still
> documents this docker variant for existing deployments.

## What remains

| Path                                         | What                                                                                                      |
|----------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| [docker/](docker/README.md)                  | Docker Compose stack: Britive broker, `guacd`, Guacamole web app, PostgreSQL                              |
| [broker-scripts/](broker-scripts/README.md)  | Checkout and check-in scripts the broker runs: create the temporary account, return the signed token      |
| [encrypt-token.sh](encrypt-token.sh)         | Standalone token signer for testing a key by hand, fed with [example_user.json](example_user.json)         |

The CloudFormation and ECS Fargate variants were removed. Deploy Britive Bridge
instead.

## Script naming

- `remote-*` runs on the broker and reaches the target over SSH (Linux) or WinRM (Windows); each checkout has a matching check-in.
- `checkout-rdp.ps1` / `checkin-rdp.ps1` are PowerShell and run on the Windows target itself.
- `*-ec2-*` reads the Guacamole secret from AWS Secrets Manager with the EC2 instance role instead of taking it as a variable.
- `checkout-rdp.sh` is token only, for an existing domain or local account: nothing is created and there is no check-in.

## Guacamole secret

Every token is signed and encrypted with one 128-bit AES key, written as 32 hex
characters:

```sh
openssl rand -hex 16
```

Put it in `docker/.env` as `JSON_SECRET_KEY` and give the same value to the
scripts (`SECRET`, `SECRET_KEY` or `json_secret_key`, see the
[variable reference](broker-scripts/README.md#variable-reference)). To check a
key and a connection JSON by hand:

```sh
./encrypt-token.sh <32-hex-key> example_user.json
# open <guacamole-url>/guacamole?data=<token>
```
