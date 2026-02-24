# Session Recording

These examples cover session recording features for SSH and RDP sessions curated by Britive Access Broker.

## Background

This example uses Britive Access Broker and Apache Guacamole to achieve proxied user sessions into servers and allows for video recording of the user session. These sessions are curated by Britive, are short-lived, and do not require end users to install any special tools or to copy credentials — the credential rotation is handled entirely by Britive Access Broker.

Traditional remote access tools often run as a local client application, however, the Guacamole client requires nothing more than a modern web browser when accessing one of the served protocols, such as RDP/SSH/VNC.

By separating the frontend (web application) from the backend (`guacd`), Guacamole enables secure, clientless remote access through a browser without any additional plugins.

### How RDP/SSH Connections Work

1. **User connects via browser** to the Guacamole web interface.
2. **Guacamole web server** sends connection parameters (hostname, port, credentials) to `guacd`.
3. **`guacd` opens the remote connection** (RDP/SSH) directly to the target machine.
4. **`guacd` encodes the session** into an optimized WebSocket stream for the browser.
5. **Browser renders the session** using JavaScript — no plugins required.

The RDP/SSH connection is made by `guacd`, not the browser. `guacd` must have network access to the target host.

---

## Deployment Options

Three deployment methods are provided. All share the same Guacamole-based architecture and broker scripts.

| Method          | Directory                                    | Best For                                          |
|-----------------|----------------------------------------------|---------------------------------------------------|
| Docker Compose  | [docker/](docker/)                           | Local development, single-host setups             |
| CloudFormation  | [cloudformation/](cloudformation/)           | AWS production via declarative IaC                |
| ECS Fargate     | [ecs-fargate/](ecs-fargate/)                 | AWS production via automated deployment script    |

---

## [docker/](docker/) — Docker Compose

Runs the full stack locally using Docker Compose. Suitable for development and single-server deployments.

### Services

| Service   | Image / Source        | Purpose                                    |
|-----------|-----------------------|--------------------------------------------|
| broker    | Custom (Dockerfile)   | Britive Access Broker + SSH server         |
| guacd     | `guacamole/guacd`     | Native protocol daemon (libguac)           |
| guacamole | `guacamole/guacamole` | Browser-based web UI                       |
| guacenc   | Custom                | Recording conversion (`.guac` → `.m4v`)    |

### Docker Quick Start

1. Generate a JSON secret key:

   ```sh
   echo -n "your-passphrase" | md5    # macOS
   echo -n "your-passphrase" | md5sum # Linux
   ```

2. Update `docker/docker-compose.yaml` with the generated key:

   ```yaml
   guacamole:
     environment:
       JSON_SECRET_KEY: "<your-key>"
   ```

3. Update `docker/broker/broker-config.yml` with your Britive tenant subdomain and broker token.

4. Build and start:

   ```sh
   cd docker/
   mkdir -m a+rw recordings
   docker build -t broker-docker .
   docker compose up -d
   ```

See [docker/README.md](docker/README.md) for full setup instructions.

---

## [cloudformation/](cloudformation/) — AWS CloudFormation

Deploys the stack to AWS ECS using a CloudFormation template. Requires manual parameter setup but is fully declarative.

### Template: [cloudformation/stackamole.yaml](cloudformation/stackamole.yaml)

Key parameters:

| Parameter                | Description                                                         |
|--------------------------|---------------------------------------------------------------------|
| `JsonSecretKey`          | 32-character hex string for Guacamole JSON auth                     |
| `VpcId`                  | VPC to deploy into                                                  |
| `FirstSubnetId`          | First subnet ID                                                     |
| `SecondSubnetId`         | Second subnet ID                                                    |
| `LoadBalancerArn`        | Existing ALB to attach the Guacamole listener to                    |
| `CertificateArn`         | ACM certificate for the HTTPS listener                              |
| `ImageLocationGuacd`     | ECR or Docker Hub image URI for guacd                               |
| `ImageLocationGuacamole` | ECR or Docker Hub image URI for guacamole                           |
| `ImageLocationGuacSync`  | *(Optional)* ECR image for recording conversion + S3 sync           |
| `S3BucketArnGuacSync`    | *(Optional)* S3 bucket ARN where converted recordings are stored    |

See [cloudformation/DEPLOY.md](cloudformation/DEPLOY.md) for the full parameter reference and deployment walkthrough.

### Optional: GuacSync

To automatically convert `.guac` session recordings to `.m4v` and sync to S3:

1. Build the GuacSync image from `cloudformation/guacsync/Dockerfile`
2. Push to ECR
3. Set `ImageLocationGuacSync` and `S3BucketArnGuacSync` in the CloudFormation parameters

---

## [ecs-fargate/](ecs-fargate/) — AWS ECS Fargate (Automated)

Deploys the full stack to AWS ECS Fargate using a single `deploy.sh` script. All AWS infrastructure is created automatically — ECR, EFS, ALB, Secrets Manager, Cloud Map service discovery, IAM roles, and ECS services.

### Services

| Service   | Image / Source                  | Purpose                                    |
|-----------|---------------------------------|--------------------------------------------|
| broker    | Custom ECR image                | Britive Access Broker + SSH server         |
| guacd     | `guacamole/guacd:1.5.5`         | Native protocol daemon                     |
| guacamole | `guacamole/guacamole:1.5.5`     | Browser-based web UI (behind ALB)          |
| guacsync  | Custom ECR image *(optional)*   | Recording conversion + S3 sync             |

Services communicate via AWS Cloud Map private DNS (`guacd.britive.local`, `broker.britive.local`). Session recordings are stored on a shared EFS filesystem mounted at `/recordings`.

### ECS Fargate Quick Start

1. Copy and fill in `ecs-fargate/secrets.json`:

   ```sh
   cp ecs-fargate/secrets.json.example ecs-fargate/secrets.json
   ```

   Set `BRITIVE_TENANT` and `BRITIVE_TOKEN`. Leave `JSON_SECRET_KEY` empty to auto-generate.

2. Place the broker JAR in `ecs-fargate/broker/`:

   ```sh
   cp /path/to/britive-broker-2.0.0.jar ecs-fargate/broker/
   ```

3. Deploy:

   ```sh
   cd ecs-fargate/
   chmod +x deploy.sh manage-secrets.sh
   ./deploy.sh
   ```

### Key Options

| CLI Flag                  | Description                                            | Default                     |
|---------------------------|--------------------------------------------------------|-----------------------------|
| `--broker-version <ver>`  | Broker JAR version to build and deploy                 | `2.0.0`                     |
| `--region <region>`       | AWS region                                             | `us-east-1`                 |
| `--cluster-name <name>`   | ECS cluster name                                       | `britive-session-recording` |
| `--acm-cert-arn <arn>`    | Enable HTTPS on ALB (adds HTTP→HTTPS redirect)         | *(HTTP/80 only)*            |
| `--enable-guacsync`       | Deploy the GuacSync recording conversion service       | `false`                     |
| `--s3-bucket <bucket>`    | S3 bucket for GuacSync output *(required with above)*  |                             |
| `--vpc-id <id>`           | Override auto-detected default VPC                     | *(auto-detect)*             |
| `--subnets <ids>`         | Comma-separated subnet IDs                             | *(auto-detect)*             |
| `--use-secrets-json`      | Force-load configuration from `secrets.json`           |                             |

### Secrets Management

```sh
./manage-secrets.sh list                          # list all secrets
./manage-secrets.sh get BRITIVE_TOKEN             # retrieve a value
./manage-secrets.sh set MY_SECRET "value"         # add or update a secret
./manage-secrets.sh sync                          # push secrets.json to Secrets Manager
./manage-secrets.sh restart-tasks                 # restart ECS tasks to pick up new values
./manage-secrets.sh update-iam                    # refresh IAM permissions after adding secrets
```

See [ecs-fargate/README.md](ecs-fargate/README.md) for the full documentation.

---

## [broker-scripts/](broker-scripts/) — Checkout Scripts

Scripts called by the Britive broker during permission checkout and check-in. They generate signed, encrypted Guacamole tokens that authenticate users into sessions.

| Script                          | Description                                                              |
|---------------------------------|--------------------------------------------------------------------------|
| `checkout-generic.sh`           | Generic token generator — accepts a full connection JSON object          |
| `rdp/checkout-rdp.sh`           | RDP checkout — builds connection from hostname/domain params             |
| `rdp/checkout-rdp.ps1`          | RDP checkout (PowerShell) — creates a temporary local admin user         |
| `rdp/checkin-rdp.ps1`           | RDP check-in — removes the temporary user after the session ends         |
| `rdp/checkout-ec2-rdp.sh`       | RDP checkout for EC2 — retrieves the secret key from Secrets Manager     |
| `ssh/checkout-ssh.sh`           | SSH checkout — creates SSH user, key pair, and Guacamole token           |
| `ssh/remote-checkout-ssh.sh`    | SSH checkout — sets up a user on a remote host via SSH                   |
| `ssh/checkout-ec2-ssh.sh`       | SSH checkout for EC2 — retrieves the encryption key from Secrets Manager |

---

## Shared Utilities

### [encrypt-token.sh](encrypt-token.sh)

Signs and encrypts a JSON authentication object for Guacamole using HMAC-SHA256 signing and AES-128-CBC encryption. The output is a URL-encoded token passed to Guacamole via `?data=`.

```sh
./encrypt-token.sh <json-secret-key> <json-file>
```

**Example:**

```sh
# Generate a JSON secret key
echo -n "britiveallthethings" | md5   # → fb57d11d533339aea1e37c2a5a1cb92c

# Encrypt a token
./encrypt-token.sh fb57d11d533339aea1e37c2a5a1cb92c example_user.json

# Use the token in a URL
# https://guacamole.example.com/guacamole?data=<token>
```

### [example_user.json](example_user.json)

Sample JSON object showing the structure expected by the Guacamole JSON auth extension:

```json
{
  "username": "first.last@britive.com",
  "expires": "1750000000000",
  "connections": {
    "my-ssh-session": {
      "protocol": "ssh",
      "parameters": {
        "hostname": "1.2.3.4",
        "port": "22",
        "username": "ubuntu",
        "private-key": "...",
        "recording-path": "/recordings",
        "recording-name": "${GUAC_DATE}-${GUAC_TIME}-${GUAC_USERNAME}-my-ssh-session"
      }
    }
  }
}
```

> Full connection parameter reference: [configuring-connections](https://guacamole.apache.org/doc/gug/configuring-guacamole.html#configuring-connections)

---

## Broker Version

All deployment methods support a configurable broker version. The default is **2.0.0**.

| Method          | How to set the version                                                                                                    |
|-----------------|---------------------------------------------------------------------------------------------------------------------------|
| Docker Compose  | Replace the JAR filename in `docker/broker/Dockerfile` and place the matching JAR in `docker/broker/`                     |
| CloudFormation  | Update the ECR image tag in the `ImageLocation*` parameters                                                               |
| ECS Fargate     | `./deploy.sh --broker-version 2.0.0` or set `BROKER_VERSION` at the top of `deploy.sh`                                    |

Place the matching `britive-broker-<version>.jar` file in the `broker/` directory of your chosen deployment method before building.
