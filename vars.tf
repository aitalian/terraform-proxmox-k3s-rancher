variable "ssh_public_key_path" {
  default = "~/.ssh/id_rsa.pub"
}

variable "proxmox_node" {
    default = "node1"
}

variable "proxmox_dns" {
    default = "127.0.0.1"
}

variable "template_name" {
    default = "ubuntu-2004-cloudinit-template"
}

variable "ssh_private_key_path" {
    default   = "~/.ssh/id_rsa"
    sensitive = true
}

variable "k3s_token" {
  default = "myk3stoken"
}
