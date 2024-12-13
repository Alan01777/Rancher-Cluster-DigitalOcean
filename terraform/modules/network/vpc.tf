resource "digitalocean_vpc" "rancher_vpc" {
  name     = "rancher-vpc"
  region   = var.region
  ip_range = var.vpc_cidr
}

resource "digitalocean_firewall" "vpc_firewall" {
  name = "rancher-cluster-firewall"

  droplet_ids = var.droplet_ids

  # Expose ports 22, 80, and 443 to the internet
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow all other TCP traffic from the external IPs of the droplets
  inbound_rule {
    protocol         = "tcp"
    port_range       = "all"
    source_addresses = var.external_ips
  }

  # Allow elasticsearch port
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9200"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow all other UDP traffic from the external IPs of the droplets
  inbound_rule {
    protocol         = "udp"
    port_range       = "all"
    source_addresses = var.external_ips
  }

  # Allow all outbound TCP traffic
  outbound_rule {
    protocol              = "tcp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound UDP traffic
  outbound_rule {
    protocol              = "udp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}