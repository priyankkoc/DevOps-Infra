variable "vpcs" {
    description = "A map of VPCs to create. Each key is the VPC name, and the value is an object containing the project ID, CIDR block, subnets, and labels."
    type = map(object({
        project_id = string
        cidr_block = string
        subnets    = list(object({
        name       = string
        cidr_block = string
        region     = string
        }))
    }))
}