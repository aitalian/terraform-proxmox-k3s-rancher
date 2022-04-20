output "control-plane" {
    value = {
        for node in proxmox_vm_qemu.control-plane:
            node.name => node.default_ipv4_address
    }
}

output "worker" {
    value = {
        for node in proxmox_vm_qemu.worker:
            node.name => node.default_ipv4_address
    }
}
