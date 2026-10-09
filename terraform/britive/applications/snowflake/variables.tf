variable "standalone" {
  description = "false: the Snowflake (organization) application, one set of connection properties for every account Britive scans. true: the Snowflake Standalone application with one environment per account from `accounts`."
  type        = bool
  default     = false
}

variable "application_name" {
  description = "Display name of the application in Britive."
  type        = string
  default     = "Snowflake"
}

variable "description" {
  description = "Description shown on the application."
  type        = string
  default     = "Snowflake, integration managed with Terraform"
}

variable "account_mapping_attribute" {
  description = "Britive user attribute matched against the Snowflake user: Email (the guide's choice) or Username."
  type        = string
  default     = "Email"
}

variable "max_session_duration_for_profiles" {
  description = "Longest expiration a profile on this application may have, in seconds (15 minutes to 7 days)."
  type        = number
  default     = 43200

  validation {
    condition     = var.max_session_duration_for_profiles >= 900 && var.max_session_duration_for_profiles <= 604800
    error_message = "max_session_duration_for_profiles must be between 900 and 604800 seconds."
  }
}

# ---- connection: organization application (standalone = false) ----------
variable "account_identifier" {
  description = "Organization application only. Snowflake account identifier, as `terraform output account_identifier` in ../../../snowflake prints it (<org>-<account>)."
  type        = string
  default     = null
}

# ---- connection: standalone application (standalone = true) -------------
variable "accounts" {
  description = "Standalone application only. One environment per Snowflake account, keyed by a short name: the account identifier and an optional description."
  type = map(object({
    account_identifier = string
    description        = optional(string, "")
  }))
  default = {}
}

# ---- shared connection properties -----------------------------------------
variable "username" {
  description = "Service user created for Britive (`terraform output username` in ../../../snowflake). Uppercase; the field is case sensitive."
  type        = string
  default     = "BRITIVEUSER"
}

variable "role" {
  description = "Role granted to that user (`terraform output role`). Uppercase."
  type        = string
  default     = "BRITIVEROLE"
}

variable "login_url" {
  description = "Login URL users open at checkout; `{accountId}` is replaced by the account identifier. The console default is https://{accountId}.snowflakecomputing.com."
  type        = string
  default     = "https://{accountId}.snowflakecomputing.com"
}

variable "private_key_file" {
  description = "Path to the Britive service user's PKCS#8 private key (~/.ssh/britive_snowflake.p8 in ../../../snowflake). Read at plan time; never commit it."
  type        = string
}

variable "public_key_file" {
  description = "Path to the matching public key (~/.ssh/britive_snowflake.pub)."
  type        = string
}

variable "private_key_passphrase" {
  description = "Passphrase of the private key, or empty when it has none."
  type        = string
  default     = ""
  sensitive   = true
}

variable "use_login_name_for_account_mapping" {
  description = "Map Britive users to Snowflake's login name instead of the name field during scans."
  type        = bool
  default     = false
}

variable "skip_schema_level_privileges" {
  description = "Do not collect schema-level privileges during scans (faster on large accounts)."
  type        = bool
  default     = false
}

variable "copy_settings_to_all_accounts" {
  description = "Organization application only: use the same user, role and keys for every account the organization scan finds."
  type        = bool
  default     = true
}
