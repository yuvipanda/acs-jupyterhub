#!/bin/bash

set -e

function proxy_public_ip {
	kubectl --namespace=jupyterhub get svc proxy-public | \
		grep proxy-public | awk '{ print $3; }'
}

# install and run ansible
{
	export DEBIAN_PRIORITY=high DEBIAN_FRONTEND=noninteractive
	add-apt-repository -y ppa:ansible/ansible
	apt-get update
	apt-get -y install ansible
} > /dev/null
(
	cd k8s-nfs-ansible
	sudo -u datahub -H ansible-playbook -i hosts playbook.yml
)

# install helm and jupyterhub
curl -s -S https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash
helm init

echo 'waiting 1m'
sleep 1m
echo 'done waiting'

helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update

helm install jupyterhub/jupyterhub --version=v0.4 \
	--name=jupyterhub --namespace=jupyterhub -f \
	config.yaml

# get our public ip
PUBLIC_IP=$(proxy_public_ip)
while [ "${PUBLIC_IP}" == '<pending>' ]; do
    PUBLIC_IP=$(proxy_public_ip)
    sleep 10s
done

echo ${PUBLIC_IP}
