resource "digitalocean_vpc" "rancher_vpc" {
  name   = "rancher-vpc"
  region = var.region
}

resource "digitalocean_firewall" "vpc_firewall" {
  name = "vpc-firewall"

  droplet_ids = []

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

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "all"
    source_addresses = ["10.0.0.0/8"]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "all"
    source_addresses = ["10.0.0.0/8"]
  }

  outbound_rule {
    protocol         = "tcp"
    port_range       = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol         = "udp"
    port_range       = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}