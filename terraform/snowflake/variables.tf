variable "snowflake_organization" {
  description = "The Snowflake account identifier"
  type        = string
}

variable "snowflake_account" {
  description = "The Snowflake account identifier"
  type        = string
}

variable "snowflake_user" {
  description = "The Snowflake user for authentication"
  type        = string
}

variable "snowflake_password" {
  description = "The password for the Snowflake user"
  type        = string
  sensitive   = true
}

variable "snowflake_admin_role" {
  description = "The Snowflake role with admin privileges"
  type        = string
  default     = "ACCOUNTADMIN"
}

variable "britive_role_name" {
  description = "The name of the custom Britive role"
  type        = string
  default     = "BRITIVEROLE"
}

variable "britive_role_privileges" {
  description = "List of privileges assigned to the Britive role"
  type        = list(string)
  default     = ["MANAGE GRANTS"]
}

variable "orgadmin_role" {
  description = "The ORGADMIN role in Snowflake"
  type        = string
  default     = "ORGADMIN"
}

variable "britive_user_name" {
  description = "The name of the Britive user account"
  type        = string
  default     = "BRITIVEUSER"
}

variable "britive_public_key_path" {
  description = "Path to the Britive user's public key file"
  type        = string
  default     = "${path.module}/britive_public_key.pem"
}
