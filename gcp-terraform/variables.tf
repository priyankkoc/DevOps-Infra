variable "environment" {
    description = "The environment name (e.g., dev, staging, prod)."
    type        = string

    validation {
        condition     = contains(["dev", "staging", "prod"], var.environment)
        error_message = "The environment must be one of: dev, staging, prod."
    }
}

variable "org_id" {
    description = "The organization ID where the folders will be created."
    type        = string
}

variable "sub_folders" {    
    description = "A map of sub-folders to create. Each key is the sub-folder name, and the value is an object containing the display name and parent folder key."
    type = set(string)
}
variable "display_name" {
    description = "The display name for the project."
    type        = string
}
variable "project_id" {
    description = "The unique project ID for the GCP project."
    type        = string
}
variable "folder_id" {
    description = "The numeric ID of the parent folder where the project will be created."
    type        = string
}
variable "billing_account" {
    description = "The billing account ID to link the project to."
    type        = string
}
variable "apis" {
    description = "A list of service APIs to enable on the project."
    type        = list(string)
    default     = []
}