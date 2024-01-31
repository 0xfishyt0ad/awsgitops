output "database_address" {
  value = aws_db_instance.this.address
}

output "database_name" {
  value = local.name
}

output "database_password" {
  value = random_password.master_password.result
}

output "database_username" {
  value = aws_db_instance.this.username
}