output "rds_address" {
  value = aws_db_instance.rds-cliente.address
}

output "db_access_sg_id" {
  value = aws_security_group.db_cliente_access_sg.id
}