# Lambda関数一覧と役割

このシステムには全部で**7個のLambda関数**があります。

## 1. `update-schedule` Lambda関数

**役割**: EventBridgeルールのスケジュール式を更新する

**主な処理**:
- ユーザーが指定した実行時間（`scheduleTime`）を受け取る
- 実行時間の形式を変換:
  - `"HH:MM"` (JST) → 毎日同じ時間に実行するcron式
  - `"YYYY-MM-DD HH:MM"` (JST) → 特定の日時に1回だけ実行するcron式
  - `cron(...)` → そのまま使用
- EventBridgeルールのスケジュール式と入力パラメータを更新
- ルールを有効化（`ENABLED`）
- 特定の日時を指定した場合、実行後にルールを無効化する設定を保存

**呼び出し元**: ユーザー（直接実行またはAWS CLI/コンソール）

**VPC接続**: なし（EventBridge APIのみ使用）

**タイムアウト**: 30秒

---

## 2. `schedule-scaling` Lambda関数

**役割**: スケール実行をトリガーし、Step Functionsを実行する

**主な処理**:
1. EventBridgeルールから実行される（指定時間に自動実行）
2. 直接RDS APIを呼び出してクラスターから現在のインスタンス情報を取得
   - Writerインスタンス
   - Dedicated Readerインスタンス
   - AutoScaling Readerインスタンス（複数）
3. Step Functionsの入力JSONを作成
4. Step Functionsを実行開始
5. 特定の日時を指定した場合、実行後にEventBridgeルールを無効化

**呼び出し元**: EventBridgeルール（スケジュール実行時）

**VPC接続**: あり（RDS APIとStep Functions APIにアクセスするため）

**タイムアウト**: 900秒（15分）

---

## 3. `modify-instance` Lambda関数

**役割**: RDSインスタンスのインスタンスタイプを変更する

**主な処理**:
- 指定されたインスタンスIDとターゲットインスタンスタイプを受け取る
- インスタンスの現在の状態を確認
- `deleting`状態の場合はスキップ
- `modifying`状態の場合は既に変更中として成功を返す
- `available`状態の場合は`modify_db_instance`を実行してインスタンスタイプを変更

**呼び出し元**: Step Functions（`ScaleDedicatedReader`, `ScaleOldWriter`, `ScaleAutoScalingReader`）

**VPC接続**: あり（RDS APIにアクセスするため）

**タイムアウト**: 60秒

---

## 4. `check-instance-status` Lambda関数

**役割**: インスタンスのステータスとインスタンスタイプを確認する

**主な処理**:
- 指定されたインスタンスID（複数可）のステータスを確認
- 各インスタンスについて以下をチェック:
  - ステータスが`available`であるか
  - インスタンスタイプがターゲットタイプと一致しているか（`targetClass`が指定されている場合）
- すべてのインスタンスが`available`かつ正しいインスタンスタイプの場合、`allAvailable: true`を返す
- 1つでも条件を満たさない場合、`allAvailable: false`を返す

**呼び出し元**: Step Functions（各ステータスチェックステップ）

**VPC接続**: あり（RDS APIにアクセスするため）

**タイムアウト**: 30秒

---

## 5. `failover-cluster` Lambda関数

**役割**: Auroraクラスターを指定したインスタンスにフェイルオーバーする

**主な処理**:
- クラスター識別子とターゲットインスタンスIDを受け取る
- ターゲットインスタンスの状態を確認
- インスタンスが`available`でない場合はエラーを発生
- `failover_db_cluster`を実行してフェイルオーバーを開始

**呼び出し元**: Step Functions（`FailoverToDedicatedReader`）

**VPC接続**: あり（RDS APIにアクセスするため）

**タイムアウト**: 60秒

**注意**: インスタンスが`available`でない場合（停止状態から起動中など）はエラーになるが、Step FunctionsのCatchブロックでリトライロジックに進む

---

## 6. `get-cluster-instances` Lambda関数

**役割**: クラスターから現在のインスタンス情報を取得し、Writer/Dedicated Reader/AutoScaling Readerに分類する

**主な処理**:
- クラスター識別子を受け取る
- `describe_db_clusters`でクラスター情報を取得
- 各インスタンスの詳細情報を取得
- インスタンスを分類:
  - Writer: `IsClusterWriter: true`のインスタンス
  - Dedicated Reader: `Role: dedicated-reader`タグを持つインスタンス
  - AutoScaling Reader: `Role: autoscaling-reader`タグを持つインスタンス、または`as-`を含むIDのインスタンス
- `deleting`や`deleted`状態のインスタンスはスキップ
- 分類結果を返す

**呼び出し元**: Step Functions（`RefreshDedicatedReaderInfo`, `RefreshFailoverInfo`, `RefreshOldWriterInfo`）

**VPC接続**: あり（RDS APIにアクセスするため）

**タイムアウト**: 60秒

**用途**: リトライ時に削除中インスタンスが検出された場合、クラスター情報を再取得してインスタンスIDを更新するために使用

---

## 7. `send-notification` Lambda関数

**役割**: SNS経由で処理完了/失敗の通知を送信する

**主な処理**:
- Step Functionsからの実行結果を受け取る
- 処理が成功した場合と失敗した場合でメッセージを分ける
- SNSトピックに通知を発行

**呼び出し元**: Step Functions（`SendCompletionNotification`）

**VPC接続**: なし（SNS APIのみ使用）

**タイムアウト**: 30秒

---

## Lambda関数の分類

### VPC接続あり（RDS APIにアクセスするため）
1. `modify-instance`
2. `check-instance-status`
3. `failover-cluster`
4. `get-cluster-instances`
5. `schedule-scaling`

### VPC接続なし
1. `update-schedule`（EventBridge APIのみ）
2. `send-notification`（SNS APIのみ）

### IAMロールの分類

**`lambda-scaling-role`を使用**（RDS操作、Step Functions実行、EventBridge操作の権限）:
- `modify-instance`
- `check-instance-status`
- `failover-cluster`
- `get-cluster-instances`
- `schedule-scaling`
- `update-schedule`

**`lambda-notification-role`を使用**（SNS発行の権限のみ）:
- `send-notification`

---

## 実行フローでの役割

```
1. ユーザー → update-schedule: スケジュール設定
2. EventBridge → schedule-scaling: 指定時間に実行
3. schedule-scaling → Step Functions: 実行開始
4. Step Functions → modify-instance: インスタンスタイプ変更
5. Step Functions → check-instance-status: ステータス確認
6. Step Functions → failover-cluster: フェイルオーバー
7. Step Functions → get-cluster-instances: インスタンス情報更新（リトライ時）
8. Step Functions → send-notification: 完了通知
```

