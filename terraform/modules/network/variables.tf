variable "digitalocean_token" {
  type = string
}

variable "region" {
  type = string
}

variable "droplet_ids" {
  type = list(string)
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "external_ips" {
  description = "List of external IPs of the droplets"
  type        = list(string)
}