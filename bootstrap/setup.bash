#!/bin/bash

set -e

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
