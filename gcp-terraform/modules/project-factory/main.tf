
resource "google_project" "this" {
  name                = var.display_name
  project_id          = var.project_id
  folder_id           = var.folder_id
  billing_account     = var.billing_account
  auto_create_network = false

  labels = merge(
    {
      environment = var.environment
      managed_by  = "terraform"
    },
    var.labels
  )
}

resource "google_project_service" "apis" {
  for_each                  = toset(var.apis)
  project                   = google_project.this.project_id
  service                   = each.value
  disable_dependent_services = false
}

resource "google_project_iam_member" "bindings" {
  for_each = var.iam_bindings
  project  = google_project.this.project_id
  role     = each.value.role
  member   = each.value.member
}

# Optional: default VPC is disabled above (auto_create_network = false);
# create a minimal network here if every project should get one uniformly.
