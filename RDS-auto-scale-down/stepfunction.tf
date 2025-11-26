# Step Functions ステートマシン定義
resource "aws_sfn_state_machine" "aurora_scaling" {
  name     = "${var.project_name}-${var.environment}-aurora-scaling"
  role_arn = aws_iam_role.stepfunctions_execution.arn

  definition = jsonencode({
    Comment = "Aurora PostgreSQL Instance Scaling Workflow"
    StartAt = "ValidateInput"
    
    States = {
      ValidateInput = {
        Type = "Pass"
        Parameters = {
          "targetClass.$"                = "$.targetClass"
          "writerInstanceId.$"           = "$.writerInstanceId"
          "dedicatedReaderInstanceId.$"    = "$.dedicatedReaderInstanceId"
          "autoScalingReaderInstanceIds.$" = "$.autoScalingReaderInstanceIds"
          "clusterIdentifier.$"          = "$.clusterIdentifier"
          "executionName.$"              = "$$.Execution.Name"
          "startTime.$"                  = "$$.Execution.StartTime"
          "dedicatedReaderRetryCount"    = 0
          "failoverRetryCount"           = 0
          "oldWriterRetryCount"           = 0
          "autoScalingReaderRetryCount"  = 0
          "overallRetryCount"            = 0
        }
        Next = "ScaleDedicatedReader"
      },
      
      # 1. プライマリリーダーインスタンス（Dedicated Reader）をスケールダウン
      ScaleDedicatedReader = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.modify_instance.arn
          Payload = {
            "instanceId.$"  = "$.dedicatedReaderInstanceId"
            "targetClass.$" = "$.targetClass"
          }
        }
        ResultPath = "$.dedicatedReaderResult"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath = "$.error"
            Next = "CheckDedicatedReaderStatus"
          }
        ]
        Next = "WaitForDedicatedReader"
      },
      
      WaitForDedicatedReader = {
        Type    = "Wait"
        Seconds = 60
        Next    = "CheckDedicatedReaderStatus"
      },
      
      CheckDedicatedReaderStatus = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.check_instance_status.arn
          Payload = {
            "instanceIds.$" = "States.Array($.dedicatedReaderInstanceId)"
            "targetClass.$" = "$.targetClass"
          }
        }
        ResultPath = "$.statusCheckResult"
        Next       = "EvaluateDedicatedReaderStatus"
      },
      
      EvaluateDedicatedReaderStatus = {
        Type    = "Choice"
        Choices = [
          {
            Variable      = "$.statusCheckResult.Payload.allAvailable"
            BooleanEquals = true
            Next          = "FailoverToDedicatedReader"
          },
          {
            Variable      = "$.dedicatedReaderRetryCount"
            NumericGreaterThanEquals = 5
            Next          = "DedicatedReaderStatusError"
          }
        ]
        Default = "IncrementDedicatedReaderRetry"
      },
      
      IncrementDedicatedReaderRetry = {
        Type = "Pass"
        Parameters = {
          "targetClass.$"                = "$.targetClass"
          "writerInstanceId.$"           = "$.writerInstanceId"
          "dedicatedReaderInstanceId.$"    = "$.dedicatedReaderInstanceId"
          "autoScalingReaderInstanceIds.$" = "$.autoScalingReaderInstanceIds"
          "clusterIdentifier.$"          = "$.clusterIdentifier"
          "executionName.$"              = "$.executionName"
          "startTime.$"                  = "$.startTime"
          "dedicatedReaderRetryCount.$"   = "States.MathAdd($.dedicatedReaderRetryCount, 1)"
          "failoverRetryCount.$"         = "$.failoverRetryCount"
          "oldWriterRetryCount.$"         = "$.oldWriterRetryCount"
          "autoScalingReaderRetryCount.$" = "$.autoScalingReaderRetryCount"
          "overallRetryCount.$"          = "$.overallRetryCount"
        }
        Next = "WaitForDedicatedReaderRetry"
      },
      
      WaitForDedicatedReaderRetry = {
        Type    = "Wait"
        Seconds = 600
        Next    = "RefreshDedicatedReaderInfo"
      },
      
      RefreshDedicatedReaderInfo = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.get_cluster_instances.arn
          Payload = {
            "clusterIdentifier.$" = "$.clusterIdentifier"
          }
        }
        ResultPath = "$.refreshedInstanceInfo"
        Next       = "UpdateDedicatedReaderInfo"
      },
      
      UpdateDedicatedReaderInfo = {
        Type = "Pass"
        Parameters = {
          "targetClass.$"                = "$.targetClass"
          "writerInstanceId.$"           = "$.refreshedInstanceInfo.Payload.writerInstanceId"
          "dedicatedReaderInstanceId.$"    = "$.refreshedInstanceInfo.Payload.dedicatedReaderInstanceId"
          "autoScalingReaderInstanceIds.$" = "$.refreshedInstanceInfo.Payload.autoScalingReaderInstanceIds"
          "clusterIdentifier.$"          = "$.clusterIdentifier"
          "executionName.$"              = "$.executionName"
          "startTime.$"                  = "$.startTime"
          "dedicatedReaderRetryCount.$"   = "$.dedicatedReaderRetryCount"
          "failoverRetryCount.$"         = "$.failoverRetryCount"
          "oldWriterRetryCount.$"         = "$.oldWriterRetryCount"
          "autoScalingReaderRetryCount.$" = "$.autoScalingReaderRetryCount"
          "overallRetryCount.$"          = "$.overallRetryCount"
        }
        Next = "CheckDedicatedReaderStatus"
      },
      
      DedicatedReaderStatusError = {
        Type = "Fail"
        Error = "DedicatedReaderStatusTimeout"
        Cause = "Dedicated Reader instance did not become available after 5 retries (50 minutes)"
      },
      
      # 2. スケールダウンしたプライマリリーダーインスタンスをライターインスタンスにフェイルオーバー
      FailoverToDedicatedReader = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.failover_cluster.arn
          Payload = {
            "clusterIdentifier.$" = "$.clusterIdentifier"
            "targetInstanceId.$"   = "$.dedicatedReaderInstanceId"
          }
        }
        ResultPath = "$.failoverResult"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath = "$.error"
            Next = "CheckFailoverStatus"
          }
        ]
        Next       = "WaitForFailover"
      },
      
      WaitForFailover = {
        Type    = "Wait"
        Seconds = 120
        Next    = "CheckFailoverStatus"
      },
      
      CheckFailoverStatus = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.check_instance_status.arn
          Payload = {
            "instanceIds.$" = "States.Array($.dedicatedReaderInstanceId)"
            "targetClass.$" = "$.targetClass"
          }
        }
        ResultPath = "$.failoverStatusCheck"
        Next       = "EvaluateFailoverStatus"
      },
      
      EvaluateFailoverStatus = {
        Type    = "Choice"
        Choices = [
          {
            Variable      = "$.failoverStatusCheck.Payload.allAvailable"
            BooleanEquals = true
            Next          = "ScaleOldWriter"
          },
          {
            Variable      = "$.failoverRetryCount"
            NumericGreaterThanEquals = 5
            Next          = "FailoverStatusError"
          }
        ]
        Default = "IncrementFailoverRetry"
      },
      
      IncrementFailoverRetry = {
        Type = "Pass"
        Parameters = {
          "targetClass.$"                = "$.targetClass"
          "writerInstanceId.$"           = "$.writerInstanceId"
          "dedicatedReaderInstanceId.$"    = "$.dedicatedReaderInstanceId"
          "autoScalingReaderInstanceIds.$" = "$.autoScalingReaderInstanceIds"
          "clusterIdentifier.$"          = "$.clusterIdentifier"
          "executionName.$"              = "$.executionName"
          "startTime.$"                  = "$.startTime"
          "dedicatedReaderRetryCount.$"   = "$.dedicatedReaderRetryCount"
          "failoverRetryCount.$"          = "States.MathAdd($.failoverRetryCount, 1)"
          "oldWriterRetryCount.$"         = "$.oldWriterRetryCount"
          "autoScalingReaderRetryCount.$" = "$.autoScalingReaderRetryCount"
          "overallRetryCount.$"          = "$.overallRetryCount"
        }
        Next = "WaitForFailoverRetry"
      },
      
      WaitForFailoverRetry = {
        Type    = "Wait"
        Seconds = 600
        Next    = "RefreshFailoverInfo"
      },
      
      RefreshFailoverInfo = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.get_cluster_instances.arn
          Payload = {
            "clusterIdentifier.$" = "$.clusterIdentifier"
          }
        }
        ResultPath = "$.refreshedInstanceInfo"
        Next       = "UpdateFailoverInfo"
      },
      
      UpdateFailoverInfo = {
        Type = "Pass"
        Parameters = {
          "targetClass.$"                = "$.targetClass"
          "writerInstanceId.$"           = "$.refreshedInstanceInfo.Payload.writerInstanceId"
          "dedicatedReaderInstanceId.$"    = "$.refreshedInstanceInfo.Payload.dedicatedReaderInstanceId"
          "autoScalingReaderInstanceIds.$" = "$.refreshedInstanceInfo.Payload.autoScalingReaderInstanceIds"
          "clusterIdentifier.$"          = "$.clusterIdentifier"
          "executionName.$"              = "$.executionName"
          "startTime.$"                  = "$.startTime"
          "dedicatedReaderRetryCount.$"   = "$.dedicatedReaderRetryCount"
          "failoverRetryCount.$"         = "$.failoverRetryCount"
          "oldWriterRetryCount.$"         = "$.oldWriterRetryCount"
          "autoScalingReaderRetryCount.$" = "$.autoScalingReaderRetryCount"
          "overallRetryCount.$"          = "$.overallRetryCount"
        }
        Next = "CheckFailoverStatus"
      },
      
      FailoverStatusError = {
        Type = "Fail"
        Error = "FailoverStatusTimeout"
        Cause = "Failover did not complete after 5 retries (50 minutes)"
      },
      
      # 3. 元ライターインスタンスをスケールダウン
      ScaleOldWriter = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.modify_instance.arn
          Payload = {
            "instanceId.$"  = "$.writerInstanceId"
            "targetClass.$" = "$.targetClass"
          }
        }
        ResultPath = "$.oldWriterResult"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath = "$.error"
            Next = "CheckOldWriterStatus"
          }
        ]
        Next = "WaitForOldWriter"
      },
      
      WaitForOldWriter = {
        Type    = "Wait"
        Seconds = 60
        Next    = "CheckOldWriterStatus"
      },
      
      CheckOldWriterStatus = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.check_instance_status.arn
          Payload = {
            "instanceIds.$" = "States.Array($.writerInstanceId)"
            "targetClass.$" = "$.targetClass"
          }
        }
        ResultPath = "$.statusCheckResult"
        Next       = "EvaluateOldWriterStatus"
      },
      
      EvaluateOldWriterStatus = {
        Type    = "Choice"
        Choices = [
          {
            Variable      = "$.statusCheckResult.Payload.allAvailable"
            BooleanEquals = true
            Next          = "ProcessAutoScalingReaders"
          },
          {
            Variable      = "$.oldWriterRetryCount"
            NumericGreaterThanEquals = 5
            Next          = "OldWriterStatusError"
          }
        ]
        Default = "IncrementOldWriterRetry"
      },
      
      IncrementOldWriterRetry = {
        Type = "Pass"
        Parameters = {
          "targetClass.$"                = "$.targetClass"
          "writerInstanceId.$"           = "$.writerInstanceId"
          "dedicatedReaderInstanceId.$"    = "$.dedicatedReaderInstanceId"
          "autoScalingReaderInstanceIds.$" = "$.autoScalingReaderInstanceIds"
          "clusterIdentifier.$"          = "$.clusterIdentifier"
          "executionName.$"              = "$.executionName"
          "startTime.$"                  = "$.startTime"
          "dedicatedReaderRetryCount.$"   = "$.dedicatedReaderRetryCount"
          "failoverRetryCount.$"         = "$.failoverRetryCount"
          "oldWriterRetryCount.$"         = "States.MathAdd($.oldWriterRetryCount, 1)"
          "autoScalingReaderRetryCount.$" = "$.autoScalingReaderRetryCount"
          "overallRetryCount.$"          = "$.overallRetryCount"
        }
        Next = "WaitForOldWriterRetry"
      },
      
      WaitForOldWriterRetry = {
        Type    = "Wait"
        Seconds = 600
        Next    = "RefreshOldWriterInfo"
      },
      
      RefreshOldWriterInfo = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.get_cluster_instances.arn
          Payload = {
            "clusterIdentifier.$" = "$.clusterIdentifier"
          }
        }
        ResultPath = "$.refreshedInstanceInfo"
        Next       = "UpdateOldWriterInfo"
      },
      
      UpdateOldWriterInfo = {
        Type = "Pass"
        Parameters = {
          "targetClass.$"                = "$.targetClass"
          "writerInstanceId.$"           = "$.refreshedInstanceInfo.Payload.writerInstanceId"
          "dedicatedReaderInstanceId.$"    = "$.refreshedInstanceInfo.Payload.dedicatedReaderInstanceId"
          "autoScalingReaderInstanceIds.$" = "$.refreshedInstanceInfo.Payload.autoScalingReaderInstanceIds"
          "clusterIdentifier.$"          = "$.clusterIdentifier"
          "executionName.$"              = "$.executionName"
          "startTime.$"                  = "$.startTime"
          "dedicatedReaderRetryCount.$"   = "$.dedicatedReaderRetryCount"
          "failoverRetryCount.$"         = "$.failoverRetryCount"
          "oldWriterRetryCount.$"         = "$.oldWriterRetryCount"
          "autoScalingReaderRetryCount.$" = "$.autoScalingReaderRetryCount"
          "overallRetryCount.$"          = "$.overallRetryCount"
        }
        Next = "CheckOldWriterStatus"
      },
      
      OldWriterStatusError = {
        Type = "Fail"
        Error = "OldWriterStatusTimeout"
        Cause = "Old Writer instance did not become available after 5 retries (50 minutes)"
      },
      
      ProcessAutoScalingReaders = {
        Type           = "Map"
        Comment        = "AutoScaling Readerを1台ずつ順次変更"
        ItemsPath      = "$.autoScalingReaderInstanceIds"
        MaxConcurrency = 1
        Parameters = {
          "instanceId.$"  = "$$.Map.Item.Value"
          "targetClass.$" = "$.targetClass"
          "autoScalingReaderRetryCount" = 0
          "overallRetryCount.$" = "$.overallRetryCount"
          "writerInstanceId.$" = "$.writerInstanceId"
          "dedicatedReaderInstanceId.$" = "$.dedicatedReaderInstanceId"
          "autoScalingReaderInstanceIds.$" = "$.autoScalingReaderInstanceIds"
          "clusterIdentifier.$" = "$.clusterIdentifier"
          "executionName.$" = "$.executionName"
          "startTime.$" = "$.startTime"
          "dedicatedReaderRetryCount.$" = "$.dedicatedReaderRetryCount"
          "failoverRetryCount.$" = "$.failoverRetryCount"
          "oldWriterRetryCount.$" = "$.oldWriterRetryCount"
        }
        ResultPath = "$.autoScalingResults"
        Iterator = {
          StartAt = "ScaleAutoScalingReader"
          States = {
            ScaleAutoScalingReader = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Parameters = {
                FunctionName = aws_lambda_function.modify_instance.arn
                Payload = {
                  "instanceId.$"  = "$.instanceId"
                  "targetClass.$" = "$.targetClass"
                }
              }
              ResultPath = "$.scaleResult"
              Catch = [
                {
                  ErrorEquals = ["States.ALL"]
                  ResultPath = "$.error"
                  Next = "CheckAutoScalingReaderStatus"
                }
              ]
              Next = "WaitForAutoScalingReader"
            },
            
            WaitForAutoScalingReader = {
              Type    = "Wait"
              Seconds = 60
              Next    = "CheckAutoScalingReaderStatus"
            },
            
            CheckAutoScalingReaderStatus = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Parameters = {
                FunctionName = aws_lambda_function.check_instance_status.arn
                Payload = {
                  "instanceIds.$" = "States.Array($.instanceId)"
                  "targetClass.$" = "$.targetClass"
                }
              }
              ResultPath = "$.statusCheckResult"
              Next       = "EvaluateAutoScalingReaderStatus"
            },
            
            EvaluateAutoScalingReaderStatus = {
              Type    = "Choice"
              Choices = [
                {
                  Variable      = "$.statusCheckResult.Payload.allAvailable"
                  BooleanEquals = true
                  Next          = "AutoScalingReaderComplete"
                },
                {
                  Variable      = "$.autoScalingReaderRetryCount"
                  NumericGreaterThanEquals = 5
                  Next          = "AutoScalingReaderStatusError"
                }
              ]
              Default = "IncrementAutoScalingReaderRetry"
            },
            
            IncrementAutoScalingReaderRetry = {
              Type = "Pass"
              Parameters = {
                "instanceId.$"  = "$.instanceId"
                "targetClass.$" = "$.targetClass"
                "autoScalingReaderRetryCount.$" = "States.MathAdd($.autoScalingReaderRetryCount, 1)"
              }
              Next = "WaitForAutoScalingReaderRetry"
            },
            
            WaitForAutoScalingReaderRetry = {
              Type    = "Wait"
              Seconds = 600
              Next    = "CheckAutoScalingReaderStatus"
            },
            
            AutoScalingReaderStatusError = {
              Type = "Fail"
              Error = "AutoScalingReaderStatusTimeout"
              Cause = "AutoScaling Reader instance did not become available after 5 retries (50 minutes)"
            },
            
            AutoScalingReaderComplete = {
              Type = "Pass"
              End  = true
            }
          }
        }
        ResultPath = "$.autoScalingResults"
        Next       = "PrepareFinalVerification"
      },
      
      # 最終確認: 全てのインスタンスがスケールダウンできているか確認
      PrepareFinalVerification = {
        Type = "Pass"
        Parameters = {
          "targetClass.$"                = "$.targetClass"
          "writerInstanceId.$"           = "$.writerInstanceId"
          "dedicatedReaderInstanceId.$"    = "$.dedicatedReaderInstanceId"
          "autoScalingReaderInstanceIds.$" = "$.autoScalingReaderInstanceIds"
          "clusterIdentifier.$"          = "$.clusterIdentifier"
          "executionName.$"              = "$.executionName"
          "startTime.$"                  = "$.startTime"
          "dedicatedReaderRetryCount.$"   = "$.dedicatedReaderRetryCount"
          "failoverRetryCount.$"         = "$.failoverRetryCount"
          "oldWriterRetryCount.$"         = "$.oldWriterRetryCount"
          "autoScalingReaderRetryCount.$" = "$.autoScalingReaderRetryCount"
          "overallRetryCount"             = 0
        }
        Next = "FinalVerification"
      },
      
      FinalVerification = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.check_instance_status.arn
          Payload = {
            "instanceIds.$" = "States.Array($.writerInstanceId, $.dedicatedReaderInstanceId)"
            "targetClass.$" = "$.targetClass"
          }
        }
        ResultPath = "$.finalVerificationResult"
        Next       = "FinalVerificationAutoScaling"
      },
      
      FinalVerificationAutoScaling = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.check_instance_status.arn
          Payload = {
            "instanceIds.$" = "$.autoScalingReaderInstanceIds"
            "targetClass.$" = "$.targetClass"
          }
        }
        ResultPath = "$.finalVerificationAutoScalingResult"
        Next       = "EvaluateFinalVerification"
      },
      
      EvaluateFinalVerification = {
        Type = "Pass"
        Parameters = {
          "targetClass.$"                = "$.targetClass"
          "writerInstanceId.$"           = "$.writerInstanceId"
          "dedicatedReaderInstanceId.$"    = "$.dedicatedReaderInstanceId"
          "autoScalingReaderInstanceIds.$" = "$.autoScalingReaderInstanceIds"
          "clusterIdentifier.$"          = "$.clusterIdentifier"
          "executionName.$"              = "$.executionName"
          "startTime.$"                  = "$.startTime"
          "dedicatedReaderRetryCount.$"   = "$.dedicatedReaderRetryCount"
          "failoverRetryCount.$"         = "$.failoverRetryCount"
          "oldWriterRetryCount.$"         = "$.oldWriterRetryCount"
          "autoScalingReaderRetryCount.$" = "$.autoScalingReaderRetryCount"
          "overallRetryCount.$"          = "$.overallRetryCount"
          "writerAndReaderAvailable.$"   = "$.finalVerificationResult.Payload.allAvailable"
          "autoScalingAvailable.$"       = "$.finalVerificationAutoScalingResult.Payload.allAvailable"
        }
        Next = "CheckFinalVerificationResult"
      },
      
      CheckFinalVerificationResult = {
        Type    = "Choice"
        Choices = [
          {
            And = [
              {
                Variable      = "$.writerAndReaderAvailable"
                BooleanEquals = true
              },
              {
                Variable      = "$.autoScalingAvailable"
                BooleanEquals = true
              }
            ]
            Next = "SendCompletionNotification"
          },
          {
            Variable      = "$.overallRetryCount"
            NumericGreaterThanEquals = 3
            Next          = "OverallRetryError"
          }
        ]
        Default = "IncrementOverallRetry"
      },
      
      IncrementOverallRetry = {
        Type = "Pass"
        Parameters = {
          "targetClass.$"                = "$.targetClass"
          "writerInstanceId.$"           = "$.writerInstanceId"
          "dedicatedReaderInstanceId.$"    = "$.dedicatedReaderInstanceId"
          "autoScalingReaderInstanceIds.$" = "$.autoScalingReaderInstanceIds"
          "clusterIdentifier.$"          = "$.clusterIdentifier"
          "executionName.$"              = "$.executionName"
          "startTime.$"                  = "$.startTime"
          "dedicatedReaderRetryCount"    = 0
          "failoverRetryCount"           = 0
          "oldWriterRetryCount"           = 0
          "autoScalingReaderRetryCount"  = 0
          "overallRetryCount.$"          = "States.MathAdd($.overallRetryCount, 1)"
        }
        Next = "WaitBeforeRetry"
      },
      
      WaitBeforeRetry = {
        Type    = "Wait"
        Seconds = 60
        Next    = "ScaleDedicatedReader"
      },
      
      OverallRetryError = {
        Type = "Fail"
        Error = "OverallRetryTimeout"
        Cause = "All instances did not scale down successfully after 3 overall retries"
      },
      
      SendCompletionNotification = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.send_notification.arn
          Payload = {
            "status"          = "completed"
            "executionName.$" = "$.executionName"
            "startTime.$"     = "$.startTime"
            "results.$"       = "$"
          }
        }
        End = true
      }
    }
  })

  tags = var.tags
}

# Step Functions実行ポリシーの更新
resource "aws_iam_policy" "stepfunctions_execution_extended" {
  name        = "${var.project_name}-${var.environment}-stepfunctions-extended-policy"
  description = "Extended policy for Step Functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.modify_instance.arn,
          aws_lambda_function.check_instance_status.arn,
          aws_lambda_function.send_notification.arn,
          aws_lambda_function.failover_cluster.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "stepfunctions_execution_extended" {
  role       = aws_iam_role.stepfunctions_execution.name
  policy_arn = aws_iam_policy.stepfunctions_execution_extended.arn
}