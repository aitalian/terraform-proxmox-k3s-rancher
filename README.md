# terraform-proxmox-k3s-rancher

Useful for labbing at home, this repository provides a quick and easy way to deploy a [K3s](https://k3s.io/) cluster on an existing [Proxmox VE](https://www.proxmox.com/en/proxmox-ve) hypervisor using [Terraform](https://www.terraform.io/).

## Setup

Before getting started, a Proxmox API token is required so that you can use Terraform with your Proxmox datacenter.

On your Proxmox host:

```sh
pveum role add TerraformProv -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.Audit VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit"

pveum user add terraform-prov@pve

### IMPORTANT: Copy/paste and save the token value (secret) presented after running the command below. You are only shown it once and need to set it later as PM_API_TOKEN_SECRET
pveum user token add terraform-prov@pve mytoken

pveum aclmod / -user terraform-prov@pve -tokens 'terraform-prov@pve!mytoken' -role TerraformProv
```

On your workstation:

```sh
# Set the below appropriately for your Proxmox API token ID, secret, and API URL
export PM_API_TOKEN_ID='terraform-prov@pve!mytoken'
export PM_API_TOKEN_SECRET="afcd8f45-acc1-4d0f-bb12-a70b0777ec11"
export PM_API_URL="https://proxmox-server01.example.com:8006/api2/json"

# Set to the default username for the image being used (e.g. ubuntu, cloud-user, etc.)
export SSH_USERNAME="ubuntu"

# Set to path of SSH key to be used (must be passwordless)
export SSH_KEY_PATH=~/.ssh/terraform_proxmox_ssh_key_nopassword

# Generate a passwordless SSH keypair to be used
ssh-keygen -f $SSH_KEY_PATH -t ed25519 -C "${PM_API_TOKEN_ID}" -N "" -q
```

## Prepare a Machine Image

In order to deploy VMs or CTs, you need to prepare an image, and have it available as a template on your Proxmox cluster.

### Ubuntu

On your Proxmox host:

```sh
# ------ Configure between the lines as needed

# Set the image URL - must be cloud-init enabled
export IMAGE_URL="https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
# Set a template name to be used
export IMAGE_TEMPLATE_NAME="ubuntu-2004-cloudinit-template"
# Set to your Proxmox storage device name (local-lvm, iscsi-lvm, etc.)
export PROXMOX_STORAGE_NAME="iscsi-lvm"
# Set the template VM ID (must not currently be in use; e.g. 9000)
export PROXMOX_TEMPLATE_VM_ID=9000

# ------

# Download cloud-init image and keep a copy of the original (.orig) since we'll be customizing it
export IMAGE_FILENAME="${IMAGE_URL##*/}"
wget -O $IMAGE_FILENAME $IMAGE_URL
cp $IMAGE_FILENAME ${IMAGE_FILENAME}.orig

# Customize and prepare a golden image
# See: http://manpages.ubuntu.com/manpages/focal/man1/virt-sysprep.1.html
sudo apt update -y && sudo apt install libguestfs-tools -y
sudo virt-sysprep \
  -a $IMAGE_FILENAME \
  --network \
  --update \
  --install qemu-guest-agent,jq,git,curl,vim,wget,unzip \
  --truncate /etc/machine-id

# Create a VM to use as a template - adjust parameters as needed
sudo qm create $PROXMOX_TEMPLATE_VM_ID \
  --name "${IMAGE_TEMPLATE_NAME}" \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0
sudo qm importdisk $PROXMOX_TEMPLATE_VM_ID $IMAGE_FILENAME $PROXMOX_STORAGE_NAME
sudo qm set $PROXMOX_TEMPLATE_VM_ID \
  --scsihw virtio-scsi-pci \
  --scsi0 $PROXMOX_STORAGE_NAME:vm-$PROXMOX_TEMPLATE_VM_ID-disk-0 \
  --boot c --bootdisk scsi0 \
  --ide2 $PROXMOX_STORAGE_NAME:cloudinit \
  --serial0 socket --vga serial0 \
  --agent enabled=1

# Convert VM to a template
sudo qm template $PROXMOX_TEMPLATE_VM_ID
```

## Define and deploy machines in Terraform

In `main.tf`, there are two resource blocks to consider:

- `resource "proxmox_vm_qemu" "control-plane"`
  - Set `count` to an odd number: 1, 3, 5, etc.. For HA, a minimum of 3 control (server) nodes are required
- `resource "proxmox_vm_qemu" "worker"`
  - Set `count` to any number for the desired amount of worker (agent) nodes

For both of the above, tweak resource and networking requirements as needed.

Create `terraform.tfvars`:

```ini
# Must have a passwordless SSH keypair available for use
# Terraform uses this for remote-exec provisioner
# Path should match SSH_KEY_PATH set earlier
ssh_private_key_path = "~/.ssh/terraform_proxmox_ssh_key_nopassword"
ssh_public_key_path  = "~/.ssh/terraform_proxmox_ssh_key_nopassword.pub"

proxmox_node = "name-of-proxmox-node-here"

# Set to your network's DNS server (optional)
proxmox_dns = "192.168.0.1"

# Should match IMAGE_TEMPLATE_NAME set earlier
template_name = "ubuntu-2004-cloudinit-template"
```

Plan and apply. In tests, it took ~11m to create a 5 node cluster (3 control + 2 worker), but of course this varies based on hardware.

```sh
terraform plan
terraform apply -auto-approve
```

## Using the k3s cluster

Then connect to any of the control machines:

```sh
export CONTROL0=$(terraform output -json control-plane | jq -r '."control-0"')
ssh -i $SSH_KEY_PATH $SSH_USERNAME@$CONTROL0

# On control-0
k3s kubectl get nodes
```

Or, copy the kube config from a server node so you can access the cluster from your local machine (externally):

```sh
export CONTROL0=$(terraform output -json control-plane | jq -r ' ."control-0"')
scp -i $SSH_KEY_PATH $SSH_USERNAME@$CONTROL0:/etc/rancher/k3s/k3s.yaml ~/kubeconfig-$CONTROL0-k3s-terraform.yaml
### Edit the downloaded config file and change the "server: https://127.0.0.1:6443" line to match the IP of one of the control machines
sed -i.bak "s/127.0.0.1/${CONTROL0}/" ~/kubeconfig-$CONTROL0-k3s-terraform.yaml
# Use the config using KUBECONFIG OR pass the --kubeconfig flag
export KUBECONFIG=~/kubeconfig-$CONTROL0-k3s-terraform.yaml
kubectl get nodes -o wide
kubectl --kubeconfig ~/kubeconfig-$CONTROL0-k3s-terraform.yaml get pods --all-namespaces

# View all of the external IPs are the ones for each node in the cluster
kubectl -n kube-system get service/traefik -o=jsonpath='{.status.loadBalancer.ingress}' | jq -r 'map(.ip)'
```

### (optional) Install a Dashboard!

You can install a dashboard of your choosing:

#### Option 1: Deploy Rancher

A popular choice on K3s is to deploy the Rancher UI. See: [Quick Start Guide](https://rancher.com/docs/rancher/v2.6/en/quick-start-guide/deployment/quickstart-manual-setup/) for more info.

```sh
# Set a bootstrap admin password
export PASSWORD_FOR_RANCHER_ADMIN="p4nc4K3s"

helm repo add rancher-latest https://releases.rancher.com/server-charts/latest

kubectl create namespace cattle-system

kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.5.1/cert-manager.crds.yaml

helm repo add jetstack https://charts.jetstack.io

helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.5.1

helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=$CONTROL0.nip.io \
  --set replicas=1 \
  --set bootstrapPassword=$PASSWORD_FOR_RANCHER_ADMIN

# Wait awhile for the cluster to become available... (~5 mins depending on cluster)
# Continue on when you see all pods are ready
watch kubectl -n cattle-system get pods
echo "Open your browser to: https://${CONTROL0}.nip.io for the Rancher UI."

# Take the opportunity to change admin's password or you will be locked out...
# If you end up locked out, you can reset the password using:
kubectl -n cattle-system exec $(kubectl -n cattle-system get pods -l app=rancher | grep '1/1' | head -1 | awk '{ print $1 }') -- reset-password
# Then login using admin/<new-password> and change it in the UI properly.
```

To delete the Rancher UI:

```sh
kubectl delete -f https://github.com/jetstack/cert-manager/releases/download/v1.5.1/cert-manager.crds.yaml
helm uninstall rancher --namespace cattle-system
helm uninstall cert-manager --namespace cert-manager
helm repo remove jetstack
helm repo remove rancher-latest
kubectl delete namespace cattle-system
```

#### Option 2: Deploy Kubernetes Dashboard

For a vanilla experience, you can deploy the [Kubernetes Dashboard](https://github.com/kubernetes/dashboard) instead of Rancher.

```sh
# Deploy the kubernetes dashboard as a test
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.5.0/aio/deploy/recommended.yaml
kubectl create serviceaccount dashboard-admin-sa
kubectl create clusterrolebinding dashboard-admin-sa --clusterrole=cluster-admin --serviceaccount=default:dashboard-admin-sa

# Get the secret to login to the dashboard - copy this for the next steps
kubectl get secret $(kubectl get secrets -o json | jq -r '.items[] | select(.metadata.name | test("dashboard-admin-sa-token-")) | .metadata.name') -o jsonpath='{.data.token}' | base64 -d

kubectl proxy
# In your browser open up: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
# Paste the login token from the earlier step
# Use CTRL+C to exit the proxy when you're done
```

To delete the Kubernetes Dashboard:

```sh
kubectl delete -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.5.0/aio/deploy/recommended.yaml
kubectl delete clusterrolebinding dashboard-admin-sa
kubectl delete serviceaccount dashboard-admin-sa
```

## Destroying the cluster

In tests, it took ~4m to destroy a 5 node cluster (3 control + 2 worker), but of course this varies based on hardware.

```sh
$ terraform destroy
```

## Docs

https://registry.terraform.io/providers/Telmate/proxmox/latest/docs
