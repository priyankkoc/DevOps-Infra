resource "google_folder" "sub" {
  for_each     = var.sub_folders
  display_name = each.value
  parent       = "prod"
}