output "route_table_id" {
  value       = aws_route_table.this.id
  description = "ID of route table pointing to NAT gateway"
}