# 構成図作成用リファレンス

手動で構成図を作成する際に必要な情報をまとめています。

## 命名規則

すべてのリソース名は以下の形式で命名されています：

```
{project_name}-{environment}-{resource_type}
```

**例**:
- `k-nakatani-dev-cluster` (Aurora Cluster)
- `k-nakatani-dev-writer` (Writer Instance)
- `k-nakatani-dev-schedule-scaling` (EventBridge Rule)

---

## AWSサービスとリソース一覧

### 1. Amazon RDS Aurora

#### クラスター
- **リソース名**: `k-nakatani-dev-cluster`
- **エンジン**: `aurora-postgresql`
- **バージョン**: `16.2`
- **VPC**: `10.0.0.0/16`内のプライベートサブネット
- **サブネットグループ**: `k-nakatani-dev-aurora-subnet-group` (3つのAZに配置)

#### インスタンス

| インスタンス名 | タイプ | 役割 | インスタンスクラス |
|--------------|--------|------|-------------------|
| `k-nakatani-dev-writer` | Writer | 読み書き | `db.t4g.medium` |
| `k-nakatani-dev-reader-dedicated` | Reader | 専用リーダー | `db.t4g.medium` |
| `k-nakatani-dev-reader-as-1` | Reader | AutoScalingリーダー | `db.t4g.medium` |

**タグ**:
- Writer: `Role: writer`
- Dedicated Reader: `Role: dedicated-reader`
- AutoScaling Reader: `Role: autoscaling-reader`

---

### 2. AWS Lambda関数（7個）

| 関数名 | リソース名 | VPC接続 | タイムアウト | IAMロール |
|--------|-----------|---------|-------------|-----------|
| `update-schedule` | `k-nakatani-dev-update-schedule` | なし | 30秒 | `lambda-scaling-role` |
| `schedule-scaling` | `k-nakatani-dev-schedule-scaling` | あり | 900秒 | `lambda-scaling-role` |
| `modify-instance` | `k-nakatani-dev-modify-instance` | あり | 60秒 | `lambda-scaling-role` |
| `check-instance-status` | `k-nakatani-dev-check-instance-status` | あり | 30秒 | `lambda-scaling-role` |
| `failover-cluster` | `k-nakatani-dev-failover-cluster` | あり | 60秒 | `lambda-scaling-role` |
| `get-cluster-instances` | `k-nakatani-dev-get-cluster-instances` | あり | 60秒 | `lambda-scaling-role` |
| `send-notification` | `k-nakatani-dev-send-notification` | なし | 30秒 | `lambda-notification-role` |

**VPC接続ありのLambda関数**:
- サブネット: `k-nakatani-dev-lambda-subnet-1`, `-2`, `-3` (3つのAZ)
- セキュリティグループ: `k-nakatani-dev-lambda-sg`

---

### 3. AWS Step Functions

- **ステートマシン名**: `k-nakatani-dev-aurora-scaling`
- **IAMロール**: `k-nakatani-dev-stepfunctions-execution-role`
- **実行時間**: 最大数時間（リトライを含む）

---

### 4. Amazon EventBridge

- **ルール名**: `k-nakatani-dev-schedule-scaling`
- **デフォルト状態**: `DISABLED`（無効）
- **ターゲット**: `schedule-scaling` Lambda関数
- **入力パラメータ**: 
  ```json
  {
    "clusterIdentifier": "k-nakatani-dev-cluster",
    "targetClass": "db.t4g.medium"
  }
  ```

---

### 5. Amazon SNS

- **トピック名**: `k-nakatani-dev-aurora-scaling-alerts`
- **用途**: 処理完了/失敗の通知

---

### 6. Application Auto Scaling

- **ターゲット**: `cluster:k-nakatani-dev-cluster`
- **最小容量**: 1台
- **最大容量**: 14台
- **スケーリングポリシー**: CPU使用率ベース（Target: 60%）

---

## ネットワーク構成

### VPC

- **CIDR**: `10.0.0.0/16`
- **リソース名**: `k-nakatani-dev-vpc`
- **DNS設定**: 有効

### サブネット構成

#### Public Subnets（パブリックサブネット）
- **定義**: なし（このシステムでは使用していない）
- **理由**: VPCエンドポイントを使用するため、インターネットゲートウェイやNAT Gatewayは不要

#### Private Subnets - Aurora（プライベートサブネット - Aurora用）
- **リソース名**: `k-nakatani-dev-aurora-subnet-1`, `-2`, `-3`
- **数**: 3つ（AZ-1, AZ-2, AZ-3）
- **CIDR**: `10.0.0.0/24`, `10.0.1.0/24`, `10.0.2.0/24`（推定）
- **ルートテーブル**: `k-nakatani-dev-private-rt`

#### Private Subnets - Lambda（プライベートサブネット - Lambda用）
- **リソース名**: `k-nakatani-dev-lambda-subnet-1`, `-2`, `-3`
- **数**: 3つ（AZ-1, AZ-2, AZ-3）
- **CIDR**: `10.0.10.0/24`, `10.0.11.0/24`, `10.0.12.0/24`（推定）
- **ルートテーブル**: `k-nakatani-dev-private-rt`

### ゲートウェイ

- **Internet Gateway**: 定義されていない（VPCエンドポイントを使用するため不要）
- **NAT Gateway**: 定義されていない（VPCエンドポイントを使用するため不要）

**重要**: このシステムでは、すべてのAWS APIアクセスをVPCエンドポイント経由で行うため、インターネットゲートウェイやNAT Gatewayは不要です。これにより、コスト削減とセキュリティ向上を実現しています。

### VPCエンドポイント

| エンドポイント名 | サービス名 | タイプ | サブネット | セキュリティグループ |
|----------------|-----------|--------|-----------|-------------------|
| `k-nakatani-dev-rds-endpoint` | `com.amazonaws.ap-northeast-1.rds` | Interface | Lambda Subnets (3つ) | `k-nakatani-dev-vpc-endpoints-sg` |
| `k-nakatani-dev-logs-endpoint` | `com.amazonaws.ap-northeast-1.logs` | Interface | Lambda Subnets (3つ) | `k-nakatani-dev-vpc-endpoints-sg` |
| `k-nakatani-dev-states-endpoint` | `com.amazonaws.ap-northeast-1.states` | Interface | Lambda Subnets (3つ) | `k-nakatani-dev-vpc-endpoints-sg` |

**特徴**:
- すべてInterfaceタイプ
- Private DNS有効
- Lambdaサブネット（3つのAZ）に配置

### セキュリティグループ

#### Aurora用セキュリティグループ
- **リソース名**: `k-nakatani-dev-aurora-sg`
- **インバウンド**: 
  - PostgreSQL (5432) from VPC CIDR (`10.0.0.0/16`)
- **アウトバウンド**: すべて許可

#### Lambda用セキュリティグループ
- **リソース名**: `k-nakatani-dev-lambda-sg`
- **インバウンド**: なし
- **アウトバウンド**: すべて許可

#### VPCエンドポイント用セキュリティグループ
- **リソース名**: `k-nakatani-dev-vpc-endpoints-sg`
- **インバウンド**: 
  - HTTPS (443) from VPC CIDR (`10.0.0.0/16`)
- **アウトバウンド**: なし

---

## IAMロールとポリシー

### Lambda用IAMロール

#### `lambda-scaling-role`
- **リソース名**: `k-nakatani-dev-lambda-scaling-role`
- **使用Lambda関数**: 
  - `update-schedule`
  - `schedule-scaling`
  - `modify-instance`
  - `check-instance-status`
  - `failover-cluster`
  - `get-cluster-instances`

**主な権限**:
- RDS操作（Describe, Modify, Failover）
- Step Functions実行
- EventBridge操作（PutRule, PutTargets）
- CloudWatch Logs
- VPCアクセス

#### `lambda-notification-role`
- **リソース名**: `k-nakatani-dev-lambda-notification-role`
- **使用Lambda関数**: 
  - `send-notification`

**主な権限**:
- SNS発行
- CloudWatch Logs

### Step Functions用IAMロール

- **リソース名**: `k-nakatani-dev-stepfunctions-execution-role`
- **主な権限**:
  - Lambda関数の呼び出し
  - CloudWatch Logs

---

## 接続関係（データフロー）

### 1. スケジュール設定フロー

```
ユーザー
  ↓ (直接実行)
update-schedule Lambda
  ↓ (EventBridge API)
EventBridge Rule
  ↓ (ルール更新・有効化)
EventBridge Rule (ENABLED)
```

### 2. スケール実行フロー

```
EventBridge Rule (スケジュール実行)
  ↓ (イベント)
schedule-scaling Lambda
  ↓ (RDS API via VPC Endpoint)
Aurora Cluster
  ↓ (インスタンス情報)
schedule-scaling Lambda
  ↓ (JSON作成)
schedule-scaling Lambda
  ↓ (Step Functions API via VPC Endpoint)
Step Functions State Machine
```

### 3. Step Functions実行フロー

```
Step Functions State Machine
  ├─→ modify-instance Lambda (RDS API via VPC Endpoint) → Aurora Instances
  ├─→ check-instance-status Lambda (RDS API via VPC Endpoint) → Aurora Instances
  ├─→ failover-cluster Lambda (RDS API via VPC Endpoint) → Aurora Cluster
  ├─→ get-cluster-instances Lambda (RDS API via VPC Endpoint) → Aurora Cluster
  └─→ send-notification Lambda (SNS API) → SNS Topic
```

### 4. ネットワーク接続

#### Lambda関数（VPC接続あり）の接続先
- **RDS API**: VPCエンドポイント経由（`k-nakatani-dev-rds-endpoint`）
- **Step Functions API**: VPCエンドポイント経由（`k-nakatani-dev-states-endpoint`）
- **CloudWatch Logs**: VPCエンドポイント経由（`k-nakatani-dev-logs-endpoint`）

#### Lambda関数（VPC接続なし）の接続先
- **EventBridge API**: インターネット経由（`update-schedule`のみ）
  - 注意: VPC接続なしのため、Lambda関数はインターネット経由でEventBridge APIにアクセス
- **SNS API**: インターネット経由（`send-notification`のみ）
  - 注意: VPC接続なしのため、Lambda関数はインターネット経由でSNS APIにアクセス

**重要**: VPC接続ありのLambda関数はすべてVPCエンドポイント経由でAWS APIにアクセスするため、NAT Gatewayは不要です。

---

## リソース配置図（レイヤー別）

### レイヤー1: ユーザー/外部
- ユーザー（手動実行）

### レイヤー2: スケジュール管理
- EventBridge Rule
- `update-schedule` Lambda

### レイヤー3: 実行トリガー
- `schedule-scaling` Lambda

### レイヤー4: ワークフロー管理
- Step Functions State Machine

### レイヤー5: 処理実行
- `modify-instance` Lambda
- `check-instance-status` Lambda
- `failover-cluster` Lambda
- `get-cluster-instances` Lambda

### レイヤー6: データストア
- Aurora Cluster
  - Writer Instance
  - Dedicated Reader Instance
  - AutoScaling Reader Instances

### レイヤー7: 通知
- `send-notification` Lambda
- SNS Topic

### レイヤー8: インフラストラクチャ
- VPC
- サブネット（Aurora, Lambda - すべてプライベート）
- VPCエンドポイント（RDS, Logs, States）
- セキュリティグループ
- IAMロール
- **注意**: Public Subnets、Internet Gateway、NAT Gatewayは使用していない

---

## 構成図作成時の注意点

### 1. 接続線の種類
- **実線**: 直接的なAPI呼び出し
- **点線**: スケジュール実行やイベント駆動
- **矢印**: データフローの方向

### 2. 色分けの推奨
- **青**: AWS管理サービス（EventBridge, Step Functions, SNS）
- **緑**: Lambda関数
- **オレンジ**: RDS Aurora
- **グレー**: ネットワーク（VPC, サブネット, エンドポイント）
- **紫**: IAMロール

### 3. グループ化
- **ユーザー操作**: ユーザー、`update-schedule`
- **スケジュール実行**: EventBridge、`schedule-scaling`
- **ワークフロー**: Step Functions、処理用Lambda関数
- **データストア**: Aurora Cluster、インスタンス
- **通知**: SNS、`send-notification`
- **ネットワーク**: VPC、サブネット、エンドポイント

### 4. ラベルに含める情報
- **Lambda関数**: 関数名、VPC接続の有無、タイムアウト
- **RDS**: クラスター名、インスタンス名、インスタンスクラス
- **VPCエンドポイント**: サービス名、タイプ
- **セキュリティグループ**: リソース名、主要なルール

---

## 主要な設定値

### タイムアウト設定
- `schedule-scaling`: 900秒（15分）
- `modify-instance`: 60秒
- `check-instance-status`: 30秒
- `failover-cluster`: 60秒
- `get-cluster-instances`: 60秒
- `update-schedule`: 30秒
- `send-notification`: 30秒

### リトライ設定
- **個別インスタンス**: 最大5回、各10分待機
- **全体リトライ**: 最大3回、各60秒待機

### リージョン
- **AWSリージョン**: `ap-northeast-1` (東京)

---

## 補足情報

### 環境変数

#### `schedule-scaling` Lambda
- `CLUSTER_IDENTIFIER`: `k-nakatani-dev-cluster`
- `STEP_FUNCTION_ARN`: Step FunctionsのARN
- `EVENTBRIDGE_RULE_NAME`: `k-nakatani-dev-schedule-scaling`

#### `update-schedule` Lambda
- `CLUSTER_IDENTIFIER`: `k-nakatani-dev-cluster`
- `EVENTBRIDGE_RULE_NAME`: `k-nakatani-dev-schedule-scaling`
- `PROJECT_NAME`: `k-nakatani`
- `ENVIRONMENT`: `dev`

#### `send-notification` Lambda
- `SNS_TOPIC_ARN`: SNSトピックのARN

---

## 構成図の種類

### 1. システム全体構成図
- すべてのAWSサービスとリソース
- サービス間の接続関係
- データフロー

### 2. ネットワーク構成図
- VPC、サブネット、ルートテーブル
- VPCエンドポイント（RDS, Logs, States）
- セキュリティグループ
- **注意**: NAT Gatewayは使用していない（VPCエンドポイント経由のため）

### 3. 実行フロー図
- スケジュール設定から実行完了までの流れ
- Step Functionsのステート遷移
- リトライロジック

### 4. セキュリティ構成図
- IAMロールとポリシー
- セキュリティグループルール
- VPCエンドポイントのアクセス制御

---

このドキュメントを参考に、目的に応じた構成図を作成してください。

