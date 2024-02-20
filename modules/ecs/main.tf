/*====
Cloudwatch Log Group
======*/
resource "aws_cloudwatch_log_group" "fast_food_app" {
  name = "fast_food_app"

  tags = {
    Environment = var.environment
    Application = "fast_food_app"
  }
}

/*====
ECR repository to store our Docker images
======*/
resource "aws_ecr_repository" "fast_food_app" {
  name = var.repository_name
}

/*====
ECS cluster
======*/
resource "aws_ecs_cluster" "cluster" {
  name = "${var.environment}-ecs-cluster"
}

/*====
ECS task definitions
======*/

/* the task definition for the web service */
data "template_file" "web_task" {
  template = file("${path.module}/tasks/web_task_definition.json")

  vars = {
    image             = "${aws_ecr_repository.fast_food_app.repository_url}:latest"
    log_group         = aws_cloudwatch_log_group.fast_food_app.name
  }
}

resource "aws_ecs_task_definition" "web" {
  family                   = "${var.environment}-web"
  container_definitions    = data.template_file.web_task.rendered
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

/* security group for ALB */
resource "aws_security_group" "web_inbound_sg" {
  name        = "${var.environment}-web-inbound-sg"
  description = "Allow HTTP from Anywhere into ALB"
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
    Name = "${var.environment}-web-inbound-sg"
  }
}

resource "aws_alb" "alb_fast_food_app" {
  name            = "${var.environment}-alb-fast-food-app"
  subnets         = var.public_subnet_ids
  security_groups = concat(tolist(var.security_groups_ids),
    tolist([aws_security_group.web_inbound_sg.id])
  )

  tags = {
    Name        = "${var.environment}-alb-fast_food_app"
    Environment = var.environment
  }
}

resource "aws_alb_listener" "fast_food_app" {
  load_balancer_arn = aws_alb.alb_fast_food_app.arn
  port              = "80"
  protocol          = "HTTP"
  depends_on        = [aws_alb_target_group.alb_target_group]

  default_action {
    target_group_arn = aws_alb_target_group.alb_target_group.arn
    type             = "forward"
  }
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

/* ecs service scheduler role */
resource "aws_iam_role_policy" "ecs_service_role_policy" {
  name   = "ecs_service_role_policy"
  #policy = "${file("${path.module}/policies/ecs-service-role.json")}"
  policy = data.aws_iam_policy_document.ecs_service_policy.json
  role   = aws_iam_role.ecs_role.id
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
ECS service
======*/

/* Security Group for ECS */
resource "aws_security_group" "ecs_service" {
  vpc_id      = var.vpc_id
  name        = "${var.environment}-ecs-service-sg"
  description = "Allow egress from container"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-ecs-service-sg"
    Environment = var.environment
  }
}

/* Simply specify the family to find the latest ACTIVE revision in that family */
data "aws_ecs_task_definition" "web" {
  task_definition = aws_ecs_task_definition.web.family
  depends_on = [ aws_ecs_task_definition.web ]
}

resource "aws_ecs_service" "web" {
  name            = "${var.environment}-web"
  task_definition = "${aws_ecs_task_definition.web.family}:${max("${aws_ecs_task_definition.web.revision}", "${data.aws_ecs_task_definition.web.revision}")}"
  desired_count   = 1
  launch_type     = "FARGATE"
  cluster =       aws_ecs_cluster.cluster.id

  network_configuration {
    security_groups = concat(tolist(var.security_groups_ids),
      tolist([aws_security_group.web_inbound_sg.id])
    )
    subnets         = var.subnets_ids
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.alb_target_group.arn
    container_name   = "web"
    container_port   = 8080
  }

  depends_on = [aws_alb_target_group.alb_target_group, aws_iam_role_policy.ecs_service_role_policy]
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

resource "aws_appautoscaling_target" "target" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  role_arn           = aws_iam_role.ecs_autoscale_role.arn
  min_capacity       = 1
  max_capacity       = 2
}

resource "aws_appautoscaling_policy" "up" {
  name                    = "${var.environment}_scale_up"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.web.name}"
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

  depends_on = [aws_appautoscaling_target.target]
}

resource "aws_appautoscaling_policy" "down" {
  name                    = "${var.environment}_scale_down"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.web.name}"
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

  depends_on = [aws_appautoscaling_target.target]
}

/* metric used for auto scale */
resource "aws_cloudwatch_metric_alarm" "service_cpu_high" {
  alarm_name          = "${var.environment}_fast_food_app_web_cpu_utilization_high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "85"

  dimensions = {
    ClusterName = aws_ecs_cluster.cluster.name
    ServiceName = aws_ecs_service.web.name
  }

  alarm_actions = [aws_appautoscaling_policy.up.arn]
  ok_actions    = [aws_appautoscaling_policy.down.arn]
}

/*====
FAST FODD PAGAMENTO
======*/

/*====
Cloudwatch Log Group
======*/
resource "aws_cloudwatch_log_group" "fast_food_app_pagamento" {
  name = "fast_food_app_pagamento"

  tags = {
    Environment = var.environment
    Application = "fast_food_app_pagamento"
  }
}

/*====
ECR repository to store our Docker images
======*/
resource "aws_ecr_repository" "fast_food_app_pagamento" {
  name = var.repository_name_pagamento
}

/*====
ECS task definitions
======*/
data "template_file" "pagamento_task" {
  template = file("${path.module}/tasks/pagamento_task_definition.json")

  vars = {
    image                         = "${aws_ecr_repository.fast_food_app_pagamento.repository_url}:latest"
    log_group                     = aws_cloudwatch_log_group.fast_food_app_pagamento.name
  }
}

resource "aws_ecs_task_definition" "pagamento" {
  family                   = "${var.environment}-pagamento"
  container_definitions    = data.template_file.pagamento_task.rendered
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
resource "aws_alb_target_group" "pagamento_alb_target_group" {
  name     = "${var.environment}-pg-alb-tg-group-${random_id.target_group_sufix.hex}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "ip"

  lifecycle {
    create_before_destroy = true
  }
}

/* security group for ALB */
resource "aws_security_group" "pagamento_web_inbound_sg" {
  name        = "${var.environment}-pagamento-web-inbound-sg"
  description = "Allow HTTP from Anywhere into ALB Pagamento"
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
    Name = "${var.environment}-pagamento-web-inbound-sg"
  }
}

resource "aws_alb" "alb_fast_food_app_pagamento" {
  name            = "${var.environment}-pag-alb-fast-food-app"
  subnets         = var.public_subnet_ids
  security_groups = concat(tolist(var.security_groups_ids),
    tolist([aws_security_group.pagamento_web_inbound_sg.id])
  )

  tags = {
    Name        = "${var.environment}-pagamento-alb-fast_food_app"
    Environment = var.environment
  }
}

resource "aws_alb_listener" "fast_food_app_pagamento" {
  load_balancer_arn = aws_alb.alb_fast_food_app_pagamento.arn
  port              = "80"
  protocol          = "HTTP"
  depends_on        = [aws_alb_target_group.pagamento_alb_target_group]

  default_action {
    target_group_arn = aws_alb_target_group.pagamento_alb_target_group.arn
    type             = "forward"
  }
}

data "aws_ecs_task_definition" "pagamento" {
  task_definition = aws_ecs_task_definition.pagamento.family
  depends_on = [ aws_ecs_task_definition.pagamento ]
}

resource "aws_ecs_service" "pagamento" {
  name            = "${var.environment}-pagamento"
  task_definition = "${aws_ecs_task_definition.pagamento.family}:${max("${aws_ecs_task_definition.pagamento.revision}", "${data.aws_ecs_task_definition.pagamento.revision}")}"
  desired_count   = 1
  launch_type     = "FARGATE"
  cluster =       aws_ecs_cluster.cluster.id

  network_configuration {
    security_groups = concat(tolist(var.security_groups_ids),
      tolist([aws_security_group.pagamento_web_inbound_sg.id])
    )
    subnets         = var.subnets_ids
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.pagamento_alb_target_group.arn
    container_name   = "pagamento"
    container_port   = 8090
  }

  depends_on = [aws_alb_target_group.pagamento_alb_target_group, aws_iam_role_policy.ecs_service_role_policy]
}

resource "aws_appautoscaling_target" "pagamento_target" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.pagamento.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  role_arn           = aws_iam_role.ecs_autoscale_role.arn
  min_capacity       = 1
  max_capacity       = 2
}

resource "aws_appautoscaling_policy" "pagamento_up" {
  name                    = "${var.environment}_scale_up"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.pagamento.name}"
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

  depends_on = [aws_appautoscaling_target.pagamento_target]
}

resource "aws_appautoscaling_policy" "pagamento_down" {
  name                    = "${var.environment}_scale_down"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.pagamento.name}"
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

  depends_on = [aws_appautoscaling_target.pagamento_target]
}

resource "aws_cloudwatch_metric_alarm" "pagamento_service_cpu_high" {
  alarm_name          = "${var.environment}_fast_food_app_pagamento_cpu_utilization_high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "85"

  dimensions = {
    ClusterName = aws_ecs_cluster.cluster.name
    ServiceName = aws_ecs_service.pagamento.name
  }

  alarm_actions = [aws_appautoscaling_policy.pagamento_up.arn]
  ok_actions    = [aws_appautoscaling_policy.pagamento_down.arn]
}

/*====
FAST FODD PRODUCAO
======*/

/*====
Cloudwatch Log Group
======*/
resource "aws_cloudwatch_log_group" "fast_food_app_producao" {
  name = "fast_food_app_producao"

  tags = {
    Environment = var.environment
    Application = "fast_food_app_producao"
  }
}

/*====
ECR repository to store our Docker images
======*/
resource "aws_ecr_repository" "fast_food_app_producao" {
  name = var.repository_name_producao
}

/*====
ECS task definitions
======*/
data "template_file" "producao_task" {
  template = file("${path.module}/tasks/producao_task_definition.json")

  vars = {
    image                         = "${aws_ecr_repository.fast_food_app_producao.repository_url}:latest"
    log_group                     = aws_cloudwatch_log_group.fast_food_app_producao.name
  }
}

resource "aws_ecs_task_definition" "producao" {
  family                   = "${var.environment}-producao"
  container_definitions    = data.template_file.producao_task.rendered
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
resource "aws_alb_target_group" "producao_alb_target_group" {
  name     = "${var.environment}-prod-alb-tg-group-${random_id.target_group_sufix.hex}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "ip"

  lifecycle {
    create_before_destroy = true
  }
}

/* security group for ALB */
resource "aws_security_group" "producao_web_inbound_sg" {
  name        = "${var.environment}-producao-web-inbound-sg"
  description = "Allow HTTP from Anywhere into ALB Producao"
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
    Name = "${var.environment}-producao-web-inbound-sg"
  }
}

resource "aws_alb" "alb_fast_food_app_producao" {
  name            = "${var.environment}-prod-alb-fast-food-app"
  subnets         = var.public_subnet_ids
  security_groups = concat(tolist(var.security_groups_ids),
    tolist([aws_security_group.producao_web_inbound_sg.id])
  )

  tags = {
    Name        = "${var.environment}-producao-alb-fast_food_app"
    Environment = var.environment
  }
}

resource "aws_alb_listener" "fast_food_app_producao" {
  load_balancer_arn = aws_alb.alb_fast_food_app_producao.arn
  port              = "80"
  protocol          = "HTTP"
  depends_on        = [aws_alb_target_group.producao_alb_target_group]

  default_action {
    target_group_arn = aws_alb_target_group.producao_alb_target_group.arn
    type             = "forward"
  }
}

data "aws_ecs_task_definition" "producao" {
  task_definition = aws_ecs_task_definition.producao.family
  depends_on = [ aws_ecs_task_definition.producao ]
}

resource "aws_ecs_service" "producao" {
  name            = "${var.environment}-producao"
  task_definition = "${aws_ecs_task_definition.producao.family}:${max("${aws_ecs_task_definition.producao.revision}", "${data.aws_ecs_task_definition.producao.revision}")}"
  desired_count   = 1
  launch_type     = "FARGATE"
  cluster =       aws_ecs_cluster.cluster.id

  network_configuration {
    security_groups = concat(tolist(var.security_groups_ids),
      tolist([aws_security_group.producao_web_inbound_sg.id])
    )
    subnets         = var.subnets_ids
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.producao_alb_target_group.arn
    container_name   = "producao"
    container_port   = 8082
  }

  depends_on = [aws_alb_target_group.producao_alb_target_group, aws_iam_role_policy.ecs_service_role_policy]
}

resource "aws_appautoscaling_target" "producao_target" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.producao.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  role_arn           = aws_iam_role.ecs_autoscale_role.arn
  min_capacity       = 1
  max_capacity       = 2
}

resource "aws_appautoscaling_policy" "producao_up" {
  name                    = "${var.environment}_scale_up"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.producao.name}"
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

  depends_on = [aws_appautoscaling_target.producao_target]
}

resource "aws_appautoscaling_policy" "producao_down" {
  name                    = "${var.environment}_scale_down"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.producao.name}"
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

  depends_on = [aws_appautoscaling_target.producao_target]
}

resource "aws_cloudwatch_metric_alarm" "producao_service_cpu_high" {
  alarm_name          = "${var.environment}_fast_food_app_producao_cpu_utilization_high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "85"

  dimensions = {
    ClusterName = aws_ecs_cluster.cluster.name
    ServiceName = aws_ecs_service.producao.name
  }

  alarm_actions = [aws_appautoscaling_policy.producao_up.arn]
  ok_actions    = [aws_appautoscaling_policy.producao_down.arn]
}