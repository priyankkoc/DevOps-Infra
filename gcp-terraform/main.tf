module "folders" {
  source = "./modules/folders"
  org_id = var.org_id
  environment = var.environment
}

module "sub_folders" {
   source = "./modules/sub_folders"
   sub_folders = var.sub_folders
}

module "project-factory" {
  source = "./modules/project-factory"
  environment = var.environment
  display_name = var.display_name
  project_id = var.project_id
  folder_id = var.folder_id
  billing_account = var.billing_account
  apis = var.apis
}