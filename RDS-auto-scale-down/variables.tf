variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "k-nakatani"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_master_username" {
  description = "Database master username"
  type        = string
  default     = "postgres"
  sensitive   = true
}

variable "db_master_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "testdb"
}

variable "instance_class_writer" {
  description = "Instance class for writer"
  type        = string
  default     = "db.t4g.medium"  
}

variable "instance_class_reader" {
  description = "Instance class for reader"
  type        = string
  default     = "db.t4g.medium"
}

variable "autoscaling_min_capacity" {
  description = "Minimum number of autoscaling readers"
  type        = number
  default     = 1
}

variable "autoscaling_max_capacity" {
  description = "Maximum number of autoscaling readers"
  type        = number
  default     = 14
}

variable "scale_up_cpu_threshold" {
  description = "CPU threshold for scale up"
  type        = number
  default     = 70
}

variable "scale_down_cpu_threshold" {
  description = "CPU threshold for scale down"
  type        = number
  default     = 30
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {
    Owner = "nakatani-kousuke"
  }
}