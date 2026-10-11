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