variable "org_id" {
  description = "GCP Organization ID (numeric)."
  type        = string
}

variable "billing_account" {
  description = "Default billing account ID for projects that don't override it."
  type        = string
}

variable "default_region" {
  type    = string
  default = "asia-south1"
}

# ---------------------------------------------------------------------------
# Data-driven project declarations.
# Add a new project by adding a map entry here — no new HCL needed.
# `folder_key` must match a key in local.folders (see main.tf).
# ---------------------------------------------------------------------------
variable "projects" {
  description = "Map of projects to create across the folder hierarchy."
  type = map(object({
    display_name    = string
    folder_key      = string
    environment     = string
    apis            = list(string)
    billing_account = optional(string)
    labels          = optional(map(string), {})
  }))
}
