

# Aurora Cluster
resource "aws_rds_cluster" "main" {
  cluster_identifier              = "${var.project_name}-${var.environment}-cluster"
  engine                         = "aurora-postgresql"
  engine_version                 = "16.2"
  database_name                  = var.db_name
  master_username                = var.db_master_username
  master_password                = var.db_master_password
  
  # デフォルトのパラメータグループを使用
  # db_cluster_parameter_group_name = 省略（デフォルト使用）
  
  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  
  # 検証用の最小限のバックアップ設定
  backup_retention_period         = 1  # 検証なので1日で十分
  preferred_backup_window         = "03:00-04:00"
  preferred_maintenance_window    = "mon:04:00-mon:05:00"
  
  # High Availability settings
  availability_zones              = data.aws_availability_zones.available.names
  
  # ログは検証では不要
    enabled_cloudwatch_logs_exports = ["postgresql"]
  
  # 検証環境なので削除しやすくする
  deletion_protection             = false
  skip_final_snapshot            = true
  
  # 暗号化も検証では省略可能（コスト削減）
  storage_encrypted              = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-aurora-cluster"
  })
}

# Writer Instance
resource "aws_rds_cluster_instance" "writer" {
  identifier                   = "${var.project_name}-${var.environment}-writer"
  cluster_identifier           = aws_rds_cluster.main.id
  instance_class              = var.instance_class_writer
  engine                      = aws_rds_cluster.main.engine
  engine_version              = aws_rds_cluster.main.engine_version
  
  # デフォルトのパラメータグループを使用
  # db_parameter_group_name     = 省略（デフォルト使用）
  
  # Performance Insightsも検証では不要
  performance_insights_enabled = false
  
  # 基本的なモニタリングのみ（0 = 無効、検証には十分）
  monitoring_interval         = 0
  
  auto_minor_version_upgrade  = false
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-writer"
    Role = "writer"
  })
}

# Dedicated Reader Instance
resource "aws_rds_cluster_instance" "dedicated_reader" {
  identifier                   = "${var.project_name}-${var.environment}-reader-dedicated"
  cluster_identifier           = aws_rds_cluster.main.id
  instance_class              = var.instance_class_reader
  engine                      = aws_rds_cluster.main.engine
  engine_version              = aws_rds_cluster.main.engine_version
  
  performance_insights_enabled = false
  monitoring_interval         = 0
  
  auto_minor_version_upgrade  = false
  promotion_tier              = 1  # フェイルオーバー優先度
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-reader-dedicated"
    Role = "dedicated-reader"
  })
}

# Initial AutoScaling Readers (1台作成してテスト時間を短縮)
resource "aws_rds_cluster_instance" "autoscaling_reader_initial" {
  count                        = 1  # テスト用に1台のみ
  identifier                   = "${var.project_name}-${var.environment}-reader-as-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.main.id
  instance_class              = var.instance_class_reader
  engine                      = aws_rds_cluster.main.engine
  engine_version              = aws_rds_cluster.main.engine_version
  
  performance_insights_enabled = false
  monitoring_interval         = 0
  
  auto_minor_version_upgrade  = false
  promotion_tier              = 2  # 低い優先度
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-reader-as-${count.index + 1}"
    Role = "autoscaling-reader"
  })
}