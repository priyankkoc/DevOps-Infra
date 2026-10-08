/**
 * FOUNDATION STAGE — FOLDER HIERARCHY
 * ------------------------------------
 * Fixed, top-level folders directly under the Organization. This mirrors
 * Google's own reference architecture (bootstrap / common / env-tiered) and
 * is deliberately flat — one level is enough for most orgs. If you later
 * need per-team sub-folders inside an environment, add a second
 * `google_folder` resource keyed off `google_folder.top[*].id`.
 */

locals {
  folders = {
    bootstrap       = "fldr-bootstrap"
    non_production  = "fldr-non-production"
    production      = "fldr-production"
  }
  sub_folders = {
    non_production  = ["fldr-non-production-web", "fldr-non-production-backend", "fldr-non-production-data"]
    production      = ["fldr-production-web", "fldr-production-backend", "fldr-production-data"]
  }
  sub_folders_flat =  {
    for item in flatten([for k, v in local.sub_folders : [for name in v : { parent_key = k, display_name = name }]]) : item.display_name => item 
  }
}
resource "google_folder" "top" {
  for_each     = local.folders
  display_name = each.value
  parent       = "organizations/${var.org_id}"
}
resource "google_folder" "sub" {
  for_each     = local.sub_folders_flat
  display_name = each.value.display_name
  parent       = google_folder.top[each.value.parent_key].id
}
