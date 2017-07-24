#!/bin/bash
# Start a cluster!
set -e
NAME=${1}

sed "s/DNSPREFIX/${NAME}/" cluster.json > ${NAME}.json

acs-engine generate ${NAME}.json

az group create --name ${NAME} --location westus
az group deployment create --name ${NAME} --resource-group ${NAME} --template-file ./_output/${NAME}/azuredeploy.json --parameters @./_output/${NAME}/azuredeploy.parameters.json
sleep 1m
scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no bootstrap/* datahub@${NAME}.westus.cloudapp.azure.com:
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no datahub@${NAME}.westus.cloudapp.azure.com "sudo bash setup.bash ${NAME}"
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no datahub@${NAME}.westus.cloudapp.azure.com
