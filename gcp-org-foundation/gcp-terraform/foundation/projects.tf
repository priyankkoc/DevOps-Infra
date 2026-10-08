module "projects" {
  source = "../modules/project-factory"

  for_each = var.projects

  project_id      = each.key
  display_name    = each.value.display_name
  folder_id       = google_folder.top[each.value.folder_key].id
  billing_account = coalesce(each.value.billing_account, var.billing_account)
  environment     = each.value.environment
  apis            = each.value.apis
  labels          = each.value.labels
}
