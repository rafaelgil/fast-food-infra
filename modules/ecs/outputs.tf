output "repository_url" {
  value = aws_ecr_repository.fast_food_app.repository_url
}

output "cluster_name" {
  value = aws_ecs_cluster.cluster.name
}

output "service_name" {
  value = aws_ecs_service.web.name
}

output "security_group_id" {
  value = aws_security_group.ecs_service.id
}

output "repository_url_pagamento" {
  value = aws_ecr_repository.fast_food_app_pagamento.repository_url
}

output "service_name_pagamento" {
  value = aws_ecs_service.pagamento.name
}
