# Deploy

## [britive-broker ec2 ssh checkout](broker/checkout-ec2-ssh.sh)

### Prerequisites

- Must be an AWS EC2 instance. (Other examples available soon)
- Must have the `aws` CLI and `ec2metadata` CLI installed.
- Must have permission to `secretsmanager:GetSecretValue` on the provided secret.

### Usage

1. Using the `checkout-guac-ssh.sh` checkout script, the resource permission requires the following fields:
   - `BRITIVE_USER_EMAIL` - the Britive user's email, will be used for local username.
   - `expiration` - in seconds
   - `connection_name` - the name of the connection
   - `hostname` - hostname/IP of connection
   - `port` - port to connect on
   - `json_secret_key` - AWS Secrets Manager Secret to retrieve the encryption key from
   - `url` - URL to return for use in a response template
2. Checkout will return a JSON object containing the URL encoded token and the aforementioned `url` value:
   - E.g. `{"token": "...", "url": "..."}"`
3. This can be used in a Response Template to provide the URL for users
   - E.g. `https://{{url}}?data={{token}}`

## [britive-broker generic checkout](broker/checkout-generic.sh)

### Usage

1. Using the `checkout-generic.sh` checkout script, the resource permission requires 4 fields:
   - `username` - the username for guacamole`
   - `expiration` - in seconds
   - `connection_name` - the name of the connection
   - `connection` - the JSON child object, containing `protocol` and `parameters` of the connection
2. Checkout will return a JSON object containing the URL encoded token:
   - E.g. `{"token": "..."}"`
3. This can be used in a Response Template to provide the URL for users
   - E.g. `https://guacamole.example.com/guacamole?data={{token}}`

## [Cloudformation](cloudformation/stackamole.yaml)

### Parameters

| parameter | description |
| --------: | :---------- |
| JsonSecretKey | Must be a 32-character hexadecimal string (0-9, a-f). |
| VpcId | Specify the ID of the VPC to use. |
| VpcSecurityGroupId | Specify the ID of the VPC Security Group to use for NFS access to EFS. |
| FirstSubnetId | Specify the ID of the first VPC Subnet to use. |
| SecondSubnetId | Specify the ID of the second VPC Subnet to use. |
| AllowEcsCidr | Specify the CIDR that will be allowed to access the exposed ports from the ECS tasks. |
| CreateVpcEndpoints | Specify whether the required VPC endpoints should be created - [true|false]. |
| RouteTableId | If creating VPC endpoints, specify the route table ID for the S3 gateway endpoint. |
| LoadBalancerArn | Specify the ARN of the ALB to add the HTTPS listener to. |
| ListenerPort | Specify the port number for the HTTPS listener. |
| SslPolicy | Specify the SSL Policy of the HTTPS listener. |
| CertificateArn | Specify the Certificate ARN for the HTTPS listener. |
| AllowedGuacamoleCidr | Specify the CIDR for allowed ingress traffic on the new listener port. |
| ImageLocationGuacd | ECR image URI, or docker hub image (e.g. guacamole/guacd) if comfortable pulling from there, but that will require a NAT gateway. |
| ImageLocationGuacamole | ECR image URI, or docker hub image (e.g. guacamole/guacamole) if comfortable pulling from there, but that will require a NAT gateway. |
| ImageLocationGuacSync | OPTIONAL - ECR image URI for the image used to convert and sync recordings to S3. |
| S3BucketArnGuacSync | OPTIONAL - S3 bucket ARN where converted recordings will be placed. |

### _optional_ [guacsync](cloudformation/guacsync)

1. build the docker image, e.g. `docker build -f guacsync/Dockerfile`
2. push to ECR repo, instructions: [Pushing a Docker image to an Amazon ECR private repository](https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html)
3. use ECR image URI in the `ImageLocationGuacSync` parameter
4. create a S3 bucket or use an existing one, enter the ARN in the `S3BucketArnGuacSync` parameter

## [docker compose](docker/docker-compose.yaml)

1. Replace the `<json secret key goes here>` in the `docker-compose.yaml` file with your JSON secret key.
   - [configuring-guacamole-to-accept-encrypted-json](https://guacamole.apache.org/doc/gug/json-auth.html#configuring-guacamole-to-accept-encrypted-json)

### Usage

```sh
docker compose up -d
```
