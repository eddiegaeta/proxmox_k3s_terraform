output "k3s_controller_ip" {
  description = "IP address of k3s controller"
  value       = var.k3s_controller_ip
}

output "k3s_controller_hostname" {
  description = "Hostname of k3s controller"
  value       = var.k3s_controller_hostname
}

output "k3s_worker_ips" {
  description = "IP addresses of k3s workers"
  value       = var.k3s_worker_ips
}

output "k3s_worker_hostnames" {
  description = "Hostnames of k3s workers"
  value       = [for i in range(var.k3s_worker_count) : format("%s%02d", var.k3s_worker_hostname_prefix, i + 1)]
}

output "k3s_token" {
  description = "k3s cluster token"
  value       = local.k3s_token
  sensitive   = true
}

output "kubeconfig_command" {
  description = "Command to retrieve kubeconfig"
  value       = "ssh root@${var.k3s_controller_ip} 'cat /etc/rancher/k3s/k3s.yaml'"
}

output "kubectl_command" {
  description = "Example kubectl command"
  value       = "ssh root@${var.k3s_controller_ip} 'kubectl get nodes -o wide'"
}
