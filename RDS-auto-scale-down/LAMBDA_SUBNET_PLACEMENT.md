# Lambda関数のサブネット配置（構成図作成用）

## 重要なポイント

**Lambda関数は特定のサブネットに「固定配置」されるわけではありません。**
- 複数のサブネットを指定すると、AWSが自動的に最適なAZに配置します
- 実行のたびに異なるAZに配置される可能性があります
- 高可用性のため、AWSが自動的に複数のAZに分散配置します

---

## VPC接続ありのLambda関数（5個）

以下のLambda関数は、**Lambdaサブネット（2つのAZ）**に配置されます：

| Lambda関数 | サブネット指定 | 配置先 |
|-----------|--------------|--------|
| `modify-instance` | `aws_subnet.lambda[*].id` | Lambda Subnet (AZ-1, AZ-2) |
| `check-instance-status` | `aws_subnet.lambda[*].id` | Lambda Subnet (AZ-1, AZ-2) |
| `failover-cluster` | `aws_subnet.lambda[*].id` | Lambda Subnet (AZ-1, AZ-2) |
| `get-cluster-instances` | `aws_subnet.lambda[*].id` | Lambda Subnet (AZ-1, AZ-2) |
| `schedule-scaling` | `aws_subnet.lambda[*].id` | Lambda Subnet (AZ-1, AZ-2) |

### サブネット詳細（2つのAZ構成）

| サブネット名 | AZ | CIDR | 用途 |
|------------|----|----|------|
| `k-nakatani-dev-lambda-subnet-1` | AZ-1 | `10.0.10.0/24` | Lambda関数とVPCエンドポイント |
| `k-nakatani-dev-lambda-subnet-2` | AZ-2 | `10.0.11.0/24` | Lambda関数とVPCエンドポイント |

**注意**: 
- Lambda関数は、この2つのサブネットの**いずれか**にAWSが自動的に配置します
- 構成図では「Lambda Subnet (AZ-1, AZ-2)」と記載するか、両方のサブネットに接続線を引く

---

## VPC接続なしのLambda関数（2個）

以下のLambda関数は、**VPC外（AWS管理ネットワーク）**で実行されます：

| Lambda関数 | VPC接続 | 配置先 |
|-----------|---------|--------|
| `update-schedule` | なし | AWS管理ネットワーク（VPC外） |
| `send-notification` | なし | AWS管理ネットワーク（VPC外） |

**構成図での表現**:
- VPCの外側に配置
- または「VPC接続なし」と明記

---

## 構成図での記載方法

### 推奨表現1: グループ化

```
[Lambda Subnet (AZ-1, AZ-2)]
  ├─ modify-instance
  ├─ check-instance-status
  ├─ failover-cluster
  ├─ get-cluster-instances
  └─ schedule-scaling
```

### 推奨表現2: サブネットごとに記載

```
[Lambda Subnet 1 (AZ-1)]
  └─ Lambda関数群（AWSが自動配置）

[Lambda Subnet 2 (AZ-2)]
  └─ Lambda関数群（AWSが自動配置）
```

### 推奨表現3: 接続線で表現

```
Lambda関数 → Lambda Subnet 1 (AZ-1)
Lambda関数 → Lambda Subnet 2 (AZ-2)
```

**注意**: 各Lambda関数が特定のサブネットに固定されているわけではないため、「複数のサブネットに接続可能」という表現が適切です。

---

## VPCエンドポイントの配置

VPCエンドポイントは、**Lambdaサブネットのすべて**に配置されます：

| VPCエンドポイント | 配置先サブネット |
|-----------------|----------------|
| RDS Endpoint | Lambda Subnet 1 (AZ-1), Lambda Subnet 2 (AZ-2) |
| CloudWatch Logs Endpoint | Lambda Subnet 1 (AZ-1), Lambda Subnet 2 (AZ-2) |
| Step Functions Endpoint | Lambda Subnet 1 (AZ-1), Lambda Subnet 2 (AZ-2) |

**重要**: VPCエンドポイントは、指定されたすべてのサブネットに**必ず配置**されます（Lambda関数とは異なります）。

---

## 構成図作成時の注意点

1. **Lambda関数の配置**:
   - 「Lambda Subnet (AZ-1, AZ-2)に配置可能」と記載
   - または「複数のAZに分散配置」と記載
   - 特定のサブネットに固定されているように見えないように注意

2. **VPCエンドポイントの配置**:
   - 「Lambda Subnet 1と2の両方に配置」と明記
   - 高可用性のため、両方のAZに配置されることを強調

3. **VPC接続なしのLambda関数**:
   - VPCの外側に配置
   - または「VPC接続なし」と明記

---

## 実際の配置例

### 実行時の配置パターン

**パターン1**: すべてのLambda関数がAZ-1に配置される場合
- Lambda Subnet 1 (AZ-1) にすべて配置
- VPCエンドポイントは両方のAZに配置されているため、問題なし

**パターン2**: Lambda関数が分散配置される場合
- 一部のLambda関数がAZ-1に配置
- 一部のLambda関数がAZ-2に配置
- VPCエンドポイントは両方のAZに配置されているため、問題なし

**パターン3**: すべてのLambda関数がAZ-2に配置される場合
- Lambda Subnet 2 (AZ-2) にすべて配置
- VPCエンドポイントは両方のAZに配置されているため、問題なし

**結論**: どのパターンでも、VPCエンドポイントが両方のAZに配置されているため、問題なく動作します。

