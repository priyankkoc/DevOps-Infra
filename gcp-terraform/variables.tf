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

variable "projects" {
    description = "A list of project configurations to create. Each project is an object containing project_id, display_name, folder_id, billing_account, and apis."
    type = map(object({
        name     = string
        project_id = string
        folder_id    = string
        billing_account = string
        auto_create_network = bool
    }))
}
variable "services" {
    description = "A list of services to enable for each project."
    type        = list(string)
}