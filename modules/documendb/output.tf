output "documentdb_address" {
  value = aws_docdb_cluster.service.endpoint
}