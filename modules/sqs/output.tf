output "sqs_notificacao_pagamento_url" {
  value = aws_sqs_queue.notificacao-pagamento.url
}

output "sqs_endpoint" {
  value = substr(aws_sqs_queue.notificacao-pagamento.url, 0, length(aws_sqs_queue.notificacao-pagamento.url) - 22)
}