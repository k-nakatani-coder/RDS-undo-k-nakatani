# テスト方法ガイド

## テスト方法の選択

テストには以下の3つの方法があります。用途に応じて選択してください。

### 方法1: schedule-scaling Lambda関数を実行（推奨）⭐

**最も簡単で推奨される方法**  
クラスターから現在のインスタンス情報を自動取得してStep Functionsを実行します。

#### AWSコンソールから実行

1. AWSコンソールで **Lambda** → **関数** を開く
2. `k-nakatani-dev-schedule-scaling` 関数を選択
3. **テスト** タブを開く
4. **新しいイベント** を選択
5. イベント名を入力（例: `test-scaling`）
6. 以下のJSONを入力：
   ```json
   {
     "clusterIdentifier": "k-nakatani-dev-cluster",
     "targetClass": "db.t4g.medium"
   }
   ```
7. **保存** → **テスト** をクリック

#### AWS CLIから実行

```bash
aws lambda invoke \
  --function-name k-nakatani-dev-schedule-scaling \
  --payload '{
    "clusterIdentifier": "k-nakatani-dev-cluster",
    "targetClass": "db.t4g.medium"
  }' \
  response.json

# レスポンスを確認
cat response.json
```

#### 実行結果の確認

- Lambda関数の実行ログを確認（CloudWatch Logs）
- Step Functionsの実行履歴を確認
- RDSコンソールでインスタンスタイプが変更されているか確認

---

### 方法2: Step Functionsを直接実行

インスタンスIDを手動で指定する必要があります。現在のインスタンス情報を事前に取得してください。

#### 現在のインスタンス情報を取得

```bash
# Terraformの出力から取得
terraform output test_input_json

# または、RDSコンソールから手動で確認
```

#### AWSコンソールから実行

1. AWSコンソールで **Step Functions** → **ステートマシン** を開く
2. `k-nakatani-dev-aurora-scaling` を選択
3. **実行を開始** をクリック
4. 実行名を入力（例: `test-execution-20250118`）
5. 以下のJSONを入力：
   ```json
   {
     "targetClass": "db.t4g.medium",
     "clusterIdentifier": "k-nakatani-dev-cluster",
     "writerInstanceId": "k-nakatani-dev-writer",
     "dedicatedReaderInstanceId": "k-nakatani-dev-reader-dedicated",
     "autoScalingReaderInstanceIds": ["k-nakatani-dev-reader-as-1"]
   }
   ```
6. **実行を開始** をクリック

#### AWS CLIから実行

```bash
aws stepfunctions start-execution \
  --state-machine-arn $(terraform output -raw step_function_arn) \
  --name "test-execution-$(date +%Y%m%d-%H%M%S)" \
  --input '{
    "targetClass": "db.t4g.medium",
    "clusterIdentifier": "k-nakatani-dev-cluster",
    "writerInstanceId": "k-nakatani-dev-writer",
    "dedicatedReaderInstanceId": "k-nakatani-dev-reader-dedicated",
    "autoScalingReaderInstanceIds": ["k-nakatani-dev-reader-as-1"]
  }'
```

---

### 方法3: 個別のLambda関数をテスト

各Lambda関数を個別にテストする場合。

#### get-cluster-instances のテスト

```bash
aws lambda invoke \
  --function-name k-nakatani-dev-get-cluster-instances \
  --payload '{
    "clusterIdentifier": "k-nakatani-dev-cluster"
  }' \
  response.json

cat response.json
```

#### modify-instance のテスト

```bash
aws lambda invoke \
  --function-name k-nakatani-dev-modify-instance \
  --payload '{
    "instanceId": "k-nakatani-dev-reader-as-1",
    "targetClass": "db.t4g.medium"
  }' \
  response.json

cat response.json
```

#### check-instance-status のテスト

```bash
aws lambda invoke \
  --function-name k-nakatani-dev-check-instance-status \
  --payload '{
    "instanceIds": ["k-nakatani-dev-reader-as-1"]
  }' \
  response.json

cat response.json
```

---

## テストの流れ（推奨）

### 1. 事前確認

```bash
# 現在のインスタンス情報を確認
terraform output test_input_json

# または、RDSコンソールで確認
# - Writerインスタンスのタイプ
# - Dedicated Readerインスタンスのタイプ
# - AutoScaling Readerインスタンスのタイプと台数
```

### 2. schedule-scaling Lambda関数を実行

```bash
aws lambda invoke \
  --function-name k-nakatani-dev-schedule-scaling \
  --payload '{
    "clusterIdentifier": "k-nakatani-dev-cluster",
    "targetClass": "db.t4g.medium"
  }' \
  response.json

# レスポンスを確認
cat response.json | jq
```

### 3. Step Functionsの実行を確認

```bash
# Step FunctionsコンソールのURLを取得
terraform output step_function_console_url

# または、AWS CLIで実行履歴を確認
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw step_function_arn) \
  --max-results 5
```

### 4. 実行状況の監視

- **Step Functionsコンソール**: 各ステップの実行状況を確認
- **CloudWatch Logs**: Lambda関数のログを確認
- **RDSコンソール**: インスタンスのステータスを確認

### 5. 完了確認

- Step Functionsの実行が成功しているか確認
- RDSコンソールでインスタンスタイプが変更されているか確認
- SNS通知が送信されているか確認（設定している場合）

---

## トラブルシューティング

### Lambda関数の実行エラー

1. **CloudWatch Logsを確認**
   ```bash
   aws logs tail /aws/lambda/k-nakatani-dev-schedule-scaling --follow
   ```

2. **IAM権限を確認**
   - Lambda関数の実行ロールに必要な権限があるか確認

3. **VPC接続を確認**
   - VPC内のLambda関数がRDSにアクセスできるか確認
   - セキュリティグループの設定を確認

### Step Functionsの実行エラー

1. **実行履歴を確認**
   - Step Functionsコンソールでエラーの詳細を確認

2. **Lambda関数のログを確認**
   - 各Lambda関数のCloudWatch Logsを確認

3. **リトライロジックを確認**
   - インスタンスが`available`状態になるまで時間がかかる場合がある
   - リトライが正常に動作しているか確認

---

## テスト用の便利なコマンド

### 現在のインスタンス情報を取得

```bash
# Terraformの出力から
terraform output test_input_json | jq

# または、get-cluster-instances Lambda関数を使用
aws lambda invoke \
  --function-name k-nakatani-dev-get-cluster-instances \
  --payload '{"clusterIdentifier":"k-nakatani-dev-cluster"}' \
  response.json && cat response.json | jq
```

### Step Functionsの実行履歴を確認

```bash
# 最新の5件の実行履歴
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw step_function_arn) \
  --max-results 5 \
  --query 'executions[*].[executionArn,name,status,startDate]' \
  --output table
```

### Lambda関数のログを確認

```bash
# schedule-scaling Lambda関数のログ
aws logs tail /aws/lambda/k-nakatani-dev-schedule-scaling --follow

# modify-instance Lambda関数のログ
aws logs tail /aws/lambda/k-nakatani-dev-modify-instance --follow

# check-instance-status Lambda関数のログ
aws logs tail /aws/lambda/k-nakatani-dev-check-instance-status --follow
```

---

## 注意事項

- **テスト環境での実行**: 本番環境で実行する前に、必ずテスト環境で動作確認してください
- **インスタンスタイプの変更**: インスタンスタイプの変更には数分かかります
- **リトライロジック**: インスタンスが`available`状態になるまで最大25分（5分×5回）待機します
- **コスト**: インスタンスタイプの変更中も課金が発生します

