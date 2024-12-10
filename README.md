# Rancher and Longhorn Deployment with Terraform and Ansible

This project automates the deployment of a Rancher and Longhorn environment on DigitalOcean using Terraform and Ansible.

## Project Structure

```shell
├── ansible
│ ├── hosts
│ ├── longhorn_install.yaml
│ ├── rancher_install.yaml
│ ├── rke2_install_agent.yaml
│ └── rke2_install_server.yaml
├── terraform
│ ├── main.tf
│ ├── modules
│ │ └── droplets.tf
│ ├── provider.tf
│ ├── state
│ │ ├── terraform.tfstate
│ │ └── terraform.tfstate.backup
│ ├── terraform.tfvars
│ └── variables.tf
├── script.sh
└── README.md
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) installed
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) installed
- [jq](https://stedolan.github.io/jq/download/) installed
- DigitalOcean Account with an API token
- Cloudflare API token and zone ID (if using Cloudflare for DNS)

## Digital Ocean Credentials

Make sure to create a the file `terraform/terraform.tfvar` with your digital ocean credentials.

You can use the following as an example:

```hcl
digitalocean_token = "abcd123456789" # Your API token
region             = "nyc3" # Region
droplet_size       = "s-4vcpu-8gb" # Resources available in the node
droplet_image      = "debian-12-x64" # Image Used
ssh_key_id         = "11223344"  # Replace with the actual ID of the new SSH key
```

## Running the script

Give the proper permissions to the `script.sh`, so it can run:

```shell
chmod +x script.sh
```

### Script Flags


| Flag                                | Optional | Explanation                                                                                                                                            |
|-------------------------------------|----------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| --cloudflare_token=<CLOUDFLARE_API_TOKEN> | yes      | The Cloudflare API token used to authenticate with the Cloudflare API. This flag is optional and only required if you want to use Cloudflare to create the DNS record. |
| --cloudflare_zone_id=<CLOUDFLARE_ZONE_ID> | yes      | The Cloudflare zone ID where the DNS record will be created. This flag is optional and only required if you want to use Cloudflare to create the DNS record. |
| --rancher_dns=<RANCHER_DNS>         | no       | The DNS name that Rancher will use. This flag is required.                                                                                              |
| --letsEncrypt_email=<LETSENCRYPT_EMAIL> | no       | The email address to use for Let's Encrypt. This flag is required.                                                                                      |



### Example Usage

```shell
./script.sh --rancher_dns="rancher.example.com" --letsEncrypt_email="your-email@example.com" --cloudflare_token="your-cloudflare-token" --cloudflare_zone_id="your-zone-id"
```

This will trigger the deployment of the Rancher and Longhorn environment, using Cloudflare for DNS management and Let's Encrypt for SSL certificates.

### Terraform Variables

The following variables should be configured in your terraform/terraform.tfvars file:

* ``digitalocean_token:`` Your DigitalOcean API token.
* ``region:`` Region to deploy resources (default: nyc3).
* ``droplet_size:`` Size of the droplets (default: s-4vcpu-8gb).
* ``droplet_image:`` Image to use for the droplets (default: debian-12-x64).
* ``ssh_key_id:`` ID of the SSH key to use for the droplets

### Ansible Variables

* ``rancher_dns:`` The DNS name to assign to the Rancher instance.
* ``letsEncrypt_email:`` The email address for Let's Encrypt SSL certificates

### Notes

Ensure that you have your Cloudflare API token and zone ID, if you're using Cloudflare for DNS.
Customize the ``terraform/terraform.tfvars`` file with your DigitalOcean settings.
The ``script.sh`` script will create the Ansible inventory file and run the playbooks automatically.


### Troubleshooting
* **SSH Issues**: If you encounter SSH connection issues, verify that your SSH key is correctly configured and available in your environment.
* **Rancher Server Initialization**: The playbooks may fail if the Rancher server is not fully initialized. Ensure that the Rancher server is up and running before proceeding with other tasks.
* **Error Logs**: Check the logs for detailed error messages and consult the documentation for resolution.

## License
This project is licensed under the MIT License. See the LICENSE file for details.