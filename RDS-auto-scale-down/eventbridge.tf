# EventBridge Rule for scheduled scaling
# デフォルトでは無効化。update-schedule Lambda関数で必要な日時に有効化する
resource "aws_cloudwatch_event_rule" "schedule_scaling" {
  name                = "${var.project_name}-${var.environment}-schedule-scaling"
  description         = "Trigger Aurora scaling at specified time (disabled by default)"
  schedule_expression = "cron(0 15 * * ? *)"  # デフォルト値（update-scheduleで上書きされる）
  state               = "DISABLED"  # デフォルトでは無効化

  tags = var.tags
}

# EventBridge Target: Lambda function
resource "aws_cloudwatch_event_target" "schedule_scaling_target" {
  rule      = aws_cloudwatch_event_rule.schedule_scaling.name
  target_id = "ScheduleScalingTarget"
  arn       = aws_lambda_function.schedule_scaling.arn
  
  # 入力パラメータに設定を含める（コンソールから変更可能）
  input = jsonencode({
    clusterIdentifier = aws_rds_cluster.main.cluster_identifier
    targetClass       = "db.t4g.medium"  # デフォルト値（コンソールから変更可能）
  })
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "schedule_scaling_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.schedule_scaling.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule_scaling.arn
}

# SSM Parameter for target class configuration (オプション: 使わない場合は削除可能)
# EventBridgeルールの入力パラメータで設定できるため、必須ではありません
# 現在は使用していないためコメントアウト
# resource "aws_ssm_parameter" "target_class" {
#   name        = "/aurora-scaling/${aws_rds_cluster.main.cluster_identifier}/targetClass"
#   description = "Target instance class for Aurora scaling (optional, can be set in EventBridge rule input)"
#   type        = "String"
#   value       = "db.t4g.medium"  # デフォルト値
#
#   tags = merge(var.tags, {
#     Name = "${var.project_name}-${var.environment}-target-class"
#   })
# }

