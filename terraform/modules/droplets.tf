resource "digitalocean_droplet" "rancher" {
  count  = 3
  name   = "rancher${count.index + 1}"
  region = var.region
  size   = var.droplet_size
  image  = var.droplet_image

  ssh_keys = [var.ssh_key_id]

  user_data = <<-EOF
              #!/bin/bash
              # No need to set a password since we are using SSH keys
              EOF
}

output "droplet_ip_addresses" {
  value = {
    for droplet in digitalocean_droplet.rancher:
    droplet.name => droplet.ipv4_address
  }
}