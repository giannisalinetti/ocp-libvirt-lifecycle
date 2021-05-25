#!/bin/bash

# Include cluster config vars file
# A valid file should include the following values
# username='xxxxxxx'
# password='xxxxxxx'
# endpoint='https://api.ocp4.example.com:6443'
. cluster_config


# Global variables
date_fmt=$(date '+%h %d %H:%M:%S')
local_etcd_backups='/root/etcd-backups/'

if [ $# == 0 ]; then 
    echo "Error: an action argument is mandatory. Accepted values: start,shutdown"
    echo "Usage: ocp-lifecycle.sh start|stop"
    exit 1
fi

if [ $1 == '-h' ] || [ $1 == '--help' ]; then
    echo "OCP 4 cluster lifecycle management for libvirt"
    echo "Usage: ocp-lifecycle.sh start|stop"
    exit 0
fi

# Check and download oc CLI
cli_check () {
    # Download latest oc version
    if [ ! -x /usr/local/bin/oc ]; then
        wget -O /tmp/oc.tar.gz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/oc/latest/linux/oc.tar.gz
        tar zxf /tmp/oc.tar.gz -C /usr/local/bin
    fi
}

# Perform graceful cluster shutdown
cluster_shutdown () {
    set -x
    # Authenticate with cluster-admin privileges
    oc login -u ${username} -p ${password} --insecure-skip-tls-verify ${endpoint} > /dev/null 2>&1

    # Get first available master node to performa an etcd backup
    first_master=$(oc get nodes -l node-role.kubernetes.io/master -o jsonpath='{.items[0].status.addresses[0].address}')

    # Run backup script on master
    ssh core@$first_master 'sudo /usr/local/bin/cluster-backup.sh /tmp/etcd-backups && sudo chown -R core:core /tmp/etcd-backups/'
    if [ $? -ne 0 ]; then
        echo "$date_fmt ==== Etcd backup failed, please backup before continuing  ===="
    else
        echo "$date_fmt ==== Copy backup files locally ===="
        scp core@$first_master:/tmp/etcd-backups/* $local_etcd_backups
    fi

    # Get nodes internal addresses
    nodes=$(oc get nodes -o jsonpath='{.items[*].status.addresses[0].address}')

    # Perform graceful shutdown of nodes
    echo "$date_fmt ==== Begin cluster shutdown ===="
    for node in ${nodes[@]}
    do
        echo "$date_fmt ==== Shut down $node ===="
        ssh core@$node sudo shutdown -h 1
    done

    echo "$date_fmt ==== Graceful shutdown completed ===="
    set +x

}


# Perform and check cluster bootstrap
cluster_bootstrap () {
    # Get vms list from virsh console
    vms=$(virsh list --all | grep ocp4 | awk '{print $2}')

    for vm in ${vms[@]}
    do
        echo "$date_fmt ==== Starting $vm ===="
        virsh start $vm
    done

    # Wait 10 minutes before beginning checks
    sleep 600

    # Authenticate with cluster-admin privileges
    oc login -u ${username} -p ${password} --insecure-skip-tls-verify ${ednpoint} > /dev/null 2>&1

    master_nodes=$(oc get nodes -l node-role.kubernetes.io/master -o jsonpath='{.items[*].metadata.name}')
    worker_nodes=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[*].metadata.name}')

    echo "$date_fmt ==== Check master nodes ===="
    loop=false
    while true; do
        for master in ${master_nodes[@]}
        do
            echo "$date_fmt ==== Checking $master ===="
        oc get node $master
            status=$(oc get node $master | sed '1d' | awk '{print $2}')
            if [ $status == 'Not Ready' ]; then
                loop=true
            fi
        done
        if [ loop == 'true' ]; then
        echo "$date_fmt ==== Waiting 120 seconds before restarting the check loop. If it takes too long, check pending csr. ===="
        sleep 120
            continue
        else
        echo "$date_fmt ==== Node check loop completed successfully ===="
        break
        fi
    done

    echo "$date_fmt ==== Check worker nodes ===="
    loop=false
    while true; do
        for worker in ${worker_nodes[@]}
        do
            echo "$date_fmt ==== Checking $worker ===="
        oc get node $worker
            status=$(oc get node $worker | sed '1d' | awk '{print $2}')
            if [ $status == 'Not Ready' ]; then
                loop=true
            fi
        done
        if [ loop == 'true' ]; then
        echo "$date_fmt ==== Waiting 120 seconds before restarting the check loop. If it takes too long, check pending csr. ===="
        sleep 120
            continue
        else
        echo "$date_fmt ==== Node check loop completed successfully ===="
        break
        fi
    done

    # Check cluster operators
    while oc get co | sed '1d' | awk '{print $5}' | grep 'True'
    do
        echo "$date_fmt ==== Waiting for cluster operators to overcome degraded state ===="
        sleep 30
    done

    # Print final cluster status
    echo "$date_fmt ==== Cluster restart completed ===="
    echo ""
    oc get nodes -o wide
}

cli_check
if [ $1 == 'start' ]; then
    cluster_bootstrap
elif [ $1 == 'stop' ]; then
    cluster_shutdown
else
    echo "Error: Please provide a valid argument. Accepted values: start,shutdown"
    echo "Usage: ocp-lifecycle.sh start|stop"
    exit 1
fi

exit 0
