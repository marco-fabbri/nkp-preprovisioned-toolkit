output "jump_host_ip" {
  description = "IPv4 address of the jump host"
  value       = var.jump_host_ip
}

output "control_plane_ips" {
  description = "IPv4 addresses of the control plane nodes"
  value       = var.control_plane_ips
}

output "control_plane_vip" {
  description = "Virtual IP of the control plane endpoint (kube-vip)"
  value       = var.control_plane_vip
}

output "worker_ips" {
  description = "IPv4 addresses of the worker nodes"
  value       = var.worker_ips
}

output "ansible_inventory" {
  description = "inventory.ini snippet for the created VMs (tofu output -raw ansible_inventory)"
  value       = module.layout.ansible_inventory
}
