/*====
RDS
======*/

/* subnet used by rds */
resource "aws_db_subnet_group" "rds_produto_subnet_group" {
  name        = "${var.environment}-rds-produto-subnet-group"
  description = "RDS subnet group"
  subnet_ids  = var.subnet_ids
  tags = {
    Environment = var.environment
  }
}

/* Security Group for resources that want to access the Database */
resource "aws_security_group" "db_produto_access_sg" {
  vpc_id      = var.vpc_id
  name        = "${var.environment}-db-produto-access-sg"
  description = "Allow access to RDS"

  tags = {
    Name        = "${var.environment}-db-produto-access-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "rds_produto_sg" {
  name = "${var.environment}-rds-produto-sg"
  description = "${var.environment} Security Group"
  vpc_id = var.vpc_id
  tags = {
    Name = "${var.environment}-rds-produto-sg"
    Environment =  var.environment
  }

  // allows traffic from the SG itself
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    self = true
  }

  //allow traffic for TCP 5432
  ingress {
    from_port = 5432
    to_port   = 5432
    protocol  = "tcp"
    security_groups = [aws_security_group.db_produto_access_sg.id]
  }

  // outbound internet access
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "rds-produto" {
  identifier             = "${var.environment}-produto-database"
  allocated_storage      = var.allocated_storage
  engine                 = "postgres"
  engine_version         = "14"
  instance_class         = var.instance_class
  multi_az               = var.multi_az
  db_name                = "foodproduto"
  username               = "postgres"
  password               = "Postgres2023"
  db_subnet_group_name   = aws_db_subnet_group.rds_produto_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_produto_sg.id]
  skip_final_snapshot    = true
  tags = {
    Environment = var.environment
  }
}