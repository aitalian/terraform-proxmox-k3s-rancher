# https://registry.terraform.io/providers/Telmate/proxmox/latest/docs/resources/vm_qemu
resource "proxmox_vm_qemu" "control-plane" {
    # control-plane nodes are known in k3s as a server; worker nodes are agent
    count   = 3
    name    = "control-${count.index}"
    tags    = "control"

    target_node = var.proxmox_node

    clone = var.template_name

    agent    = 1
    os_type  = "cloud-init"
    cores    = 2
    sockets  = 1
    cpu      = "host"
    memory   = 2048
    scsihw   = "virtio-scsi-pci"
    bootdisk = "scsi0"

    disk {
        slot     = 0
        size     = "10G"
        type     = "scsi"
        storage  = "iscsi-lvm"
        iothread = 1
    }

    network {
        model  = "virtio"
        bridge = "vmbr0"
    }

    lifecycle {
        ignore_changes = [
            network,
        ]
    }

    ipconfig0 = "ip=dhcp"

    nameserver = "${var.proxmox_dns}"

    sshkeys = file("${var.ssh_public_key_path}")

    connection {
        type        = "ssh"
        user        = "ubuntu"
        private_key = file("${var.ssh_private_key_path}")
        host        = self.default_ipv4_address
    }

    provisioner "file" {
        destination = "/tmp/bootstrap_k3s.sh"
        content = templatefile("bootstrap_k3s.sh.tpl",
            {
                k3s_token = var.k3s_token,
                k3s_cluster_join_ip = proxmox_vm_qemu.control-plane[0].default_ipv4_address
            }
        )
    }

    provisioner "remote-exec" {
        inline = [
            "set -e",
            "chmod +x /tmp/bootstrap_k3s.sh",
            "sudo /tmp/bootstrap_k3s.sh"
        ]
    }
}

resource "proxmox_vm_qemu" "worker" {
    # agent (worker) nodes
    count   = 2
    name    = "worker-${count.index}"
    tags    = "worker"

    depends_on = [
      proxmox_vm_qemu.control-plane[0]
    ]

    target_node = var.proxmox_node

    clone = var.template_name

    agent    = 1
    os_type  = "cloud-init"
    cores    = 2
    sockets  = 1
    cpu      = "host"
    memory   = 2048
    scsihw   = "virtio-scsi-pci"
    bootdisk = "scsi0"

    disk {
        slot     = 0
        size     = "10G"
        type     = "scsi"
        storage  = "iscsi-lvm"
        iothread = 1
    }

    network {
        model  = "virtio"
        bridge = "vmbr0"
    }

    lifecycle {
        ignore_changes = [
            network,
        ]
    }

    ipconfig0 = "ip=dhcp"

    nameserver = "${var.proxmox_dns}"

    sshkeys = file("${var.ssh_public_key_path}")

    connection {
        type        = "ssh"
        user        = "ubuntu"
        private_key = file("${var.ssh_private_key_path}")
        host        = self.default_ipv4_address
    }

    provisioner "file" {
        destination = "/tmp/bootstrap_k3s.sh"
        content = templatefile("bootstrap_k3s.sh.tpl",
            {
                k3s_token = var.k3s_token,
                k3s_cluster_join_ip = proxmox_vm_qemu.control-plane[0].default_ipv4_address
            }
        )
    }

    provisioner "remote-exec" {
        inline = [
            "set -e",
            "chmod +x /tmp/bootstrap_k3s.sh",
            "sudo /tmp/bootstrap_k3s.sh"
        ]
    }
}
