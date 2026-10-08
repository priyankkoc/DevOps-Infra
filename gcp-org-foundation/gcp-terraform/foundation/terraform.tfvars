billing_account = "1111-11111-11111"
org_id = "111111111111"
projects = {
  "non-prod" = {
    project_id = "non-prod-web"
    display_name = "Non-Production Web"
    folder_key = "non_production"
    environment = "non-production"
    apis = [
      "compute.googleapis.com",
      "cloudresourcemanager.googleapis.com",
      "iam.googleapis.com",
      "cloudbilling.googleapis.com",
      "serviceusage.googleapis.com",
      "cloudbuild.googleapis.com",
      "container.googleapis.com",
      "cloudfunctions.googleapis.com",
      "cloudscheduler.googleapis.com",
      "pubsub.googleapis.com",
      "cloudtasks.googleapis.com",
      "cloudtrace.googleapis.com"
    ]
  }
}