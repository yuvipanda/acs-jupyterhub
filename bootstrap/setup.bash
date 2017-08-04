#!/bin/bash

set -e

curl -s -S https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash
helm init

echo 'waiting 1m'
sleep 1m
echo 'done waiting'

helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update

helm install jupyterhub/jupyterhub --version=v0.4 --name=jupyterhub --namespace=jupyterhub -f config.yaml

kubectl apply -f pv.yaml

PUBLIC_IP=$(kubectl --namespace=jupyterhub get svc proxy-public | grep proxy-public | awk '{ print $3; }')

while [ "${PUBLIC_IP}" == '<pending>' ]; do

    PUBLIC_IP=$(kubectl --namespace=jupyterhub get svc proxy-public | grep proxy-public | awk '{ print $3; }')
    sleep 10s;
done

echo ${PUBLIC_IP}
