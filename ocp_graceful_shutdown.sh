#!/bin/bash

username='admin'
password=':SWmxl>uE|w9'
endpoint='https://api.ocp4.rhocplab.com:6443'

# Download latest oc version
if [ ! -x /usr/local/bin/oc ]; then
    wget -O /tmp/oc.tar.gz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/oc/latest/linux/oc.tar.gz
    tar zxf /tmp/oc.tar.gz -C /usr/local/bin
fi 

# Authenticate with cluster-admin privileges
oc login -u ${username} -p ${password} --insecure-skip-tls-verify ${ednpoint}

# Get nodes list
nodes=$(oc get nodes -o jsonpath='{.items[*].metadata.name}')

# Perform graceful shutdown of nodes
for node in ${nodes[@]}
do
    echo "==== Shut down $node ===="
    ssh core@$node sudo shutdown -h 1
done

