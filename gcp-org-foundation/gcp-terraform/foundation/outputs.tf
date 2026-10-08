output "folder_ids" {
  value = { for k, f in google_folder.top : k => f.id }
}

output "project_ids" {
  value = { for k, p in module.projects : k => p.project_id }
}
