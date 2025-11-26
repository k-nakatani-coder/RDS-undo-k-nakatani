# Project configuration
project_name = "k-nakatani"
environment  = "dev"
region       = "ap-northeast-1"

# Network configuration
vpc_cidr = "10.0.0.0/16"

# Database configuration
db_master_username = "knakatani"
db_master_password = "Cloudpack1008"  # Change this!
db_name           = "knakatanidevundotusindb"

# Instance configuration
instance_class_writer = "db.t4g.medium"
instance_class_reader = "db.t4g.medium"

# AutoScaling configuration
autoscaling_min_capacity = 1  # テスト用に1台のみ
autoscaling_max_capacity = 14
scale_up_cpu_threshold   = 70
scale_down_cpu_threshold = 30

# Backup configuration
backup_retention_period = 7

# Tags
tags = {
  Owner       = "k-nakatani"
}

