# Network Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "aurora_subnet_ids" {
  description = "Aurora subnet IDs"
  value       = aws_subnet.aurora[*].id
}

output "lambda_subnet_ids" {
  description = "Lambda subnet IDs"
  value       = aws_subnet.lambda[*].id
}

output "aurora_security_group_id" {
  description = "Security group ID for Aurora"
  value       = aws_security_group.aurora.id
}

output "lambda_security_group_id" {
  description = "Security group ID for Lambda"
  value       = aws_security_group.lambda.id
}

# Aurora Cluster Outputs
output "cluster_id" {
  description = "Aurora cluster ID"
  value       = aws_rds_cluster.main.cluster_identifier
}

output "cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = aws_rds_cluster.main.endpoint
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "cluster_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.main.port
}

output "cluster_database_name" {
  description = "Aurora cluster database name"
  value       = aws_rds_cluster.main.database_name
}

# Instance Outputs
output "writer_instance_id" {
  description = "Writer instance ID"
  value       = aws_rds_cluster_instance.writer.identifier
}

output "writer_instance_endpoint" {
  description = "Writer instance endpoint"
  value       = aws_rds_cluster_instance.writer.endpoint
}

output "dedicated_reader_instance_id" {
  description = "Dedicated reader instance ID"
  value       = aws_rds_cluster_instance.dedicated_reader.identifier
}

output "dedicated_reader_instance_endpoint" {
  description = "Dedicated reader instance endpoint"
  value       = aws_rds_cluster_instance.dedicated_reader.endpoint
}

output "autoscaling_reader_instance_ids" {
  description = "Initial AutoScaling reader instance IDs"
  value       = aws_rds_cluster_instance.autoscaling_reader_initial[*].identifier
}

output "autoscaling_reader_instance_endpoints" {
  description = "Initial AutoScaling reader instance endpoints"
  value       = aws_rds_cluster_instance.autoscaling_reader_initial[*].endpoint
}

# IAM Outputs
output "lambda_role_arn" {
  description = "IAM role ARN for Lambda functions"
  value       = aws_iam_role.lambda_scaling.arn
}

output "lambda_role_name" {
  description = "IAM role name for Lambda functions"
  value       = aws_iam_role.lambda_scaling.name
}

output "stepfunctions_role_arn" {
  description = "IAM role ARN for Step Functions"
  value       = aws_iam_role.stepfunctions_execution.arn
}

output "stepfunctions_role_name" {
  description = "IAM role name for Step Functions"
  value       = aws_iam_role.stepfunctions_execution.name
}

# Lambda Function Outputs
output "lambda_function_arns" {
  description = "Lambda function ARNs"
  value = {
    modify_instance       = aws_lambda_function.modify_instance.arn
    check_instance_status = aws_lambda_function.check_instance_status.arn
    send_notification    = aws_lambda_function.send_notification.arn
  }
}

output "lambda_function_names" {
  description = "Lambda function names"
  value = {
    modify_instance       = aws_lambda_function.modify_instance.function_name
    check_instance_status = aws_lambda_function.check_instance_status.function_name
    send_notification    = aws_lambda_function.send_notification.function_name
  }
}

# Step Functions Outputs
output "step_function_arn" {
  description = "Step Functions state machine ARN"
  value       = aws_sfn_state_machine.aurora_scaling.arn
}

output "step_function_name" {
  description = "Step Functions state machine name"
  value       = aws_sfn_state_machine.aurora_scaling.name
}

# VPC Endpoints Outputs
output "vpc_endpoint_ids" {
  description = "VPC Endpoint IDs"
  value = {
    rds    = aws_vpc_endpoint.rds.id
    logs   = aws_vpc_endpoint.logs.id
    states = aws_vpc_endpoint.states.id
  }
}

# SNS Outputs
output "sns_topic_arn" {
  description = "SNS topic ARN for Aurora scaling alerts"
  value       = aws_sns_topic.aurora_alerts.arn
}

output "sns_topic_name" {
  description = "SNS topic name for Aurora scaling alerts"
  value       = aws_sns_topic.aurora_alerts.name
}

# AutoScaling Outputs
output "autoscaling_target_id" {
  description = "AutoScaling target ID"
  value       = aws_appautoscaling_target.aurora_replica_count.id
}

output "autoscaling_min_capacity" {
  description = "AutoScaling minimum capacity"
  value       = aws_appautoscaling_target.aurora_replica_count.min_capacity
}

output "autoscaling_max_capacity" {
  description = "AutoScaling maximum capacity"
  value       = aws_appautoscaling_target.aurora_replica_count.max_capacity
}

# Useful Information for Testing
output "test_input_json" {
  description = "Example JSON input for Step Functions execution (scale down from large to medium)"
  value = jsonencode({
    targetClass                  = "db.t4g.medium"
    clusterIdentifier           = aws_rds_cluster.main.cluster_identifier
    writerInstanceId            = aws_rds_cluster_instance.writer.identifier
    dedicatedReaderInstanceId   = aws_rds_cluster_instance.dedicated_reader.identifier
    autoScalingReaderInstanceIds = aws_rds_cluster_instance.autoscaling_reader_initial[*].identifier
  })
}

output "step_function_console_url" {
  description = "URL to Step Functions console for this state machine"
  value       = "https://console.aws.amazon.com/states/home?region=${var.region}#/statemachines/view/${aws_sfn_state_machine.aurora_scaling.arn}"
}

output "rds_console_url" {
  description = "URL to RDS console for this cluster"
  value       = "https://console.aws.amazon.com/rds/home?region=${var.region}#database:id=${aws_rds_cluster.main.cluster_identifier};is-cluster=true"
}