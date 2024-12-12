terraform {
  backend "local" {
    path = "./state/terraform.tfstate"
  }
}

module "network" {
  source = "./modules/network"

  digitalocean_token = var.digitalocean_token
  region             = var.region
  droplet_ids        = module.droplets.droplet_ids
  external_ips       = module.droplets.droplet_ip_addresses
}

module "droplets" {
  source = "./modules/droplets"

  digitalocean_token = var.digitalocean_token
  region             = var.region
  droplet_size       = var.droplet_size
  droplet_image      = var.droplet_image
  ssh_key_id         = var.ssh_key_id
  vpc_id             = module.network.vpc_id
}

output "droplet_ip_addresses" {
  value = module.droplets.droplet_ip_addresses
}

output "droplet_names" {
  value = module.droplets.droplet_names
}