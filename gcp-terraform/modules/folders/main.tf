resource "google_folder" "top-level" {
  display_name = "${var.environment}-folders"
  parent       = "organizations/${var.org_id}"
}
