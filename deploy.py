#!/usr/bin/python3

import argparse
import json
import os
import subprocess as sp
import sys
import yaml

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
    help='Service principal file, relative to output dir. Will be created if it does not exist. [default=rbac.json].')
parser.add_argument('-d', dest='disks', type=int, default=4,
	help='Managed disk count [default=4].')
parser.add_argument('-D', dest='disk_size', type=int, default=1024,
	help='Disk size (gb) [default=1024].')
args = parser.parse_args()

# stash output data
if not os.path.exists(args.name):
	os.mkdir(args.name)
elif not os.path.isdir(args.name):
	print(args.name + " exists and is not a directory.")
	sys.exit(1)

# create an ssh keypair
ssh_key = os.path.join(args.name, 'id_rsa')
ssh_key_pub = ssh_key + '.pub'
if not os.path.exists(ssh_key):
	cmd = ['ssh-keygen', '-t', 'rsa', '-N', '', '-f', ssh_key]
	r = sp.check_output(cmd)
ssh_key_data = open(ssh_key_pub).read()

# make sure we're using our subscription
cmd = ['az', 'account', 'set', '-s', args.subscription_id]
r = sp.check_output(cmd)

# prepare az service principals
rbac_file = os.path.join(args.name, args.rbac)
if not os.path.exists(rbac_file):
	cmd = ['az', 'ad', 'sp', 'create-for-rbac',
		'--scopes=/subscriptions/{}'.format(args.subscription_id),
		'--role=Contributor']
	rbac_s = sp.check_output(cmd, universal_newlines=True)
	f = open(rbac_file, 'w')
	f.write(rbac_s)
	f.close()
else:
	rbac_s = open(rbac_file).read()
rbac = json.loads(rbac_s)

# create acs-engine cluster file
cluster = json.loads(open('templates/cluster.json.tmpl').read())
cluster['properties']['masterProfile']['dnsPrefix'] = args.name
cluster['properties']['servicePrincipalProfile']['ClientID'] = rbac["appId"]
cluster['properties']['servicePrincipalProfile']['Secret']   = rbac["password"]
cluster['properties']['linuxProfile']['ssh']['publicKeys'][0]['keyData'] = \
	ssh_key_data
write_json(os.path.join(args.name, 'cluster.json'), cluster)

# run acs-engine
cmd = ['acs-engine', 'generate', os.path.join(args.name, 'cluster.json')]
r = sp.check_output(cmd)

# create resource group
cmd = ['az', 'group', 'create', '--name', args.name, '--location', 'westus2']
r = sp.check_output(cmd, universal_newlines=True)

# create the agents
cmd = ['az', 'group', 'deployment', 'create',
	'--name', args.name,
	'--resource-group', args.name,
	'--template-file',
		'./_output/{}/azuredeploy.json'.format(args.name),
	'--parameters',
		'@./_output/{}/azuredeploy.parameters.json'.format(args.name)]
r = sp.check_output(cmd, universal_newlines=True) 

# find our agent pool network details
cmd = ['az', 'network', 'vnet', 'list', '-g', args.name]
vnet = json.loads(sp.check_output(cmd, universal_newlines=True))
agent_pool_vnet_name = vnet[0]['name']
agent_pool_subnet_name = vnet[0]['subnets'][0]['name']
agent_pool_subnet_address_prefix = vnet[0]['subnets'][0]['addressPrefix']

# create nfs server
vm_name = 'nfsserver'
cmd = ['az', 'vm', 'create', '-n', vm_name,
	'--admin-username', 'datahub',
	'--resource-group', args.name,
	'--ssh-key-value', ssh_key_pub,
	'--size', 'Standard_E4s_v3', '--storage-sku', 'Premium_LRS',
	'--vnet-name', agent_pool_vnet_name,
	'--subnet', agent_pool_subnet_name,
	'--location', 'West US 2',
	'--image', 'canonical:ubuntuserver:17.04:latest']
vm_create = sp.check_output(cmd, universal_newlines=True)
write_json(os.path.join(args.name, vm_name + '.json'), vm_create)

# create and attach disks
for i in range(1, args.disks + 1):
	r = sp.check_output(['az', 'vm', 'disk', 'attach', '--new',
		'--disk', vm_name + '-' + str(i),
		'--resource-group', args.name,
		'--vm-name', vm_name,
		'--size-gb', str(args.disk_size),
		'--sku', 'Premium_LRS']) 

# run install script
cmd = ['az', 'vm', 'extension', 'set',
	'--resource-group', args.name,
	'--vm-name', vm_name,
	'--name', 'customScript',
	'--publisher', 'Microsoft.Azure.Extensions',
	'--settings', './script-config.json']
r = sp.check_output(cmd, universal_newlines=True)

# write out pv.yaml and vars.yml with our network/nfs info
nfs_host_ip = json.loads(vm_create)['privateIpAddress']

# prepare to connect to master
ssh_opts = ['-i', ssh_key, '-o', 'UserKnownHostsFile=/dev/null', '-o', 'StrictHostKeyChecking=no', '-o', 'User=datahub']
ssh_host = args.name + '.westus2.cloudapp.azure.com'
os.environ['SSH_AUTH_SOCK'] = ''

# verify ssh works
cmd = ['ssh'] + ssh_opts + [ssh_host, 'true']
sp.check_call(cmd)

# copy bootstrap code/data
cmd = ['scp'] + ssh_opts + ['-r', 'bootstrap', ssh_host + ':']
sp.check_call(cmd)

# copy ansible playbook
cmd = ['ssh'] + ssh_opts + [ssh_host, "git clone https://github.com/berkeley-dsep-infra/k8s-nfs-ansible.git"]
sp.check_call(cmd)

# move .ansible.cfg into place
cmd = ['ssh'] + ssh_opts + [ssh_host, "mv bootstrap/.ansible.cfg ."]
sp.check_call(cmd)

# copy ssh keys
cmd = ['scp'] + ssh_opts + [ssh_key, ssh_key_pub, ssh_host + ':.ssh/']
sp.check_call(cmd)

# setup the cluster
cmd = ['ssh'] + ssh_opts + [ssh_host, "sudo bash bootstrap/setup.bash " + args.name]
sp.check_call(cmd)
