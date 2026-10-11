module "folders" {
  source = "./modules/folders"
  org_id = var.org_id
  environment = var.environment
}

module "sub_folders" {
   source = "./modules/sub_folders"
   sub_folders = var.sub_folders
}