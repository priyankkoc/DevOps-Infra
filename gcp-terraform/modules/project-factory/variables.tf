variable "projects" {
    description = "A list of project configurations to create. Each project is an object containing project_id, display_name, folder_id, billing_account, and apis."
    type = map(object({
        name            = string
        project_id      = string 
        folder_id    = string
        billing_account = string
        auto_create_network = bool
    }))
}
variable "services" {
    description = "A list of services to enable for each project."
    type        = list(string)
}