# --- how Terraform signs in (an administrator with key-pair auth) ----------

variable "snowflake_organization" {
  description = "Organization name, the first part of the account identifier <org>-<account>. SHOW ORGANIZATION ACCOUNTS or the account URL."
  type        = string
}

variable "snowflake_account" {
  description = "Account name, the second part of the account identifier <org>-<account>."
  type        = string
}

variable "snowflake_admin_user" {
  description = "User Terraform signs in as. Must hold snowflake_admin_role and have an RSA public key registered (key-pair authentication)."
  type        = string
}

variable "snowflake_admin_private_key_file" {
  description = "PEM private key for snowflake_admin_user (PKCS#8, as produced by openssl genrsa | openssl pkcs8). Kept outside the repository."
  type        = string
  default     = "~/.ssh/snowflake_admin.p8"
}

variable "snowflake_admin_private_key_passphrase" {
  description = "Passphrase of the private key, if encrypted."
  type        = string
  default     = null
  sensitive   = true
}

variable "snowflake_admin_role" {
  description = "Role Terraform uses. ACCOUNTADMIN or SECURITYADMIN can do everything here except grant ORGADMIN, which needs ORGADMIN."
  type        = string
  default     = "ACCOUNTADMIN"
}

# --- what is created for Britive -------------------------------------------

variable "britive_role_name" {
  description = "Account role Britive uses; it receives MANAGE GRANTS on the account."
  type        = string
  default     = "BRITIVEROLE"
}

variable "britive_user_name" {
  description = "Service user Britive signs in as, with key-pair authentication only."
  type        = string
  default     = "BRITIVEUSER"
}

variable "britive_public_key_file" {
  description = "PEM public key for the Britive service user. The matching private key is uploaded to the Britive application and never stored here."
  type        = string
}

variable "grant_orgadmin" {
  description = "Grant ORGADMIN to the Britive role. Required for the Snowflake organization application, not for Snowflake Standalone. Terraform must then run as ORGADMIN."
  type        = bool
  default     = false
}
