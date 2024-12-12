resource "digitalocean_droplet" "rancher" {
  count  = 3
  name   = "rancher${count.index + 1}"
  region = var.region
  size   = var.droplet_size
  image  = var.droplet_image
  
  ssh_keys = [var.ssh_key_id]
  vpc_uuid = var.vpc_id
}