# AutoScaling Target
resource "aws_appautoscaling_target" "aurora_replica_count" {
  service_namespace  = "rds"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  resource_id        = "cluster:${aws_rds_cluster.main.cluster_identifier}"
  min_capacity       = var.autoscaling_min_capacity
  max_capacity       = var.autoscaling_max_capacity

  depends_on = [
    aws_rds_cluster_instance.writer,
    aws_rds_cluster_instance.dedicated_reader,
    aws_rds_cluster_instance.autoscaling_reader_initial
  ]
}

# Target Tracking Scaling Policy - CPU Utilization
resource "aws_appautoscaling_policy" "aurora_cpu_scaling" {
  name               = "${var.project_name}-${var.environment}-aurora-cpu-scaling"
  service_namespace  = aws_appautoscaling_target.aurora_replica_count.service_namespace
  resource_id        = aws_appautoscaling_target.aurora_replica_count.resource_id
  scalable_dimension = aws_appautoscaling_target.aurora_replica_count.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }

    target_value       = 60.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

# Scheduled Scaling - Scale Up for events (example: morning peak)
resource "aws_appautoscaling_scheduled_action" "scale_up_morning" {
  name               = "${var.project_name}-${var.environment}-scale-up-morning"
  service_namespace  = aws_appautoscaling_target.aurora_replica_count.service_namespace
  resource_id        = aws_appautoscaling_target.aurora_replica_count.resource_id
  scalable_dimension = aws_appautoscaling_target.aurora_replica_count.scalable_dimension
  schedule           = "cron(0 8 ? * MON-FRI *)"  # 8:00 AM weekdays (JST would be 23:00 UTC previous day)
  timezone          = "Asia/Tokyo"

  scalable_target_action {
    min_capacity = 3
    max_capacity = 14
  }
}

# Scheduled Scaling - Scale Down for off-peak
resource "aws_appautoscaling_scheduled_action" "scale_down_night" {
  name               = "${var.project_name}-${var.environment}-scale-down-night"
  service_namespace  = aws_appautoscaling_target.aurora_replica_count.service_namespace
  resource_id        = aws_appautoscaling_target.aurora_replica_count.resource_id
  scalable_dimension = aws_appautoscaling_target.aurora_replica_count.scalable_dimension
  schedule           = "cron(0 22 ? * * *)"  # 10:00 PM daily (JST)
  timezone          = "Asia/Tokyo"

  scalable_target_action {
    min_capacity = 1
    max_capacity = 5
  }
}

# Scheduled Scaling - Scale Up for specific event
resource "aws_appautoscaling_scheduled_action" "scale_up_event" {
  name               = "${var.project_name}-${var.environment}-scale-up-event"
  service_namespace  = aws_appautoscaling_target.aurora_replica_count.service_namespace
  resource_id        = aws_appautoscaling_target.aurora_replica_count.resource_id
  scalable_dimension = aws_appautoscaling_target.aurora_replica_count.scalable_dimension
  schedule           = "cron(0 12 ? * SAT *)"  # Saturday noon for special events
  timezone          = "Asia/Tokyo"

  scalable_target_action {
    min_capacity = 5
    max_capacity = 14
  }
}