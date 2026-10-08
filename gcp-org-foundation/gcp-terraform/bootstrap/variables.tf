variable "org_id" {
  description = "GCP Organization ID (numeric)."
  type        = string
}

variable "billing_account" {
  description = "Billing account ID to attach to the seed project (format XXXXXX-XXXXXX-XXXXXX)."
  type        = string
}

variable "project_id_prefix" {
  description = "Short, globally-unique prefix used for all generated project IDs and bucket names (e.g. company/product short name)."
  type        = string
}

variable "default_region" {
  description = "Default region for the provider block."
  type        = string
  default     = "asia-south1"
}

variable "state_bucket_location" {
  description = "Location for the Terraform state bucket (region or multi-region, e.g. ASIA, US, asia-south1)."
  type        = string
  default     = "ASIA"
}
