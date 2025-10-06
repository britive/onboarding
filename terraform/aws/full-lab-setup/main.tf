terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ===== Data Sources =====

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Get latest Amazon Linux 2 AMI
data "aws_ssm_parameter" "amazon_linux_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

# Get latest Windows Server 2019 AMI
data "aws_ssm_parameter" "windows_ami" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2019-English-Full-Base"
}

# ===== IAM Resources =====

# SAML Provider
resource "aws_iam_saml_provider" "britive" {
  name                   = "britive-${var.tenant_name}"
  saml_metadata_document = var.saml_metadata_document_xml_content
}

# Integration Role
resource "aws_iam_role" "britive_integration" {
  name                 = "britive-${var.tenant_name}-integration-role"
  description          = "Britive Integration Role"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRoleWithSAML",
          "sts:SetSourceIdentity",
          "sts:TagSession"
        ]
        Principal = {
          Federated = aws_iam_saml_provider.britive.arn
        }
        Condition = {
          StringEquals = {
            "SAML:aud" = "https://signin.aws.amazon.com/saml"
          }
        }
      }
    ]
  })
}

# Attach IAM ReadOnly Access policy
resource "aws_iam_role_policy_attachment" "britive_integration_iam_readonly" {
  role       = aws_iam_role.britive_integration.name
  policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
}

# Attach Organizations ReadOnly Access policy
resource "aws_iam_role_policy_attachment" "britive_integration_orgs_readonly" {
  role       = aws_iam_role.britive_integration.name
  policy_arn = "arn:aws:iam::aws:policy/AWSOrganizationsReadOnlyAccess"
}

# AWS Invalidation Feature Policy (conditional)
resource "aws_iam_role_policy" "aws_invalidation" {
  count = var.deploy_aws_invalidation_feature ? 1 : 0

  name = "aws-invalidation"
  role = aws_iam_role.britive_integration.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions"
        ]
        Resource = "arn:aws:iam::*:policy/britive/managed/*"
      }
    ]
  })
}

# ===== KMS and Secrets =====

# KMS Key for RDS password encryption
resource "aws_kms_key" "britive" {
  description             = "KMS key for encrypting RDS password secret"
  enable_key_rotation     = true
  deletion_window_in_days = 10

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "britive" {
  name          = "alias/britive-rds-key"
  target_key_id = aws_kms_key.britive.key_id
}

# RDS Admin Password Secret
resource "random_password" "rds_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "rds_password" {
  name        = "BritiveRdsAdminSecret"
  description = "RDS admin password secret"
  kms_key_id  = aws_kms_key.britive.id
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id = aws_secretsmanager_secret.rds_password.id
  secret_string = jsonencode({
    username = "britive"
    password = random_password.rds_password.result
  })
}

# ===== Networking Resources =====

# VPC
resource "aws_vpc" "britive" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "britive-vpc"
  }
}

# Public Subnets
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.britive.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "britive-subnet-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.britive.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "britive-subnet-2"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "britive" {
  vpc_id = aws_vpc.britive.id

  tags = {
    Name = "britive-igw"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.britive.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.britive.id
  }

  tags = {
    Name = "britive-public-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "britive" {
  name        = "britive-security-group"
  description = "Britive Security Group"
  vpc_id      = aws_vpc.britive.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "RDP"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "britive-sg"
  }
}

# ===== EC2 Resources =====

# EC2 Key Pair
resource "aws_key_pair" "britive" {
  key_name   = "britive-keypair"
  public_key = var.ssh_public_key

  tags = {
    Name = "britive-keypair"
  }
}

# Linux EC2 Instance
resource "aws_instance" "linux" {
  ami                    = data.aws_ssm_parameter.amazon_linux_ami.value
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.britive.key_name
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.britive.id]

  tags = {
    Name = "Britive-Linux"
  }
}

# Windows EC2 Instance
resource "aws_instance" "windows" {
  ami                    = data.aws_ssm_parameter.windows_ami.value
  instance_type          = "t3.small"
  key_name               = aws_key_pair.britive.key_name
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.britive.id]

  tags = {
    Name = "Britive-Windows"
  }
}

# ===== RDS Resources =====

# RDS Subnet Group
resource "aws_db_subnet_group" "britive" {
  name        = "britive-db-subnet-group"
  description = "Subnet group for RDS"
  subnet_ids  = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name = "britive-db-subnet-group"
  }
}

# MySQL RDS Instance
resource "aws_db_instance" "mysql" {
  identifier              = "britive-mysql"
  engine                  = "mysql"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  db_name                 = "britive"
  username                = jsondecode(aws_secretsmanager_secret_version.rds_password.secret_string)["username"]
  password                = jsondecode(aws_secretsmanager_secret_version.rds_password.secret_string)["password"]
  publicly_accessible     = true
  backup_retention_period = 7
  vpc_security_group_ids  = [aws_security_group.britive.id]
  db_subnet_group_name    = aws_db_subnet_group.britive.name
  skip_final_snapshot     = true

  tags = {
    Name = "britive-mysql"
  }
}

# ===== Test Roles for JIT Access =====

# Read-Only Role
resource "aws_iam_role" "readonly" {
  name                 = "Readonly-admin-role"
  description          = "Britive ReadOnly Role for limited access"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_saml_provider.britive.arn
        }
        Action = [
          "sts:AssumeRoleWithSAML"
        ]
        Condition = {
          StringEquals = {
            "SAML:aud" = "https://signin.aws.amazon.com/saml"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "readonly_policy" {
  role       = aws_iam_role.readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Power User Role
resource "aws_iam_role" "poweruser" {
  name                 = "Poweruser-role"
  description          = "Elevated access role for Britive users"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_saml_provider.britive.arn
        }
        Action = [
          "sts:AssumeRoleWithSAML",
          "sts:SetSourceIdentity",
          "sts:TagSession"
        ]
        Condition = {
          StringEquals = {
            "SAML:aud" = "https://signin.aws.amazon.com/saml"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "poweruser_policy" {
  role       = aws_iam_role.poweruser.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# EC2 Full Access Role
resource "aws_iam_role" "ec2_admin" {
  name                 = "EC2-Fullaccess-role"
  description          = "Britive EC2 Full Access Role"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_saml_provider.britive.arn
        }
        Action = [
          "sts:AssumeRoleWithSAML"
        ]
        Condition = {
          StringEquals = {
            "SAML:aud" = "https://signin.aws.amazon.com/saml"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_admin_policy" {
  role       = aws_iam_role.ec2_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

# S3 Full Access Role
resource "aws_iam_role" "s3_admin" {
  name                 = "S3-Fullaccess-role"
  description          = "Elevated access role for Britive users"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_saml_provider.britive.arn
        }
        Action = [
          "sts:AssumeRoleWithSAML",
          "sts:SetSourceIdentity",
          "sts:TagSession"
        ]
        Condition = {
          StringEquals = {
            "SAML:aud" = "https://signin.aws.amazon.com/saml"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_admin_policy" {
  role       = aws_iam_role.s3_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
