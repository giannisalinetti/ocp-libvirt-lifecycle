#!/bin/bash


username='admin'
password=':SWmxl>uE|w9'
endpoint='https://api.ocp4.rhocplab.com:6443'

# Download latest oc version
if [ ! -x /usr/local/bin/oc ]; then
    wget -O /tmp/oc.tar.gz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/oc/latest/linux/oc.tar.gz
    tar zxf /tmp/oc.tar.gz -C /usr/local/bin
fi 

# Get vms list from virsh console
vms=$(virsh list --all | grep ocp4 | awk '{print $2}')

for vm in ${vms[@]}
do
    echo "==== Starting $vm ===="
    virsh start $vm
done

# Wait 10 minutes before beginning checks
sleep 600

# Authenticate with cluster-admin privileges
oc login -u ${username} -p ${password} --insecure-skip-tls-verify ${ednpoint} > /dev/null 2>&1

master_nodes=$(oc get nodes -l node-role.kubernetes.io/master -o jsonpath='{.items[*].metadata.name}')
worker_nodes=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[*].metadata.name}')

echo "==== Check master nodes ===="
loop=false
while true; do
    for master in ${master_nodes[@]}
    do
        echo "==== Checking $master ===="
	oc get node $master
        status=$(oc get node $master | sed '1d' | awk '{print $2}')
        if [ $status == 'Not Ready' ]; then
            loop=true
        fi
    done
    if [ loop == 'true' ]; then
	echo "==== Waiting 120 seconds before restarting the check loop ===="
	sleep 120
        continue
    else
	echo "==== Node check loop completed successfully ===="
	break
    fi
done

echo "==== Check worker nodes ===="
loop=false
while true; do
    for worker in ${worker_nodes[@]}
    do
        echo "==== Checking $worker ===="
	oc get node $worker
        status=$(oc get node $worker | sed '1d' | awk '{print $2}')
        if [ $status == 'Not Ready' ]; then
            loop=true
        fi
    done
    if [ loop == 'true' ]; then
	echo "==== Waiting 120 seconds before restarting the check loop ===="
	sleep 120
        continue
    else
	echo "==== Node check loop completed successfully ===="
	break
    fi
done


