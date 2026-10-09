module "vpc" {
    source = "../../modules/vpc"
    for_each = var.vpcs   
    project_id   = each.value.project_id
    vpc_name     = each.key
    cidr_block   = each.value.cidr_block
    subnets      = each.value.subnets
}