#!/bin/bash
#sudo apt update > /dev/null
#sudo apt upgrade -y > /dev/null
#sudo apt install -y jq git curl vim wget unzip

if [[ $HOSTNAME =~ ^control-* ]]
then
    # Server (Control Plane)
    if [[ $HOSTNAME -eq 'control-0' ]]
    then
        echo "Initializing k3s cluster installation..." && \
        curl -sfL https://get.k3s.io | K3S_TOKEN=${k3s_token} sh -s - --write-kubeconfig-mode=644 --cluster-init
    else
        # TODO: Write a loop to check that control-0 is available before proceeding
        echo "Installing k3s server and joining to cluster..." && \
        curl -sfL https://get.k3s.io | K3S_TOKEN=${k3s_token} sh -s - --write-kubeconfig-mode=644 --server=https://${k3s_cluster_join_ip}:6443
    fi

    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    k3s kubectl get nodes -o wide
else
    # Agent (Worker)
    echo "Installing k3s agent and joining to cluster..." && \
    curl -sfL https://get.k3s.io | K3S_TOKEN=${k3s_token} K3S_URL=https://${k3s_cluster_join_ip}:6443 sh -
fi
