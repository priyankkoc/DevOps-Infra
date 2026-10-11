variable "project_id" {
    description = "The project ID where the VPCs will be created."
    type        = string
}
variable "vpc_name" {
    description = "The name of the VPC to create."
    type        = string
}
variable "cidr_block" {
    description = "The CIDR block for the VPC."
    type        = string
}
variable "subnets" {
    description = "A list of subnets to create within the VPC."
    type = list(object({
        name       = string
        cidr_block = string
        region     = string
    }))
}