resource "google_project" "project" {
  for_each           = var.projects
  name               = each.value.name
  project_id         = each.value.project_id
  folder_id          = each.value.folder_id
  billing_account    = each.value.billing_account
  auto_create_network = each.value.auto_create_network
}

resource "google_project_service" "project_services" {
  for_each = {
    for item in flatten([
      for project_key, project in var.projects : [
        for service in var.services : {
          key = "${project_key}/${service}"
          project_key = project_key
          service = service 
        }]]) : item.key => item
  } 
   project  = google_project.project[each.value.project_key].project_id
   service  = each.value.service
 }