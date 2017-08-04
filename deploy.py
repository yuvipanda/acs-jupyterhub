#!/usr/bin/python

# TODO: copy ssh key to master

import argparse
import json
import os
import subprocess as sp
import sys

def write_json(filename, data):
	f = open(filename, 'w')
	f.write(json.dumps(data, indent=4, separators=(',', ': ')))
	f.close()

parser = argparse.ArgumentParser(description='Deploy JupyterHub on Kubernetes on Azure')
parser.add_argument('-s', dest='subscription_id', required=True,
	help='Azure subscription id.')
parser.add_argument('-n', dest='name', required=True,
	help='Cluster name.')
parser.add_argument('-r', dest='rbac', default='rbac.json',
    help='Path to Azure service principal json. File will be created if it does not exist. [default=rbac.json].')
parser.add_argument('-d', dest='disks', type=int, default=4,
	help='Managed disk count [default=4].')
parser.add_argument('-D', dest='disk_size', type=int, default=1024,
	help='Disk size (gb) [default=1024].')
args = parser.parse_args()

ssh_key = os.path.join(os.environ['HOME'], '.ssh', 'az-' + args.name)
ssh_key_pub = ssh_key + '.pub'
storage_account = args.name.replace('_', '').replace('-', '')

if not os.path.exists(ssh_key):
	cmd = ['ssh-keygen', '-t', 'rsa', '-N', '', '-f', ssh_key]
	sp.checkout_output(cmd)
ssh_key_data = open(ssh_key).read()

cmd = ['az', 'account', 'set', '-s', args.subscription_id]
sp.checkout_output(cmd)

if not os.path.exists(args.rbac):
	cmd = 'az ad sp create-for-rbac --scopes=/subscriptions/{} --role=Contributor > rbac.json'.format(args.subscription_id)
	sp.check_output(cmd, shell=True)

rbac = json.loads(open(args.rbac).read())

cluster = json.loads(open('cluster.json').read())
cluster['properties']['masterProfile']['dnsPrefix'] = args.name
cluster['properties']['servicePrincipalProfile']['servicePrincipalClientID'] = \
	rbac["appId"]
cluster['properties']['servicePrincipalProfile']['servicePrincipalClientSecret'] = \
	rbac["password"]
cluster['properties']['linuxProfile']['ssh']['publicKeys'][0]['keyData'] = \
	ssh_key_data
write_json(args.name + '.json', cluster)

cmd = ['acs-engine', 'generate', args.name + '.json']
sp.checkout_output(cmd)

# create resource group
cmd = ['az', 'group', 'create', '--name', args.name,
	'--location', 'westus']
sp.checkout_output(cmd)

# create the agents
cmd = ['az', 'group', 'deployment', 'create',
	'--name', args.name,
	'--resource-group', args.name,
	'--template-file',
		'./_output/{}/azuredeploy.json'.format(args.name),
	'--parameters',
		'@./_output/{}/azuredeploy.parameters.json'.format(args.name)]
sp.checkout_output(cmd)

# find our agent pool network details
cmd = ['az', 'network', 'vnet', 'list', '-g', args.name]
vnet = json.loads(sp.check_output(cmd))
agent_pool_vnet_name = vnet[0]['name']
agent_pool_subnet_name = vnet[0]['subnets'][0]['name']

# create nfs server
vm_name = args.name + '-nfs'
cmd = ['az', 'vm', 'create', '-n', 'vm_name',
	'--admin-username', 'datahub',
	'--resource-group', args.name,
	'--ssh-key-value', ssh_key_pub,
	'--size', 'Standard_DS13_V2', '--storage-sku', 'Premium_LRS',
	'--vnet-name', agent_pool_vnet_name,
	'--subnet', agent_pool_subnet_name,
	'--location', 'West US',
	'--image', 'canonical:ubuntuserver:17.04:latest']
vm_create = sp.check_output(cmd)
write_json(vm_name + '.json', vm_create)

# create and attach disks
for i in range(1, args.disks + 1):
	sp.check_output(['az', 'vm', 'disk', 'attach', '--new',
		'--disk', vm_name + '-' + str(i),
		'--resource-group', args.name,
		'--vm-name', vm_name,
		'--size-gb', args.disk_size,
		'--sku', 'Premium_LRS'])

# run install script
cmd = ['az', 'vm', 'extension', 'set',
	'--resource-group', args.name,
	'--vm-name', vm_name,
	'--name', 'customScript',
	'--publisher', 'Microsoft.Azure.Extensions',
	'--settings', './script-config.json']
sp.check_output(cmd)

# write out pv.yaml with our nfs server ip
nfs_host_ip = json.loads(vm_create)['privateIpAddress']
pv = list(yaml.load_all(open('templates/pv.yaml.tmpl').read()))
pv[1]['spec']['nfs']['server'] = nfs_host_ip
f = open('bootstrap/pv.yaml', 'w')
f.write(yaml.dump_all(pv, default_flow_style=False))
f.close()

# prepare to connect to master
ssh_opts = ['-i', ssh_key, '-o', 'UserKnownHostsFile=/dev/null', '-o', 'StrictHostKeyChecking=no', '-o', 'User=datahub']
ssh_host = args.name + '.westus.cloudapp.azure.com'

# verify ssh works
cmd = ['ssh'] + ssh_opts + [ssh_host, 'true']
sp.check_output(cmd)

# copy bootstrap code/data
cmd = ['scp'] + ssh_opts + ['-r', 'bootstrap/*', ssh_host + ':']
sp.check_output(cmd)

# setup the cluster
cmd = ['ssh'] + ssh_opts + [ssh_host, "sudo bash setup.bash " + args.name]
sp.check_output(cmd)
