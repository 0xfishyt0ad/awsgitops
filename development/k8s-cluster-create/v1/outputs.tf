output "cluster_name" {
  value       = aws_eks_cluster.this.name
  description = "Name of the EKS cluster"
}

output "cluster_subnet_a_id" {
  description = "ID of the cluster subnet in availability zone A"
  value       = aws_subnet.cluster_a.id
}

output "cluster_subnet_b_id" {
  description = "ID of the cluster subnet in availability zone A"
  value       = aws_subnet.cluster_b.id
}