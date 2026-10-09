resource "google_compute_shared_vpc_host_project" "host" {
  project = var.project_id
}
resource "google_compute_network" "prod-vpc" {
    project = var.project_id
    name = var.vpc_name
    description = "Production VPC"
    auto_create_subnetworks = false
    routing_mode = "REGIONAL"
}
resource "google_compute_subnetwork" "prod-subnets" {
    for_each = { for subnet in var.subnets : subnet.name => subnet } 
    project      = var.project_id
    name          = each.value.name
    ip_cidr_range = each.value.cidr_block
    region        = each.value.region
    network       = google_compute_network.prod-vpc.self_link
}

