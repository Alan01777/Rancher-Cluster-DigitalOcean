#!/bin/bash

# Colors for visual feedback
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Initialize variables
CLOUDFLARE_API_TOKEN=""
cloudflare_zone_id=""
use_cloudflare="no"
rancher_dns=""
letsEncrypt_email=""

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --cloudflare_token=*) CLOUDFLARE_API_TOKEN="${1#*=}"; use_cloudflare="yes"; shift ;;
    --cloudflare_zone_id=*) cloudflare_zone_id="${1#*=}"; shift ;;
    --rancher_dns=*) rancher_dns="${1#*=}"; shift ;;
    --letsEncrypt_email=*) letsEncrypt_email="${1#*=}"; shift ;;
    *) echo -e "${RED}Unknown parameter passed: $1${NC}"; exit 1 ;;
  esac
done

# Check if required arguments are provided
if [ -z "$rancher_dns" ]; then
  echo -e "${RED}Error: DNS name for Rancher is required. Use -rancher_dns=<DNS_NAME>${NC}"
  exit 1
fi

if [ -z "$letsEncrypt_email" ]; then
  echo -e "${RED}Error: Let's Encrypt email is required. Use -letsEncrypt_email=<EMAIL>${NC}"
  exit 1
fi

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

# Apply the Terraform configuration
echo -e "${YELLOW}Applying Terraform configuration...${NC}"
terraform apply -auto-approve

# Extract the Terraform output
echo -e "${YELLOW}Extracting Terraform output...${NC}"
terraform_output=$(terraform output -json droplet_ip_addresses)

# Parse the JSON output to get the IP addresses
rancher1_ip=$(echo $terraform_output | jq -r '.rancher1')
rancher2_ip=$(echo $terraform_output | jq -r '.rancher2')
rancher3_ip=$(echo $terraform_output | jq -r '.rancher3')

# Generate the Ansible inventory file
echo -e "${YELLOW}Generating Ansible inventory file...${NC}"
cat <<EOF > rke2/hosts
[rancher_servers]
rancher1 ansible_host=${rancher1_ip} ansible_user=root ansible_ssh_private_key_file=~/.ssh/new_droplet_key rke2_token=<rancher1_token> rancher_dns=${rancher_dns} letsEncrypt_email=${letsEncrypt_email} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

[rancher_agents]
rancher2 ansible_host=${rancher2_ip} ansible_user=root ansible_ssh_private_key_file=~/.ssh/new_droplet_key ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
rancher3 ansible_host=${rancher3_ip} ansible_user=root ansible_ssh_private_key_file=~/.ssh/new_droplet_key ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF

echo -e "${GREEN}Ansible inventory file 'rke2/hosts' generated successfully.${NC}"

# Function to test SSH connection
test_ssh_connection() {
  local host=$1
  local retries=5
  local count=0

  while [ $count -lt $retries ]; do
    echo -e "${YELLOW}Testing SSH connection to $host (attempt $((count + 1))/$retries)...${NC}"
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/new_droplet_key root@$host exit; then
      echo -e "${GREEN}SSH connection to $host successful.${NC}"
      return 0
    fi
    count=$((count + 1))
    sleep 10
  done

  echo -e "${RED}Failed to establish SSH connection to $host after $retries attempts.${NC}"
  return 1
}

# Function to create/update DNS record in Cloudflare
update_cloudflare_dns() {
  local dns_name=$1
  local ip_address=$2
  local zone_id=$3
  local api_token=$4

  echo -e "${YELLOW}Checking if DNS record exists in Cloudflare...${NC}"
  record_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?name=${dns_name}" \
    -H "Authorization: Bearer ${api_token}" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

  if [ "$record_id" != "null" ]; then
    echo -e "${YELLOW}DNS record exists. Updating the record...${NC}"
    response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}" \
      -H "Authorization: Bearer ${api_token}" \
      -H "Content-Type: application/json" \
      --data '{
        "type": "A",
        "name": "'"${dns_name}"'",
        "content": "'"${ip_address}"'",
        "ttl": 120,
        "proxied": false
      }')
  else
    echo -e "${YELLOW}DNS record does not exist. Creating a new record...${NC}"
    response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" \
      -H "Authorization: Bearer ${api_token}" \
      -H "Content-Type: application/json" \
      --data '{
        "type": "A",
        "name": "'"${dns_name}"'",
        "content": "'"${ip_address}"'",
        "ttl": 120,
        "proxied": false
      }')
  fi

  if echo "$response" | grep -q '"success":true'; then
    echo -e "${GREEN}DNS record created/updated successfully.${NC}"
  else
    echo -e "${RED}Failed to create/update DNS record.${NC}"
    echo "$response"
    exit 1
  fi
}

# Test SSH connections
test_ssh_connection $rancher1_ip || exit 1
test_ssh_connection $rancher2_ip || exit 1
test_ssh_connection $rancher3_ip || exit 1

if [ "$use_cloudflare" == "yes" ]; then
  # Update Cloudflare DNS record
  update_cloudflare_dns $rancher_dns $rancher1_ip $cloudflare_zone_id $CLOUDFLARE_API_TOKEN
else
  # Display the IP address for manual DNS record creation
  echo -e "${YELLOW}Please create a DNS record for ${rancher_dns} pointing to ${rancher1_ip}.${NC}"
  echo -e "${YELLOW}Press Enter to continue once the DNS record has been created...${NC}"
  read -r
fi

# Run the Ansible playbook - Install RKE2 Server
echo -e "${YELLOW}Running Ansible playbook to install RKE2 server...${NC}"
ansible-playbook -i rke2/hosts rke2/rke2_install_server.yaml

# Extract the RKE2 token from the Rancher server
echo -e "${YELLOW}Extracting RKE2 token from the Rancher server...${NC}"
rke2_token=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/new_droplet_key root@${rancher1_ip} sudo cat /var/lib/rancher/rke2/server/node-token)
echo -e "${GREEN}Token: ${rke2_token}${NC}"

# Update the Ansible inventory file with the RKE2 token
echo -e "${YELLOW}Updating Ansible inventory file with the RKE2 token...${NC}"
sed -i "s/<rancher1_token>/${rke2_token}/" rke2/hosts

# Run the Ansible playbook - Install RKE2 Agent
echo -e "${YELLOW}Running Ansible playbook to install RKE2 agents...${NC}"
ansible-playbook -i rke2/hosts rke2/rke2_install_agent.yaml || {
  echo -e "${RED}Retrying Ansible playbook for rancher3...${NC}"
  ansible-playbook -i rke2/hosts rke2/rke2_install_agent.yaml --limit rancher3
}

# Run the Ansible playbook - Install Rancher
echo -e "${YELLOW}Running Ansible playbook to install Rancher...${NC}"
ansible-playbook -i rke2/hosts rke2/rancher_install.yaml

# Run the ansible playbook - Install Longhorn
echo -e "${YELLOW}Running Ansible playbook to install Longhorn...${NC}"
ansible-playbook -i rke2/hosts rke2/longhorn_install.yaml

# Display all nodes in the cluster
echo -e "${YELLOW}Displaying all nodes in the cluster...${NC}"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/new_droplet_key root@${rancher1_ip} kubectl get nodes

echo -e "${GREEN}RKE2 and Rancher installation completed successfully.${NC}\n\n"
echo -e "${YELLOW}Rancher URL: https://${rancher_dns}${NC}"
echo -e "${YELLOW}Username: admin${NC}"
echo -e "${YELLOW}Bootstrap password: admin"