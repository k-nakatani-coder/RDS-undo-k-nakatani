#!/bin/bash
# RDSインスタンスを起動するスクリプト

CLUSTER_IDENTIFIER="k-nakatani-dev-cluster"

echo "=== RDSクラスターのインスタンス状態を確認 ==="
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=$CLUSTER_IDENTIFIER" \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]' \
  --output table

echo -e "\n=== 停止しているインスタンスを起動 ==="

# 停止しているインスタンスを取得
STOPPED_INSTANCES=$(aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=$CLUSTER_IDENTIFIER" \
  --query 'DBInstances[?DBInstanceStatus==`stopped`].DBInstanceIdentifier' \
  --output text)

if [ -z "$STOPPED_INSTANCES" ] || [ "$STOPPED_INSTANCES" == "None" ]; then
  echo "停止しているインスタンスはありません。"
else
  for instance_id in $STOPPED_INSTANCES; do
    echo "起動中: $instance_id"
    aws rds start-db-instance --db-instance-identifier $instance_id
    
    # 起動完了を待機
    echo "起動完了を待機中..."
    aws rds wait db-instance-available --db-instance-identifier $instance_id
    echo "$instance_id が起動しました。"
  done
fi

echo -e "\n=== 最終的なインスタンス状態 ==="
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=$CLUSTER_IDENTIFIER" \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]' \
  --output table

