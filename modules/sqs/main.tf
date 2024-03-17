
resource "aws_sqs_queue" "notificacao-pagamento" {
  name = var.sqs_name
  sqs_managed_sse_enabled = false
}

resource "aws_sqs_queue_policy" "notificacao-pagamento-policy" {
  queue_url = aws_sqs_queue.notificacao-pagamento.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Sid": "First",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:*",
      "Resource": "${aws_sqs_queue.notificacao-pagamento.arn}"
    }
  ]
}
POLICY
}

resource "aws_sqs_queue" "notificacao-pedido" {
  name = var.sqs_pedido_name
  sqs_managed_sse_enabled = false
}

resource "aws_sqs_queue_policy" "notificacao-pedido-policy" {
  queue_url = aws_sqs_queue.notificacao-pedido.id

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "sqspolicy",
    "Statement": [
        {
        "Sid": "First",
        "Effect": "Allow",
        "Principal": "*",
        "Action": "sqs:*",
        "Resource": "${aws_sqs_queue.notificacao-pedido.arn}"
        }
    ]
}
POLICY
}

resource "aws_sqs_queue" "notificacao_status" {
  name = var.sqs_notificacao_status
  sqs_managed_sse_enabled = false
}

resource "aws_sqs_queue_policy" "notificacao_status-policy" {
  queue_url = aws_sqs_queue.notificacao_status.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Sid": "First",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:*",
      "Resource": "${aws_sqs_queue.notificacao_status.arn}"
    }
  ]
}
POLICY
}

resource "aws_sqs_queue" "notificacao_cliente_inativo" {
  name = var.sqs_notificacao_cliente_inativo
  sqs_managed_sse_enabled = false
}

resource "aws_sqs_queue_policy" "notificacao_cliente_inativo-policy" {
  queue_url = aws_sqs_queue.notificacao_cliente_inativo.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Sid": "First",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:*",
      "Resource": "${aws_sqs_queue.notificacao_cliente_inativo.arn}"
    }
  ]
}
POLICY
}

resource "aws_sqs_queue" "notificacao_pagamento_error" {
  name = var.sqs_notificacao_pagamento_error
  sqs_managed_sse_enabled = false
}

resource "aws_sqs_queue_policy" "notificacao_pagamento_error-policy" {
  queue_url = aws_sqs_queue.notificacao_pagamento_error.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Sid": "First",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:*",
      "Resource": "${aws_sqs_queue.notificacao_pagamento_error.arn}"
    }
  ]
}
POLICY
}