# スケジュール実行の設定と実行方法

## 概要

Auroraクラスターのスケールダウンを自動実行するための設定方法です。
実行時間を柔軟に指定できます。

## 設定方法

### 方法1: スケジュール更新Lambda関数を使用（推奨）

実行時間、ターゲットクラス、クラスター識別子を一度に設定できます。

#### AWSコンソールから実行

1. AWSコンソールで **Lambda** → **関数** を開く
2. `k-nakatani-dev-update-schedule` 関数を選択
3. **テスト** タブを開く
4. **新しいイベント** を選択
5. 以下のJSONを入力：
   ```json
   {
     "clusterIdentifier": "k-nakatani-dev-cluster",
     "targetClass": "db.t4g.medium",
     "scheduleTime": "24:00"
   }
   ```
   - `scheduleTime`: 実行時間（JST形式: "HH:MM" または cron式）
     - 例: `"24:00"` (24:00 JST)
     - 例: `"15:30"` (15:30 JST)
     - 例: `"cron(0 15 * * ? *)"` (cron式、UTC時間)
6. **テスト** をクリック

#### AWS CLIから実行

```bash
aws lambda invoke \
  --function-name k-nakatani-dev-update-schedule \
  --payload '{
    "clusterIdentifier": "k-nakatani-dev-cluster",
    "targetClass": "db.t4g.medium",
    "scheduleTime": "24:00"
  }' \
  response.json
```

### 方法2: Lambda関数を直接実行（即座に実行、スケジュール更新なし）

1. AWSコンソールで **Lambda** → **関数** を開く
2. `k-nakatani-dev-schedule-scaling` 関数を選択
3. **テスト** タブを開く
4. **新しいイベント** を選択
5. 以下のJSONを入力：
   ```json
   {
     "clusterIdentifier": "k-nakatani-dev-cluster",
     "targetClass": "db.t4g.medium"
   }
   ```
6. **テスト** をクリック

### 方法3: AWS CLIから実行

```bash
aws lambda invoke \
  --function-name k-nakatani-dev-schedule-scaling \
  --payload '{"clusterIdentifier":"k-nakatani-dev-cluster","targetClass":"db.t4g.medium"}' \
  response.json
```

### 方法4: Step Functionsを直接実行（コンソールから）

1. AWSコンソールで **Step Functions** → **ステートマシン** を開く
2. `k-nakatani-dev-aurora-scaling` を選択
3. **実行を開始** をクリック
4. 以下のJSONを入力（インスタンス情報は自動取得されません）：
   ```json
   {
     "targetClass": "db.t4g.medium",
     "clusterIdentifier": "k-nakatani-dev-cluster",
     "writerInstanceId": "k-nakatani-dev-writer",
     "dedicatedReaderInstanceId": "k-nakatani-dev-reader-dedicated",
     "autoScalingReaderInstanceIds": ["k-nakatani-dev-reader-as-1"]
   }
   ```

## 処理フロー

1. **設定**: `update-schedule` Lambda関数で実行時間、ターゲットクラス、クラスター識別子を設定
   - EventBridgeルールのスケジュール式が更新される
   - ターゲットの入力パラメータも更新される
2. **スケジュール実行**: 指定した時間に自動実行
3. **動的取得**: `schedule-scaling` Lambda関数がクラスターから現在のインスタンス情報を取得
4. **JSON作成**: 取得した情報からStep Functions用のJSONを作成
5. **実行**: Step Functionsを実行してスケールダウン処理を開始

## 実行時間の指定方法

### JST形式（推奨）
- 形式: `"HH:MM"` (24時間形式)
- 例: `"24:00"` → 24:00 JSTに実行
- 例: `"15:30"` → 15:30 JSTに実行
- 自動的にUTC時間に変換されます（JST = UTC + 9時間）

### Cron式
- 形式: `"cron(分 時 * * ? *)"` (UTC時間)
- 例: `"cron(0 15 * * ? *)"` → 15:00 UTC（24:00 JST）に実行
- 例: `"cron(30 6 * * ? *)"` → 06:30 UTC（15:30 JST）に実行

## 注意事項

- 実行時間はJST形式で指定できます（自動的にUTCに変換されます）
- EventBridgeルールのスケジュール式が更新されると、次回のスケジュール実行から新しい時間が適用されます
- Lambda関数を直接実行する場合は、その時点でのインスタンス情報が取得されます
- Step Functionsを直接実行する場合は、インスタンスIDを手動で指定する必要があります

