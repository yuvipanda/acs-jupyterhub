#!/bin/bash
# Start a cluster!
set -e
NAME=${1}
SSH_PUB_KEY=${2}

if [ -z "${2}" ]; then
	echo Usage: $0 CLUSTER_NAME PATH_TO_SSH_PUB_KEY
	exit 1
elif [ ! -f ${SSH_PUB_KEY} ]; echo
	echo No such file: ${SSH_PUB_KEY}
	exit 1
elif [ ! -f rbac.json ]; echo
	echo No such file: rbac.json
	exit 1
fi

client_id="$(jq '.["appId"]' rbac.json)"
client_secret="$(jq '.["password"]' rbac.json)"
key_data="$(cat ${SSH_PUB_KEY})"

sed -e "s/DNSPREFIX/${NAME}/" \
	-e "s/CLIENT_ID/${client_id}/" \
	-e "s/CLIENT_SECRET/${client_secret}/" \
	-e "s/KEY_DATA/${key_data}/" \
	cluster.json > ${NAME}.json

# Validate json
python -m json.tool ${NAME}.json

acs-engine generate ${NAME}.json

az group create --name ${NAME} --location westus
az group deployment create --name ${NAME} --resource-group ${NAME} --template-file ./_output/${NAME}/azuredeploy.json --parameters @./_output/${NAME}/azuredeploy.parameters.json
sleep 1m
scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no bootstrap/* datahub@${NAME}.westus.cloudapp.azure.com:
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no datahub@${NAME}.westus.cloudapp.azure.com "sudo bash setup-nfs.bash ${NAME}"
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no datahub@${NAME}.westus.cloudapp.azure.com
