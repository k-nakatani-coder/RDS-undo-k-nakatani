
# IAM Role for future Lambda functions
resource "aws_iam_role" "lambda_scaling" {
  name = "${var.project_name}-${var.environment}-lambda-scaling-role"

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

# IAM Policy for Lambda to manage RDS
resource "aws_iam_policy" "lambda_rds_management" {
  name        = "${var.project_name}-${var.environment}-lambda-rds-policy"
  description = "Policy for Lambda to manage RDS instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBInstances",
          "rds:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:ModifyDBInstance",
          "rds:ModifyDBCluster"
        ]
        Resource = [
          "arn:aws:rds:${var.region}:*:cluster:${var.project_name}-${var.environment}-*",
          "arn:aws:rds:${var.region}:*:db:${var.project_name}-${var.environment}-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "rds:FailoverDBCluster"
        ]
        Resource = [
          "arn:aws:rds:${var.region}:*:cluster:${var.project_name}-${var.environment}-*",
          "arn:aws:rds:${var.region}:*:db:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "application-autoscaling:RegisterScalableTarget",
          "application-autoscaling:DeregisterScalableTarget",
          "application-autoscaling:PutScalingPolicy",
          "application-autoscaling:DescribeScalableTargets",
          "application-autoscaling:DescribeScalingPolicies"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter",
          "ssm:DeleteParameter"
        ]
        Resource = "arn:aws:ssm:${var.region}:*:parameter/aurora-scaling/*"
      },
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = "arn:aws:states:${var.region}:*:stateMachine:${var.project_name}-${var.environment}-aurora-scaling"
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${var.region}:*:function:${var.project_name}-${var.environment}-get-cluster-instances"
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutRule",
          "events:PutTargets",
          "events:ListTargetsByRule",
          "events:DescribeRule"
        ]
        Resource = "arn:aws:events:${var.region}:*:rule/${var.project_name}-${var.environment}-schedule-scaling"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_rds_management" {
  role       = aws_iam_role.lambda_scaling.name
  policy_arn = aws_iam_policy.lambda_rds_management.arn
}

# IAM Role for future Step Functions
resource "aws_iam_role" "stepfunctions_execution" {
  name = "${var.project_name}-${var.environment}-stepfunctions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy" "stepfunctions_execution" {
  name        = "${var.project_name}-${var.environment}-stepfunctions-policy"
  description = "Policy for Step Functions to invoke Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${var.region}:*:function:${var.project_name}-${var.environment}-*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "stepfunctions_execution" {
  role       = aws_iam_role.stepfunctions_execution.name
  policy_arn = aws_iam_policy.stepfunctions_execution.arn
}