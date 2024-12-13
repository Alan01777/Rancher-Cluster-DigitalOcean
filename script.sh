#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Colors for visual feedback
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print banner
echo -e "${YELLOW}"
echo "   _____  .__                __________________________________ "
echo "  /  _  \ |  | _____    ____ \   _  \______  \______  \______  \\"
echo " /  /_\  \|  | \__  \  /    \/  /_\  \  /    /   /    /   /    /"
echo "/    |    \  |__/ __ \|   |  \  \_/   \/    /   /    /   /    / "
echo "\____|__  /____(____  /___|  /\_____  /____/   /____/   /____/  "
echo "        \/          \/     \/       \/                          "
echo -e "${NC}"
echo -e "${YELLOW}This script sets up a Rancher cluster with RKE2 and Longhorn.${NC}"

# Check if ts command is available, if not install moreutils
if ! command -v ts &> /dev/null; then
  echo -e "${YELLOW}Installing moreutils package for ts command...${NC}"
  apt-get update && apt-get install -y moreutils
fi

# Initialize variables
CLOUDFLARE_API_TOKEN=""
cloudflare_zone_id=""
use_cloudflare="no"
rancher_dns=""
letsEncrypt_email=""

# Ensure directories exist
mkdir -p terraform/logs
mkdir -p ansible/logs

# Create log files
touch terraform/logs/terraform_init.log
touch terraform/logs/terraform_apply.log
touch ansible/logs/rke2_install_server.log
touch ansible/logs/rke2_install_agent.log
touch ansible/logs/rke2_install_agent_retry.log
touch ansible/logs/rancher_install.log
touch ansible/logs/longhorn_install.log
touch ansible/logs/post_install.log

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
  echo -e "${RED}Error: DNS name for Rancher is required. Use --rancher_dns=<DNS_NAME>${NC}"
  exit 1
fi

if [ -z "$letsEncrypt_email" ]; then
  echo -e "${RED}Error: Let's Encrypt email is required. Use --letsEncrypt_email=<EMAIL>${NC}"
  exit 1
fi

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
cd terraform
terraform init 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | ts '[%Y-%m-%d %H:%M:%S]' > logs/terraform_init.log

# Apply the Terraform configuration
echo -e "${YELLOW}Applying Terraform configuration...${NC}"
terraform apply -auto-approve 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | ts '[%Y-%m-%d %H:%M:%S]' > logs/terraform_apply.log

# Extract the Terraform output
echo -e "${YELLOW}Extracting Terraform output...${NC}"
terraform_output=$(terraform output -json)
droplet_ip_addresses=$(echo $terraform_output | jq -r '.droplet_ip_addresses.value')
droplet_names=$(echo $terraform_output | jq -r '.droplet_names.value')

# Set the first_ip variable to the IP address of the first node
first_ip=$(echo $droplet_ip_addresses | jq -r '.[0]')

# Generate the Ansible inventory file in YAML format
echo -e "${YELLOW}Generating Ansible inventory file...${NC}"
cat <<EOF > ../ansible/hosts.yml
all:
  children:
    rancher_servers:
      hosts:
        rancher1:
          ansible_host: ${first_ip}
          ansible_user: root
          ansible_ssh_private_key_file: ~/.ssh/new_droplet_key
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
      vars:
        rancher_dns: ${rancher_dns}
        letsEncrypt_email: ${letsEncrypt_email}
    rancher_agents:
      hosts:
EOF

# Add the rest of the nodes to rancher_agents
for i in $(seq 1 $(($(echo $droplet_names | jq length) - 1))); do
  name=$(echo $droplet_names | jq -r ".[$i]")
  ip=$(echo $droplet_ip_addresses | jq -r ".[$i]")
  cat <<EOF >> ../ansible/hosts.yml
        ${name}:
          ansible_host: ${ip}
          ansible_user: root
          ansible_ssh_private_key_file: ~/.ssh/new_droplet_key
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF
done

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

# Test SSH connections
for i in $(seq 0 $(($(echo $droplet_names | jq length) - 1))); do
  name=$(echo $droplet_names | jq -r ".[$i]")
  ip=$(echo $droplet_ip_addresses | jq -r ".[$i]")
  test_ssh_connection $ip || exit 1
done

# Function to extract RKE2 token with retries
extract_rke2_token() {
  local host=$1
  local retries=10
  local count=0
  local token=""

  while [ $count -lt $retries ]; do
    echo -e "${YELLOW}Extracting RKE2 token from the Rancher server (attempt $((count + 1))/$retries)...${NC}" >&2
    token=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/new_droplet_key root@$host cat /var/lib/rancher/rke2/server/node-token || true)
    if [ -n "$token" ]; then
      echo $token
      return 0
    fi
    count=$((count + 1))
    sleep 10
  done

  echo -e "${RED}Failed to extract RKE2 token from the Rancher server after $retries attempts.${NC}" >&2
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

if [ "$use_cloudflare" == "yes" ]; then
  # Update Cloudflare DNS record
  update_cloudflare_dns $rancher_dns $first_ip $cloudflare_zone_id $CLOUDFLARE_API_TOKEN
else
  # Display the IP address for manual DNS record creation
  echo -e "${YELLOW}Please create a DNS record for ${rancher_dns} pointing to ${first_ip}.${NC}"
  echo -e "${YELLOW}Press Enter to continue once the DNS record has been created...${NC}"
  read -r
fi

# Run the Ansible playbook - Install RKE2 Server
echo -e "${YELLOW}Running Ansible playbook to install RKE2 server...${NC}"
ansible-playbook -i ../ansible/hosts.yml ../ansible/rke2_install_server.yaml 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | ts '[%Y-%m-%d %H:%M:%S]' > ../ansible/logs/rke2_install_server.log

# Extract the RKE2 token from the Rancher server
echo -e "${YELLOW}Extracting RKE2 token from the Rancher server...${NC}"
rke2_token=$(extract_rke2_token ${first_ip} | sed 's/\x1b\[[0-9;]*m//g')
if [ $? -ne 0 ]; then
  exit 1
fi

# Add variables for rancher_agents with actual values
cat <<EOF >> ../ansible/hosts.yml
      vars:
        rke2_token: ${rke2_token}
        rancher1_ip: ${first_ip}
EOF

echo -e "${GREEN}Ansible inventory file 'ansible/hosts.yml' generated successfully.${NC}"

# Run the Ansible playbook - Install RKE2 Agent
echo -e "${YELLOW}Running Ansible playbook to install RKE2 agents...${NC}"
ansible-playbook -i ../ansible/hosts.yml ../ansible/rke2_install_agent.yaml 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | ts '[%Y-%m-%d %H:%M:%S]' > ../ansible/logs/rke2_install_agent.log || {
  echo -e "${RED}Retrying Ansible playbook for rancher3...${NC}"
  ansible-playbook -i ../ansible/hosts.yml ../ansible/rke2_install_agent.yaml --limit rancher3 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | ts '[%Y-%m-%d %H:%M:%S]' > ../ansible/logs/rke2_install_agent_retry.log
}

# Run the Ansible playbook - Install Rancher
echo -e "${YELLOW}Running Ansible playbook to install Rancher...${NC}"
ansible-playbook -i ../ansible/hosts.yml ../ansible/rancher_install.yaml 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | ts '[%Y-%m-%d %H:%M:%S]' > ../ansible/logs/rancher_install.log

# Run the Ansible playbook - Install Longhorn
echo -e "${YELLOW}Running Ansible playbook to install Longhorn...${NC}"
ansible-playbook -i ../ansible/hosts.yml ../ansible/longhorn_install.yaml 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | ts '[%Y-%m-%d %H:%M:%S]' > ../ansible/logs/longhorn_install.log

# Run post install tasks
# echo -e "${YELLOW}Running post install tasks...${NC}"
# ansible-playbook -i ../ansible/hosts.yml ../ansible/post_install.yaml 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | ts '[%Y-%m-%d %H:%M:%S]' > ../ansible/logs/post_install.log


# Display all nodes in the cluster
echo -e "${YELLOW}Displaying all nodes in the cluster...${NC}"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/new_droplet_key root@${first_ip} kubectl get nodes

# Display default password for Kibana
echo -e "${YELLOW}Retrieving default password for Kibana...${NC}"
kibana_pass=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/new_droplet_key root@${first_ip} kubectl get secret -n logging $(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/new_droplet_key root@${first_ip} kubectl get serviceaccount kibana -n logging -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.elasticsearch-password}' | base64 --decode)
echo -e "${YELLOW}Default username for Kibana: elastic${NC}"
echo -e "${YELLOW}Default password for Kibana: ${kibana_pass}${NC}"

# Display warning about exposing kibana
echo -e "${YELLOW} Warning: by default, this script does not expose Kibana to the internet. If you want to access Kibana from outside the cluster, you need to expose the service yourself.${NC}"

# Display the final message
echo -e "${GREEN}RKE2 and Rancher installation completed successfully.${NC}\n\n"
echo -e "${YELLOW}Rancher URL: https://${rancher_dns}${NC}"
echo -e "${YELLOW}Username: admin${NC}"
echo -e "${YELLOW}Bootstrap password: admin"

