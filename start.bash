#!/bin/bash
# Start a cluster!
set -e

# requirements:
#   az login
#   acs-engine is installed, https://github.com/Azure/acs-engine/releases
#

if [ -z "${2}" ]; then
	echo Usage: $0 SUBSCRIPTION_ID CLUSTER_NAME
	exit 1
fi

# 316f6b65-662a-4687-82ac-cbf564f7594e
SUBSCRIPTION_ID=$1
NAME=${2}
STORAGE_ACCOUNT=$(echo $NAME | tr -d '_-')

SSH_KEY=${HOME}/.ssh/az-${NAME}
SSH_KEY_PUB=${SSH_KEY}.pub

if [ -f ${SSH_KEY} ]; then
	echo "Using existing ssh key: ${SSH_KEY}"
else
	ssh-keygen -t rsa -N '' -f ${SSH_KEY}
fi

az account set -s ${SUBSCRIPTION_ID}

if [ ! -f rbac.json ]; then
	az ad sp create-for-rbac --scopes=/subscriptions/${SUBSCRIPTION_ID} \
		--role=Contributor > rbac.json
fi

client_id="$(jq '.["appId"]' rbac.json)"
client_secret="$(jq '.["password"]' rbac.json)"
key_data="$(cat ${SSH_KEY_PUB})"

sed -e "s/DNSPREFIX/${NAME}/" \
	-e "s/CLIENT_ID/${client_id}/" \
	-e "s/CLIENT_SECRET/${client_secret}/" \
	-e "s#KEY_DATA#${key_data}#" \
	cluster.json > ${NAME}.json

# Validate json
python -m json.tool ${NAME}.json

acs-engine generate ${NAME}.json

az group create --name ${NAME} --location westus

# Create the agents
az group deployment create --name ${NAME} --resource-group ${NAME} \
	--template-file ./_output/${NAME}/azuredeploy.json \
	--parameters @./_output/${NAME}/azuredeploy.parameters.json

# Find our agent pool subnet
agent_pool_vnet=$(jq '.["parameters"]["agentpool1Subnet"]["defaultValue"]' _output/${NAME}/azuredeploy.json | xargs) # /16
agent_pool_vnet_name=$(az network vnet list -g $NAME --query '[].name' -o tsv)
agent_pool_subnet_name=$(az network vnet list -g $NAME --query '[].subnets[].name' -o tsv)

# FIXME: parameterize "nfssrv" which is in azuredeploy.json.tmpl
VM_NAME="${NAME}-nfssrv"
az vm create \
	-n                 ${VMNAME} \
	--admin-username   datahub \
	--resource-group   ${NAME} \
	--ssh-key-value    ${SSH_KEY_PUB} \
	--size             Standard_DS13_V2 \
	--storage-sku      Premium_LRS \
	--vnet-name        ${agent_pool_vnet_name} \
	--subnet           ${agent_pool_subnet_name} \
	--location         "West US" \
	--image            canonical:ubuntuserver:17.04:latest > \
		${VM_NAME}.json

for i in {1..4} ; do
	az vm disk attach --new \
		--disk ${VM_NAME}-${i} \
		--resource-group ${NAME} \
		--vm-name ${VM_NAME} \
		--size-gb 1 \
		--sku Premium_LRS
done

az vm extension set --resource-group ${NAME} --vm-name ${VM_NAME} \
	--name customScript --publisher Microsoft.Azure.Extensions \
	--settings ./script-config.json

NFS_HOST_IP=$(jq .privateIpAddress ${VM_NAME}.json | xargs)
sed -e "s/NFS_HOST_IP/${NFS_HOST_IP}/" templates/pv.yaml.tmpl > \
	bootstrap/pv.yaml 

_ssh_opts="-i ${SSH_KEY} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=datahub"
_host=${NAME}.westus.cloudapp.azure.com

ssh ${_ssh_opts} ${_host} true
scp ${_ssh_opts} -r bootstrap/* ${_host}:
ssh ${_ssh_opts} ${_host} "sudo bash setup.bash ${NAME}"

ssh ${_ssh_opts} ${_host}
