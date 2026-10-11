
resource "google_project" "this" {
  name                = var.display_name
  project_id          = var.project_id
  folder_id           = var.folder_id
  billing_account     = var.billing_account
  auto_create_network = false
}

resource "google_project_service" "apis" {
  for_each                  = toset(var.apis)
  project                   = google_project.this.project_id
  service                   = each.value
  disable_dependent_services = false 
}