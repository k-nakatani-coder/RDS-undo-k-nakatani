#!/bin/bash
# Auroraスケーリング設定スクリプト
# 使用方法: ./set_scaling_config.sh <cluster-identifier> <target-class>
# 例: ./set_scaling_config.sh k-nakatani-dev-cluster db.t4g.medium

set -e

CLUSTER_IDENTIFIER=$1
TARGET_CLASS=$2

if [ -z "$CLUSTER_IDENTIFIER" ] || [ -z "$TARGET_CLASS" ]; then
    echo "使用方法: $0 <cluster-identifier> <target-class>"
    echo "例: $0 k-nakatani-dev-cluster db.t4g.medium"
    exit 1
fi

PARAMETER_NAME="/aurora-scaling/${CLUSTER_IDENTIFIER}/targetClass"

echo "設定を保存しています..."
aws ssm put-parameter \
    --name "$PARAMETER_NAME" \
    --value "$TARGET_CLASS" \
    --type "String" \
    --overwrite \
    --description "Target instance class for Aurora scaling" \
    --region ap-northeast-1

echo "設定が保存されました:"
echo "  パラメータ名: $PARAMETER_NAME"
echo "  ターゲットクラス: $TARGET_CLASS"
echo ""
echo "24:00 JST (15:00 UTC) に自動的にスケーリングが実行されます。"

