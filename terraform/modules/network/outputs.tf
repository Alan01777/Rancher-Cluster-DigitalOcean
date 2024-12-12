output "vpc_id" {
  value = digitalocean_vpc.rancher_vpc.id
}

output "whitelisted_external_ips" {
  description = "List of external IPs of the droplets that are whitelisted"
  value       = var.external_ips
}