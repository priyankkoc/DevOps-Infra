variable "project_id" {
  description = "Globally unique project ID."
  type        = string
}

variable "display_name" {
  description = "Human-readable project name."
  type        = string
}

variable "folder_id" {
  description = "Numeric ID of the parent folder this project lives under."
  type        = string
}

variable "billing_account" {
  description = "Billing account ID to link."
  type        = string
}

variable "environment" {
  description = "dev | staging | prod | common | bootstrap — used as a label and for downstream policy."
  type        = string
}

variable "apis" {
  description = "List of service APIs to enable on this project."
  type        = list(string)
  default     = []
}
