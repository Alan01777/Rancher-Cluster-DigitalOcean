output "droplet_ip_addresses" {
  value = digitalocean_droplet.rancher.*.ipv4_address
}

output "droplet_ids" {
  value = [for droplet in digitalocean_droplet.rancher : droplet.id]
}


output "droplet_names" {
  value = [for droplet in digitalocean_droplet.rancher : droplet.name]
}