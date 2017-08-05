# acs-jupyterhub
Set up a JupyterHub on Azure

1. Prerequisites:
    - [acs-engine](https://github.com/Azure/acs-engine/releases)
    - [azure-cli](https://github.com/Azure/azure-cli)
1. Clone this repo
   `git clone https://github.com/yuvipanda/acs-jupyterhub`
   `cd acs-jupyterhub`
1. Login with az
   `az login`
   and identify the subscription you want to use.
1. Create the cluster:
   `./deploy.py -s <SOME_SUBSCRIPTION_ID> -n <A_DEPLOYMENT_NAME>`
   For example:
   `./deploy.py -s da9b666d-5293-4048-8436-43c408e19eca -n my-course-1`
   This takes about 20 minutes and will output the IP address of the JupyterHub proxy.

## Scaling up

1. `./scale-up.py <CLUSTER_NAME> <NEW_NODE_COUNT>`

1. `az group deployment create --name ${NAME} --resource-group ${NAME} --mode Incremental --template-file ./_output/${NAME}/azuredeploy.json --parameters @./_output/${NAME}/azuredeploy.parameters.json`
