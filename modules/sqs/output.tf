output "sqs_notificacao_pagamento_url" {
  value = aws_sqs_queue.notificacao-pagamento-sync.url
}