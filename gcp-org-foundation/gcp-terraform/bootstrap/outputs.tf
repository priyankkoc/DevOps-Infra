output "state_bucket_name" {
  description = "Feed this into foundation/backend.tf as the GCS backend bucket."
  value       = google_storage_bucket.terraform_state.name
}

output "seed_project_id" {
  value = google_project.seed.project_id
}

output "terraform_sa_email" {
  description = "Service account subsequent stages should impersonate/authenticate as."
  value       = google_service_account.terraform_sa.email
}
