# Fill in the bucket name from `terraform output state_bucket_name` in bootstrap/.
# Terraform does not allow variables in a backend block, so this is literal.
# terraform {
#   backend "gcs" {
#     bucket = "REPLACE_WITH_STATE_BUCKET_NAME"
#     prefix = "foundation"
#   }
# }
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}