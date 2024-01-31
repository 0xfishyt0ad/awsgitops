output "cluster_subnet_a_id" {
  value       = aws_subnet.fargate_a.id
  description = "ID of subnet in A zone"
}

output "cluster_subnet_b_id" {
  value       = aws_subnet.fargate_b.id
  description = "ID of subnet in B zone"
}

output "assume_role_arn" {
  value = aws_iam_role.gitlab_ci.arn
}