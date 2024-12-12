variable "digitalocean_token" {
  type = string
}

variable "region" {
  type = string
}

variable "droplet_size" {
  type = string
}

variable "droplet_image" {
  type = string
}

variable "ssh_key_id" {
  type = string
}

variable "vpc_id" {
  description = "ID of the VPC to use for the droplets"
  type        = string
}
