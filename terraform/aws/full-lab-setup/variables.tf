variable "tenant_name" {
  description = "Britive tenant subdomain, without '.britive-app.com'."
  type        = string
}

variable "saml_metadata_document_xml_content" {
  description = "Contents of the SAML metadata XML downloaded from the Britive tenant. Pass with -var=\"saml_metadata_document_xml_content=$(cat metadata.xml)\"."
  type        = string
}

variable "deploy_aws_invalidation_feature" {
  description = "Grant the permissions Britive's AWS session-invalidation feature needs."
  type        = bool
  default     = true
}

variable "allowed_ingress_cidr" {
  description = "CIDR allowed to reach the lab instances (SSH, RDP) and the database (MySQL). Use your own public IP as a /32: curl -s https://checkip.amazonaws.com"
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ingress_cidr, 0)) && var.allowed_ingress_cidr != "0.0.0.0/0"
    error_message = "allowed_ingress_cidr must be a CIDR, and not 0.0.0.0/0; use your public IP as a /32."
  }
}

variable "ssh_public_key" {
  description = "SSH public key for the EC2 key pair. Leave empty to have Terraform generate a key pair; the private key is then available as the sensitive output generated_private_key_pem."
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region for the lab."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR of the lab VPC."
  type        = string
  default     = "10.0.0.0/16"
}
