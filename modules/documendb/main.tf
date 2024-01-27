resource "aws_docdb_subnet_group" "service" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_docdb_cluster_instance" "service" {
  count              = 1
  identifier         = "${var.name}-${count.index}"
  cluster_identifier = aws_docdb_cluster.service.id
  instance_class     = var.docdb_instance_class
}

resource "aws_docdb_cluster" "service" {
  skip_final_snapshot     = true
  db_subnet_group_name    = aws_docdb_subnet_group.service.name
  cluster_identifier      = var.name
  engine                  = "docdb"
  master_username         = var.docdb_user
  master_password         = var.docdb_password
  db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.service.name
  vpc_security_group_ids = var.vpc_security_group_ids
}

resource "aws_docdb_cluster_parameter_group" "service" {
  family = "docdb5.0"
  name = var.name

  parameter {
    name  = "tls"
    value = "disabled"
  }
}