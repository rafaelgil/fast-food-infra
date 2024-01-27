variable "environment" {
  description = "The environment"
}

variable "subnet_ids" {
  description = "Subnet ids"
}

variable "vpc_id" {
  description = "The VPC id"
}

variable "name" {
  default = "fast-food-documentdb"
}

variable "docdb_instance_class" {
  description = "docdb instance class"
}

variable "docdb_password" {
  description = "docdb password"
  default = "fast_food_pagamento_root"
}

variable "docdb_user" {
  description = "docdb user"
  default = "fast_food_pagamento_admin"
}

variable "vpc_security_group_ids" {}