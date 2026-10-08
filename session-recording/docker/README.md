# Session Recording (legacy) - Docker Compose

> Legacy. New deployments use [Britive Bridge](../../Britive%20Bridge/v2/README.md).
> See [../README.md](../README.md).

Runs Britive Access Broker next to Apache Guacamole so that SSH and RDP sessions
brokered by Britive are proxied through a browser and recorded.

## Architecture

```text
Browser -> Guacamole (:8080) -> guacd (:4822) -> Target host (SSH/RDP)
                |                   |
            PostgreSQL          ./recordings  (.guac files)
     (connection history,
      in-browser playback)
```

| Service     | Image                       | Purpose                                                                 |
|-------------|-----------------------------|-------------------------------------------------------------------------|
| `broker`    | Custom (`broker/Dockerfile`) | Britive Access Broker; runs the checkout scripts and a key-only sshd    |
| `guacd`     | `guacamole/guacd:1.5.5`     | Protocol daemon; opens the RDP/SSH connection and writes the recording  |
| `guacamole` | `guacamole/guacamole:1.5.5` | Web UI on port 8080; validates the signed token from the broker         |
| `postgres`  | `postgres:16`               | Connection history, which is what in-browser playback is attached to    |

Only Guacamole (8080) is published on the host. guacd, PostgreSQL and the
broker's sshd are reachable from the compose network only.

## Prerequisites

- Docker Engine and Docker Compose v2 (`docker compose`)
- A Britive broker token (Britive console: System Administration, Broker Pools)
- The broker JAR, `britive-broker-<version>.jar`, placed in `broker/`
  (JARs are gitignored)

## Setup

All commands run from this `docker/` directory.

### 1. Configure the broker

Edit `broker/broker-config.yml` with your tenant subdomain and broker token:

```yaml
config:
  version: 2
  bootstrap:
    tenant_subdomain: your-tenant   # for your-tenant.britive-app.com
    authentication_token: TOKEN HERE!
```

### 2. Create `.env`

```sh
cp .env.example .env
```

Fill in:

- `JSON_SECRET_KEY`: the Guacamole JSON auth key, a 128-bit AES key as 32 hex
  characters. Generate it with `openssl rand -hex 16`.
- `POSTGRES_PASSWORD`: any strong password for the `guacamole` database user.

`.env` is gitignored and `docker-compose.yaml` refuses to start without both.
The same `JSON_SECRET_KEY` value must be given to every checkout script
(`SECRET`, `SECRET_KEY` or `json_secret_key` variable in the Britive
permission, and `SECRET_KEY` in the Guac example in `broker/setup.yml.example`).
If the values differ, Guacamole rejects every token and users see an auth
error or a blank page.

### 3. Generate the database schema

PostgreSQL loads this file once, when its data volume is first created:

```sh
docker run --rm guacamole/guacamole:1.5.5 /opt/guacamole/bin/initdb.sh --postgresql > initdb.sql
```

`initdb.sql` is gitignored. If you change `POSTGRES_PASSWORD` or the schema
later, remove the volume (`docker compose down -v`) so it initializes again.

### 4. Build the broker image

```sh
docker build --build-arg BROKER_VERSION=2.0.1 -t broker-docker broker/
```

`BROKER_VERSION` must match the JAR filename in `broker/`. The start script
runs whatever `britive-broker-*.jar` is in the image, so nothing else refers
to the version.

### 5. Generate the broker SSH key pair

The `remote-*-ssh.sh` checkout scripts authenticate to target Linux hosts with
a key at `/root/.ssh/id_rsa` inside the broker container. Generate your own
pair; no key is shipped in this repository:

```sh
mkdir -p broker-ssh
ssh-keygen -t rsa -b 4096 -f broker-ssh/id_rsa -N "" -C "britive-broker"
chmod 700 broker-ssh
chmod 600 broker-ssh/id_rsa
chmod 644 broker-ssh/id_rsa.pub
```

`broker-ssh/` is bind-mounted to `/root/.ssh` and gitignored. Keep it
writable: on first contact with a target the scripts accept its host key and
pin it in `broker-ssh/known_hosts`; later connections fail if that key
changes. Add `broker-ssh/id_rsa.pub` to the `britivebroker` account's
`authorized_keys` on each target host (see
[../broker-scripts/README.md](../broker-scripts/README.md)).

### 6. Start

```sh
mkdir -m a+rw recordings
docker compose up -d
docker compose logs -f
```

### 7. Change the Guacamole admin password

The schema creates a database user `guacadmin` with password `guacadmin`.
Sign in at `http://<host>:8080/guacamole`, open Settings, Preferences, and
change it before exposing the port anywhere. This account is what you use to
review connection history and play recordings; end users never sign in, they
arrive with a token.

## Using it

A checkout returns `{"token": "...", "url": "..."}`; the Britive response
template turns that into `<url>?data=<token>`, which opens the recorded
session in the browser.

The Guac example in `broker/setup.yml.example` has the Guacamole URL hardcoded
as `http://localhost:8080/guacamole`. Set it to the address users reach
Guacamole on.

## Recordings

`guacd` writes one `.guac` file per session under `./recordings`
(`/home/guacd/recordings` in the container, `/home/guacamole/recordings` in
Guacamole). The `remote-*` scripts set `recording-path` to
`<recording_path>/${HISTORY_UUID}`, the layout the Guacamole history
recording storage uses, so a recording can be played from the connection's
history in the web UI (sign in as the admin user, Settings, History). The
`${HISTORY_UUID}` token is supplied by the database backend, which is why
PostgreSQL is part of this stack.

### Converting a recording to video

There is no converter in the stack. `guacenc`, which turns a `.guac` file into
`.m4v`, is part of guacamole-server but is not in the `guacamole/guacd` image.
To convert on a workstation, build it from the
[guacamole-server 1.5.5 source](https://guacamole.apache.org/releases/1.5.5/)
with the ffmpeg development libraries installed (`./configure --disable-guacd`,
`make`, `make install`), then:

```sh
guacenc -s 1920x1080 -r 20000000 -f ./recordings/<history-uuid>/<recording-name>
# writes <recording-name>.m4v next to the input
```

## Stopping and cleanup

```sh
docker compose down        # keeps the database volume and ./recordings
docker compose down -v     # also drops the database (recordings stay on disk)
```

## Troubleshooting

**`docker compose up` fails with "set JSON_SECRET_KEY in .env"** - step 2.

**Broker container exits immediately** - `docker compose logs broker`. Check
`broker/broker-config.yml`, and that exactly one `britive-broker-*.jar` was
copied into the image (the start script refuses to guess between two).

**Guacamole shows a blank page or connection error** - `docker compose ps`
and `docker compose logs guacd`. `GUACD_HOSTNAME` in `docker-compose.yaml`
must match the `guacd` service name.

**Guacamole rejects tokens after a checkout** - `JSON_SECRET_KEY` in `.env`
and the key the script used are not the same 32 hex characters.

**Guacamole cannot reach the database** - the schema was not loaded (step 3
ran after the volume already existed). `docker compose down -v`, confirm
`initdb.sql` is non-empty, `docker compose up -d`.

**SSH checkout fails with a host key error** - the target's host key changed
since it was pinned. Remove its line from `broker-ssh/known_hosts` once you
have confirmed why.
