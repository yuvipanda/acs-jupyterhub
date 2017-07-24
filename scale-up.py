#!/usr/bin/python

# https://github.com/Azure/acs-engine/issues/979

import json
import os
import sys

def save(filename, data):
	f = open(filename + '.new', 'w')
	f.write(json.dumps(data, indent=2, separators=(',', ': ')))
	f.close()
	os.rename(filename, filename + '.orig')
	os.rename(filename + '.new', filename)

try:
	name = sys.argv[1]
	new  = int(sys.argv[2])
except:
	print("Usage: {} NAME NEW_NODE_COUNT".format(sys.argv[0]))
	sys.exit(1)

# Read azuredeploy.parameters.json
param_file = '_output/{}/azuredeploy.parameters.json'.format(name)
buf = open(param_file.format(name)).read()
adp = json.loads(buf)

# Get current node count
num_nodes = adp['parameters']['agentpool1Count']['value']
# Set the offset to current
adp['parameters']['agentpool1Offset'] = { 'value': num_nodes }
# Set the new total
adp['parameters']['agentpool1Count']  = { 'value': new }

save(param_file, adp)


# Read azuredeploy.json
deploy_file = '_output/{}/azuredeploy.json'.format(name)
buf = open(deploy_file.format(name)).read()
ad = json.loads(buf)

# Remove networkSecurityGroups resource
ad['resources'] = list(filter(
	lambda r: r['type'] != 'Microsoft.Network/networkSecurityGroups',
	ad['resources']
))

# Remove nsg ad dependency of virtualNetworks
i = 0; j = 0
nsgdeps = "[concat('Microsoft.Network/networkSecurityGroups/', variables('nsgName'))]"
for i in range(len(ad['resources'])):
	if ad['resources'][i]['type'] == 'Microsoft.Network/virtualNetworks':
		for j in range(len(ad['resources'][i]['dependsOn'])):
			if ad['resources'][i]['dependsOn'][j] == nsgdeps:
				del(ad['resources'][i]['dependsOn'][j])
				break

save(deploy_file, ad)
