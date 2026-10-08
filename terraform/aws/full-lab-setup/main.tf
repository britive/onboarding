terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Current Amazon Linux 2023 and Windows Server 2022 images via SSM public parameters.
data "aws_ssm_parameter" "amazon_linux_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_ssm_parameter" "windows_ami" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

# ===== Britive integration + sample JIT roles =====
# The same module the production stacks use; the four sample roles are what
# the lab demonstrates checkouts against.
module "britive" {
  source = "../modules/britive-integration"

  tenant_name                        = var.tenant_name
  saml_metadata_document_xml_content = var.saml_metadata_document_xml_content
  deploy_aws_invalidation_feature    = var.deploy_aws_invalidation_feature
  deploy_sample_roles                = true
}

# ===== KMS and the database secret =====

resource "aws_kms_key" "britive" {
  description             = "Encrypts the lab RDS credentials secret"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "britive" {
  name          = "alias/britive-lab-rds"
  target_key_id = aws_kms_key.britive.key_id
}

resource "random_password" "rds_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# recovery_window_in_days = 0 so a destroy/apply cycle does not fail on a
# secret still scheduled for deletion. name_prefix avoids collisions with a
# previous lab in the same account.
resource "aws_secretsmanager_secret" "rds_password" {
  name_prefix             = "britive-lab/rds-admin-"
  description             = "Lab RDS administrator credentials"
  kms_key_id              = aws_kms_key.britive.id
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id = aws_secretsmanager_secret.rds_password.id
  secret_string = jsonencode({
    username = "britive"
    password = random_password.rds_password.result
  })
}

# ===== Networking =====

resource "aws_vpc" "britive" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "britive-lab-vpc" }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.britive.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "britive-lab-subnet-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.britive.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = { Name = "britive-lab-subnet-2" }
}

resource "aws_internet_gateway" "britive" {
  vpc_id = aws_vpc.britive.id

  tags = { Name = "britive-lab-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.britive.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.britive.id
  }

  tags = { Name = "britive-lab-public-rt" }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Ingress only from allowed_ingress_cidr (your own IP), never the internet.
resource "aws_security_group" "britive" {
  name        = "britive-lab-sg"
  description = "Britive lab: SSH, RDP and MySQL from the allowed CIDR only"
  vpc_id      = aws_vpc.britive.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ingress_cidr]
  }

  ingress {
    description = "RDP"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ingress_cidr]
  }

  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ingress_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "britive-lab-sg" }
}

# ===== EC2 =====

# A key pair is generated unless you supply ssh_public_key.
resource "tls_private_key" "generated" {
  count = var.ssh_public_key == "" ? 1 : 0

  algorithm = "ED25519"
}

resource "aws_key_pair" "britive" {
  key_name   = "britive-lab-${var.tenant_name}"
  public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.generated[0].public_key_openssh

  tags = { Name = "britive-lab-keypair" }
}

resource "aws_instance" "linux" {
  ami                    = data.aws_ssm_parameter.amazon_linux_ami.value
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.britive.key_name
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.britive.id]

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  root_block_device {
    encrypted = true
  }

  tags = { Name = "Britive-Linux" }
}

resource "aws_instance" "windows" {
  ami                    = data.aws_ssm_parameter.windows_ami.value
  instance_type          = "t3.small"
  key_name               = aws_key_pair.britive.key_name
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.britive.id]

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = { Name = "Britive-Windows" }
}

# ===== RDS =====

resource "aws_db_subnet_group" "britive" {
  name        = "britive-lab-db-subnets"
  description = "Lab RDS subnet group"
  subnet_ids  = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = { Name = "britive-lab-db-subnets" }
}

# Publicly addressable so a laptop in allowed_ingress_cidr can connect for the
# database demo; the security group is what limits who can reach it.
resource "aws_db_instance" "mysql" {
  identifier              = "britive-lab-${var.tenant_name}"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp3"
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.britive.arn
  db_name                 = "britive"
  username                = jsondecode(aws_secretsmanager_secret_version.rds_password.secret_string)["username"]
  password                = jsondecode(aws_secretsmanager_secret_version.rds_password.secret_string)["password"]
  publicly_accessible     = true
  backup_retention_period = 1
  vpc_security_group_ids  = [aws_security_group.britive.id]
  db_subnet_group_name    = aws_db_subnet_group.britive.name
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = { Name = "britive-lab-mysql" }
}
