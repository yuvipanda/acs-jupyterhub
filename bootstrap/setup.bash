#!/bin/bash
set -e
apt-get install --yes nfs-kernel-server
echo '/export/homes 10.240.0.0/16(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)' > /etc/exports
mkdir -p /export/homes/datahub
chown -R 1000:1000 /export
exportfs -a

curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash
helm init

echo 'waiting 1m'
sleep 1m
echo 'done waiting'

helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update

sed "s/NAME/${0}/" -i config.yaml

helm install jupyterhub/jupyterhub --version=v0.4 --name=jupyterhub --namespace=jupyterhub -f config.yaml

NFS_HOST=$(ip route get 1 | awk '{print $NF;exit}')

sed "s/NFS_HOST_IP/${NFS_HOST}/" -i pv.yaml

kubectl apply -f pv.yaml

PUBLIC_IP=$(kubectl --namespace=jupyterhub get svc proxy-public | grep proxy-public | awk '{ print $3; }')

while [ "${PUBLIC_IP}" == '<pending>' ]; do

    PUBLIC_IP=$(kubectl --namespace=jupyterhub get svc proxy-public | grep proxy-public | awk '{ print $3; }')
    sleep 10s;
done

echo ${PUBLIC_IP}
