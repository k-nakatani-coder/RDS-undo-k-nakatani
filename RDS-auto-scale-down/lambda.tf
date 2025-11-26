# Lambda関数用のセキュリティグループ (VPC接続用)
resource "aws_security_group" "lambda" {
  name_prefix = "${var.project_name}-${var.environment}-lambda-sg"
  description = "Security group for Lambda functions"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-lambda-sg"
  })
}

# Lambda関数のパッケージング
data "archive_file" "modify_instance" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/modify_instance/index.py"
  output_path = "${path.module}/.terraform/lambda_zips/modify_instance.zip"
}

data "archive_file" "check_instance_status" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/check_instance_status/index.py"
  output_path = "${path.module}/.terraform/lambda_zips/check_instance_status.zip"
}

data "archive_file" "send_notification" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/send_notification/index.py"
  output_path = "${path.module}/.terraform/lambda_zips/send_notification.zip"
}

data "archive_file" "failover_cluster" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/failover_cluster/index.py"
  output_path = "${path.module}/.terraform/lambda_zips/failover_cluster.zip"
}

data "archive_file" "get_cluster_instances" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/get_cluster_instances/index.py"
  output_path = "${path.module}/.terraform/lambda_zips/get_cluster_instances.zip"
}

data "archive_file" "schedule_scaling" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/schedule_scaling/index.py"
  output_path = "${path.module}/.terraform/lambda_zips/schedule_scaling.zip"
}

data "archive_file" "update_schedule" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/update_schedule/index.py"
  output_path = "${path.module}/.terraform/lambda_zips/update_schedule.zip"
}



# 1. 通知用Lambdaのロール
resource "aws_iam_role" "lambda_notification" {
  name = "${var.project_name}-${var.environment}-lambda-notification-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# 2. 通知用Lambdaに必要な「ログ書き込み」権限 (AWS管理ポリシー)
resource "aws_iam_role_policy_attachment" "lambda_notification_logs" {
  role       = aws_iam_role.lambda_notification.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 3. 通知用Lambdaに必要な「SNS発行」権限ポリシー
resource "aws_iam_policy" "lambda_sns_publish" {
  name        = "${var.project_name}-${var.environment}-lambda-sns-publish"
  description = "Policy for Lambda to publish to SNS topic"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        # このプロジェクトで作成するSNSトピックにのみ許可
        Resource = aws_sns_topic.aurora_alerts.arn
      }
    ]
  })
}

# 4. SNS発行権限をロールにアタッチ
resource "aws_iam_role_policy_attachment" "lambda_notification_sns" {
  role       = aws_iam_role.lambda_notification.name
  policy_arn = aws_iam_policy.lambda_sns_publish.arn
}



# Lambda実行ロールにVPC権限を追加 (スケーリング用ロールのみ)
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda_scaling.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Lambda関数: ModifyInstance (VPC接続あり)
resource "aws_lambda_function" "modify_instance" {
  filename         = data.archive_file.modify_instance.output_path
  function_name    = "${var.project_name}-${var.environment}-modify-instance"
  role             = aws_iam_role.lambda_scaling.arn # 強力な権限を持つロール
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.modify_instance.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60

  # VPC接続 (RDSアクセスに必須)
  vpc_config {
    subnet_ids         = aws_subnet.lambda[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_rds_management,
    aws_iam_role_policy_attachment.lambda_vpc_execution
  ]
}

# Lambda関数: CheckInstanceStatus (VPC接続あり)
resource "aws_lambda_function" "check_instance_status" {
  filename         = data.archive_file.check_instance_status.output_path
  function_name    = "${var.project_name}-${var.environment}-check-instance-status"
  role             = aws_iam_role.lambda_scaling.arn # 強力な権限を持つロール
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.check_instance_status.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30

  # VPC接続 (RDSアクセスに必須)
  vpc_config {
    subnet_ids         = aws_subnet.lambda[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_rds_management,
    aws_iam_role_policy_attachment.lambda_vpc_execution
  ]
}

# Lambda関数: FailoverCluster (VPC接続あり)
resource "aws_lambda_function" "failover_cluster" {
  filename         = data.archive_file.failover_cluster.output_path
  function_name    = "${var.project_name}-${var.environment}-failover-cluster"
  role             = aws_iam_role.lambda_scaling.arn
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.failover_cluster.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60

  # VPC接続 (RDSアクセスに必須)
  vpc_config {
    subnet_ids         = aws_subnet.lambda[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_rds_management,
    aws_iam_role_policy_attachment.lambda_vpc_execution
  ]
}

# Lambda関数: SendNotification
resource "aws_lambda_function" "send_notification" {
  filename         = data.archive_file.send_notification.output_path
  function_name    = "${var.project_name}-${var.environment}-send-notification"
  # 改善点: 権限を分離した専用ロールを使用
  role             = aws_iam_role.lambda_notification.arn
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.send_notification.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30


  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.aurora_alerts.arn
      ENVIRONMENT   = var.environment
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_notification_sns,
    aws_iam_role_policy_attachment.lambda_notification_logs
  ]
}

# Lambda関数: GetClusterInstances (VPC接続あり)
resource "aws_lambda_function" "get_cluster_instances" {
  filename         = data.archive_file.get_cluster_instances.output_path
  function_name    = "${var.project_name}-${var.environment}-get-cluster-instances"
  role             = aws_iam_role.lambda_scaling.arn
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.get_cluster_instances.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60

  # VPC接続 (RDSアクセスに必須)
  vpc_config {
    subnet_ids         = aws_subnet.lambda[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_rds_management,
    aws_iam_role_policy_attachment.lambda_vpc_execution
  ]
}

# Lambda関数: ScheduleScaling
resource "aws_lambda_function" "schedule_scaling" {
  filename         = data.archive_file.schedule_scaling.output_path
  function_name    = "${var.project_name}-${var.environment}-schedule-scaling"
  role             = aws_iam_role.lambda_scaling.arn
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.schedule_scaling.output_base64sha256
  runtime          = "python3.11"
  timeout          = 900

  # VPC接続 (RDSアクセスに必須)
  vpc_config {
    subnet_ids         = aws_subnet.lambda[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      ENVIRONMENT              = var.environment
      CLUSTER_IDENTIFIER       = aws_rds_cluster.main.cluster_identifier
      STEP_FUNCTION_ARN        = aws_sfn_state_machine.aurora_scaling.arn
      GET_INSTANCES_FUNCTION_NAME = aws_lambda_function.get_cluster_instances.function_name
      EVENTBRIDGE_RULE_NAME   = aws_cloudwatch_event_rule.schedule_scaling.name
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_rds_management,
    aws_iam_role_policy_attachment.lambda_vpc_execution
  ]
}

# Lambda関数: UpdateSchedule
resource "aws_lambda_function" "update_schedule" {
  filename         = data.archive_file.update_schedule.output_path
  function_name    = "${var.project_name}-${var.environment}-update-schedule"
  role             = aws_iam_role.lambda_scaling.arn
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.update_schedule.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30

  environment {
    variables = {
      ENVIRONMENT          = var.environment
      PROJECT_NAME         = var.project_name
      CLUSTER_IDENTIFIER   = aws_rds_cluster.main.cluster_identifier
      EVENTBRIDGE_RULE_NAME = aws_cloudwatch_event_rule.schedule_scaling.name
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_rds_management
  ]
}

# SNSトピック
resource "aws_sns_topic" "aurora_alerts" {
  name = "${var.project_name}-${var.environment}-aurora-scaling-alerts"
  
  tags = var.tags
}