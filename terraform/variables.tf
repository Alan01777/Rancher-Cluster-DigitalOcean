variable "digitalocean_token" {
  description = "DigitalOcean API token"
  type        = string
}

variable "region" {
  description = "Region to deploy resources"
  type        = string
  default     = "nyc3"
}

variable "droplet_size" {
  description = "Size of the droplets"
  type        = string
  default     = "s-4vcpu-8gb"
}

variable "droplet_image" {
  description = "Image to use for the droplets"
  type        = string
  default     = "debian-10-x64"
}

variable "ssh_key_id" {
  description = "ID of the SSH key to use for the droplets"
  type        = string
}