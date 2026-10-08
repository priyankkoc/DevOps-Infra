/**
 * PROJECT FACTORY MODULE
 * -----------------------
 * Creates one GCP project under a given folder, enables the requested APIs,
 * links billing, and applies standard labels + optional IAM bindings.
 * Called once per entry in the root `projects` map via for_each.
 */

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
  }
}

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
