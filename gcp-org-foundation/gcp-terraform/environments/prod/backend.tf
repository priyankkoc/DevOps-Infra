terraform {
  backend "local" {
    path = "tf-state/prod/terraform.tfstate"
  }
}
