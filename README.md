# acs-jupyterhub
Set up a JupyterHub with ACS

1. Prerequisites:
    - [acs-engine](https://github.com/Azure/acs-engine/blob/master/docs/acsengine.md)
        1. Install golang
        2. export GOPATH=${HOME}/go
        3. go get github.com/Azure/acs-engine
        4. go get all
        5. cd ${GOPATH}/src/github.com/Azure/acs-engine
        6. go build
        7. Add ${GOPATH}/src/github.com/Azure/acs-engine to PATH.
    - [azure-cli](https://github.com/Azure/azure-cli)
    - [jq](https://stedolan.github.io/jq/)
1. Clone this repo
   `git clone https://github.com/yuvipanda/acs-jupyterhub`
   `cd acs-jupyterhub`
1. Login with az
   `az login`
   Identify your subscription and save its id.
   `export SUBSCRIPTION_ID=your-subscription-id-...`
   `az account set -s ${SUBSCRIPTION_ID}`
1. Create service account, saving the output.
   `az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/${SUBSCRIPTION_ID}" > rbac.json`
1. Create the cluster:
   `./start.bash <SOME_UNIQUE_CLUSTER_NAME> <PATH_TO_SSH_PUB_KEY>
