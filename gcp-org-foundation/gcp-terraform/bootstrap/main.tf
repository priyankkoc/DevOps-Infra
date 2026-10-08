/**
 * BOOTSTRAP STAGE
 * ----------------
 * Run this FIRST, with local state. It creates the one thing every other
 * stage depends on: a GCS bucket for remote state, plus a seed project and
 * a service account that subsequent stages (foundation, per-app infra)
 * authenticate as.
 *
 * Chicken-and-egg note: you cannot point Terraform's own backend at a
 * bucket this same config creates in the same apply. Run this with local
 * state, note the bucket name in the output, then wire that into
 * foundation/backend.tf.
 */

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
  }
}

provider "google" {
  region = var.default_region
}

# ---------------------------------------------------------------------------
# Seed project: hosts Terraform state bucket + the automation service account
# ---------------------------------------------------------------------------
resource "google_project" "seed" {
  name            = "seed-terraform"
  project_id      = "${var.project_id_prefix}-seed"
  org_id          = var.org_id
  billing_account = var.billing_account
  labels = {
    stage = "bootstrap"
  }
}

resource "google_project_service" "seed_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "cloudbilling.googleapis.com",
    "serviceusage.googleapis.com",
  ])
  project = google_project.seed.project_id
  service = each.value
}

# ---------------------------------------------------------------------------
# Remote state bucket
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "terraform_state" {
  name                        = "${var.project_id_prefix}-tfstate"
  project                     = google_project.seed.project_id
  location                    = var.state_bucket_location
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.seed_apis]
}

# ---------------------------------------------------------------------------
# Terraform automation service account
# Grant this SA folder/project-creation rights at the ORG level (done once,
# manually or via a separate org-admin-run apply) — see README.
# ---------------------------------------------------------------------------
resource "google_service_account" "terraform_sa" {
  project      = google_project.seed.project_id
  account_id   = "terraform-automation"
  display_name = "Terraform Automation"
}

resource "google_storage_bucket_iam_member" "state_bucket_access" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_sa.email}"
}
