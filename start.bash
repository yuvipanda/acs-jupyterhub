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

az ad sp create-for-rbac --scopes=/subscriptions/${SUBSCRIPTION_ID} \
	--role=Contributor > rbac.json

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
az group deployment create --name ${NAME} --resource-group ${NAME} \
	--template-file ./_output/${NAME}/azuredeploy.json \
	--parameters @./_output/${NAME}/azuredeploy.parameters.json

agent_pool_subnet=$(jq '.["parameters"]["agentpool1Subnet"]["defaultValue"]' _output/${NAME}/azuredeploy.json | xargs)

arm_nfs_dir="arm_nfs/${NAME}"
if [ ! -d ${arm_nfs_dir} ]; then
	mkdir -p $arm_nfs_dir
fi

param_tmpl_file="templates/azuredeploy.parameters.json.tmpl"
param_file="${arm_nfs_dir}/azuredeploy.parameters.json"
deploy_tmpl_file="templates/azuredeploy.json.tmpl"
deploy_file="${arm_nfs_dir}/azuredeploy.json"

sed -e "s@VNET_SUBNET@${agent_pool_subnet}@" \
	${deploy_tmpl_file} > ${deploy_file}
sed -e "s/DNS_NAME/${NAME}-nfs/" \
	-e "s/STORAGE_ACCOUNT/${STORAGE_ACCOUNT}/" \
	-e "s#KEY_DATA#${key_data}#" \
	${param_tmpl_file} > ${param_file}

az group deployment create \
    --name ${NAME} \
    --resource-group ${NAME} \
    --template-file ./${arm_nfs_dir}/azuredeploy.json \
    --parameters @./${arm_nfs_dir}/azuredeploy.parameters.json
# FIXME: parameterize "nfssrv" which is in azuredeploy.json.tmpl
NFS_HOST_IP=$(az vm list-ip-addresses -g $NAME -n nfssrv \
	--query '[].virtualMachine.network.privateIpAddresses[0]' --out tsv)
sed -e "s/NFS_HOST_IP/${NFS_HOST_IP}/" templates/pv.yaml.tmpl > \
	bootstrap/pv.yaml 

_ssh_opts="-i ${SSH_KEY} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=datahub"
_host=${NAME}.westus.cloudapp.azure.com
echo "wait 90s for ${_host} to become available"
sleep 90s
echo "done waiting"

ssh ${_ssh_opts} ${_host} true
scp ${_ssh_opts} -r bootstrap/* ${_host}:
ssh ${_ssh_opts} ${_host} "sudo bash setup.bash ${NAME}"

ssh ${_ssh_opts} ${_host}
