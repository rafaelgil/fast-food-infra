/*====
ECS cluster
======*/
resource "aws_ecs_cluster" "cluster" {
  name = "${var.environment}-ecs-cluster"
}

/*
* IAM service role
*/
data "aws_iam_policy_document" "ecs_service_role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_role" {
  name               = "ecs_role"
  assume_role_policy = data.aws_iam_policy_document.ecs_service_role.json
}

data "aws_iam_policy_document" "ecs_service_policy" {
  statement {
    effect = "Allow"
    resources = ["*"]
    actions = [
      "elasticloadbalancing:Describe*",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "ec2:Describe*",
      "ec2:AuthorizeSecurityGroupIngress"
    ]
  }
}

/* role that the Amazon ECS container agent and the Docker daemon can assume */
resource "aws_iam_role" "ecs_execution_role" {
  name               = "ecs_task_execution_role"
  assume_role_policy = file("${path.module}/policies/ecs-task-execution-role.json")
}
resource "aws_iam_role_policy" "ecs_execution_role_policy" {
  name   = "ecs_execution_role_policy"
  policy = file("${path.module}/policies/ecs-execution-role-policy.json")
  role   = aws_iam_role.ecs_execution_role.id
}

/*====
App Load Balancer
======*/
resource "random_id" "target_group_sufix" {
  byte_length = 2
}

resource "aws_alb_target_group" "alb_target_group" {
  name     = "${var.environment}-alb-target-group-${random_id.target_group_sufix.hex}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "ip"

  lifecycle {
    create_before_destroy = true
  }
}

/* ecs service scheduler role */
resource "aws_iam_role_policy" "ecs_service_role_policy" {
  name   = "ecs_service_role_policy"
  #policy = "${file("${path.module}/policies/ecs-service-role.json")}"
  policy = data.aws_iam_policy_document.ecs_service_policy.json
  role   = aws_iam_role.ecs_role.id
}

/*====
FAST FODD CLIENTE
======*/

/*====
Cloudwatch Log Group
======*/
resource "aws_cloudwatch_log_group" "fast_food_app_cliente" {
  name = "fast_food_app_cliente"

  tags = {
    Environment = var.environment
    Application = "fast_food_app_cliente"
  }
}

/*====
ECR repository to store our Docker images
======*/
resource "aws_ecr_repository" "fast_food_app_cliente" {
  name = var.repository_name_cliente
}

/*====
ECS task definitions
======*/
data "template_file" "cliente_task" {
  template = file("${path.module}/tasks/cliente_task_definition.json")

  vars = {
    image                         = "${aws_ecr_repository.fast_food_app_cliente.repository_url}:latest"
    log_group                     = aws_cloudwatch_log_group.fast_food_app_cliente.name
  }
}

resource "aws_ecs_task_definition" "cliente" {
  family                   = "${var.environment}-cliente"
  container_definitions    = data.template_file.cliente_task.rendered
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_execution_role.arn
}

/*====
App Load Balancer
======*/
resource "aws_alb_target_group" "cliente_alb_target_group" {
  name     = "${var.environment}-cli-alb-tg-group-${random_id.target_group_sufix.hex}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "ip"

  lifecycle {
    create_before_destroy = true
  }
}

/* security group for ALB */
resource "aws_security_group" "cliente_web_inbound_sg" {
  name        = "${var.environment}-cliente-web-inbound-sg"
  description = "Allow HTTP from Anywhere into ALB cliente"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-cliente-web-inbound-sg"
  }
}

resource "aws_alb" "alb_fast_food_app_cliente" {
  name            = "${var.environment}-cli-alb-fast-food-app"
  subnets         = var.public_subnet_ids
  security_groups = concat(tolist(var.security_groups_ids),
    tolist([aws_security_group.cliente_web_inbound_sg.id])
  )

  tags = {
    Name        = "${var.environment}-cliente-alb-fast_food_app"
    Environment = var.environment
  }
}

resource "aws_alb_listener" "fast_food_app_cliente" {
  load_balancer_arn = aws_alb.alb_fast_food_app_cliente.arn
  port              = "80"
  protocol          = "HTTP"
  depends_on        = [aws_alb_target_group.cliente_alb_target_group]

  default_action {
    target_group_arn = aws_alb_target_group.cliente_alb_target_group.arn
    type             = "forward"
  }
}

data "aws_ecs_task_definition" "cliente" {
  task_definition = aws_ecs_task_definition.cliente.family
  depends_on = [ aws_ecs_task_definition.cliente ]
}

resource "aws_ecs_service" "cliente" {
  name            = "${var.environment}-cliente"
  task_definition = "${aws_ecs_task_definition.cliente.family}:${max("${aws_ecs_task_definition.cliente.revision}", "${data.aws_ecs_task_definition.cliente.revision}")}"
  desired_count   = 1
  launch_type     = "FARGATE"
  cluster =       aws_ecs_cluster.cluster.id

  network_configuration {
    security_groups = concat(tolist(var.security_groups_ids),
      tolist([aws_security_group.cliente_web_inbound_sg.id])
    )
    subnets         = var.subnets_ids
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.cliente_alb_target_group.arn
    container_name   = "cliente"
    container_port   = 8083
  }

  depends_on = [aws_alb_target_group.cliente_alb_target_group, aws_iam_role_policy.ecs_service_role_policy]
}

/*====
Auto Scaling for ECS
======*/

resource "aws_iam_role" "ecs_autoscale_role" {
  name               = "${var.environment}_ecs_autoscale_role"
  assume_role_policy = file("${path.module}/policies/ecs-autoscale-role.json")
}
resource "aws_iam_role_policy" "ecs_autoscale_role_policy" {
  name   = "ecs_autoscale_role_policy"
  policy = file("${path.module}/policies/ecs-autoscale-role-policy.json")
  role   = aws_iam_role.ecs_autoscale_role.id
}

resource "aws_appautoscaling_target" "cliente_target" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.cliente.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  role_arn           = aws_iam_role.ecs_autoscale_role.arn
  min_capacity       = 1
  max_capacity       = 2
}

resource "aws_appautoscaling_policy" "cliente_up" {
  name                    = "${var.environment}_scale_up"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.cliente.name}"
  scalable_dimension      = "ecs:service:DesiredCount"


  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment = 1
    }
  }

  depends_on = [aws_appautoscaling_target.cliente_target]
}

resource "aws_appautoscaling_policy" "cliente_down" {
  name                    = "${var.environment}_scale_down"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.cliente.name}"
  scalable_dimension      = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment = -1
    }
  }

  depends_on = [aws_appautoscaling_target.cliente_target]
}

resource "aws_cloudwatch_metric_alarm" "cliente_service_cpu_high" {
  alarm_name          = "${var.environment}_fast_food_app_cliente_cpu_utilization_high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "85"

  dimensions = {
    ClusterName = aws_ecs_cluster.cluster.name
    ServiceName = aws_ecs_service.cliente.name
  }

  alarm_actions = [aws_appautoscaling_policy.cliente_up.arn]
  ok_actions    = [aws_appautoscaling_policy.cliente_down.arn]
}

/*====
FAST FODD PRODUTO
======*/

/*====
Cloudwatch Log Group
======*/
resource "aws_cloudwatch_log_group" "fast_food_app_produto" {
  name = "fast_food_app_produto"

  tags = {
    Environment = var.environment
    Application = "fast_food_app_produto"
  }
}

/*====
ECR repository to store our Docker images
======*/
resource "aws_ecr_repository" "fast_food_app_produto" {
  name = var.repository_name_produto
}

/*====
ECS task definitions
======*/
data "template_file" "produto_task" {
  template = file("${path.module}/tasks/produto_task_definition.json")

  vars = {
    image                         = "${aws_ecr_repository.fast_food_app_produto.repository_url}:latest"
    log_group                     = aws_cloudwatch_log_group.fast_food_app_produto.name
  }
}

resource "aws_ecs_task_definition" "produto" {
  family                   = "${var.environment}-produto"
  container_definitions    = data.template_file.produto_task.rendered
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_execution_role.arn
}

/*====
App Load Balancer
======*/
resource "aws_alb_target_group" "produto_alb_target_group" {
  name     = "${var.environment}-pto-alb-tg-group-${random_id.target_group_sufix.hex}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "ip"

  lifecycle {
    create_before_destroy = true
  }
}

/* security group for ALB */
resource "aws_security_group" "produto_web_inbound_sg" {
  name        = "${var.environment}-produto-web-inbound-sg"
  description = "Allow HTTP from Anywhere into ALB produto"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-produto-web-inbound-sg"
  }
}

resource "aws_alb" "alb_fast_food_app_produto" {
  name            = "${var.environment}-pto-alb-fast-food-app"
  subnets         = var.public_subnet_ids
  security_groups = concat(tolist(var.security_groups_ids),
    tolist([aws_security_group.produto_web_inbound_sg.id])
  )

  tags = {
    Name        = "${var.environment}-produto-alb-fast_food_app"
    Environment = var.environment
  }
}

resource "aws_alb_listener" "fast_food_app_produto" {
  load_balancer_arn = aws_alb.alb_fast_food_app_produto.arn
  port              = "80"
  protocol          = "HTTP"
  depends_on        = [aws_alb_target_group.produto_alb_target_group]

  default_action {
    target_group_arn = aws_alb_target_group.produto_alb_target_group.arn
    type             = "forward"
  }
}

data "aws_ecs_task_definition" "produto" {
  task_definition = aws_ecs_task_definition.produto.family
  depends_on = [ aws_ecs_task_definition.produto ]
}

resource "aws_ecs_service" "produto" {
  name            = "${var.environment}-produto"
  task_definition = "${aws_ecs_task_definition.produto.family}:${max("${aws_ecs_task_definition.produto.revision}", "${data.aws_ecs_task_definition.produto.revision}")}"
  desired_count   = 1
  launch_type     = "FARGATE"
  cluster =       aws_ecs_cluster.cluster.id

  network_configuration {
    security_groups = concat(tolist(var.security_groups_ids),
      tolist([aws_security_group.produto_web_inbound_sg.id])
    )
    subnets         = var.subnets_ids
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.produto_alb_target_group.arn
    container_name   = "produto"
    container_port   = 8084
  }

  depends_on = [aws_alb_target_group.produto_alb_target_group, aws_iam_role_policy.ecs_service_role_policy]
}

resource "aws_appautoscaling_target" "produto_target" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.produto.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  role_arn           = aws_iam_role.ecs_autoscale_role.arn
  min_capacity       = 1
  max_capacity       = 2
}

resource "aws_appautoscaling_policy" "produto_up" {
  name                    = "${var.environment}_scale_up"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.produto.name}"
  scalable_dimension      = "ecs:service:DesiredCount"


  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment = 1
    }
  }

  depends_on = [aws_appautoscaling_target.produto_target]
}

resource "aws_appautoscaling_policy" "produto_down" {
  name                    = "${var.environment}_scale_down"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.produto.name}"
  scalable_dimension      = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment = -1
    }
  }

  depends_on = [aws_appautoscaling_target.produto_target]
}

resource "aws_cloudwatch_metric_alarm" "produto_service_cpu_high" {
  alarm_name          = "${var.environment}_fast_food_app_produto_cpu_utilization_high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "85"

  dimensions = {
    ClusterName = aws_ecs_cluster.cluster.name
    ServiceName = aws_ecs_service.produto.name
  }

  alarm_actions = [aws_appautoscaling_policy.produto_up.arn]
  ok_actions    = [aws_appautoscaling_policy.produto_down.arn]
}