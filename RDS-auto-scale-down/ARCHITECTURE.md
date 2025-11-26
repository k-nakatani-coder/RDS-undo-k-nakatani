# Aurora スケールダウン自動化システム アーキテクチャ

## 概要

Aurora PostgreSQLクラスターのインスタンスタイプを自動的にスケールダウンするシステムです。

### 主な特徴

- **柔軟なスケジュール設定**: 毎日同じ時間に実行するか、特定の日時のみ実行するかを選択可能
- **動的なインスタンス情報取得**: クラスターから現在のインスタンス情報を動的に取得して処理を実行
- **デフォルトで無効化**: EventBridgeルールはデフォルトで無効化されており、必要な時だけ有効化
- **自動無効化**: 特定の日時を指定した場合、実行後に自動的にルールが無効化される
- **VPCエンドポイント経由**: セキュアで高速なAWS APIアクセス

## システム構成図

```mermaid
graph TB
    subgraph "ユーザー操作"
        User[ユーザー]
    end
    
    subgraph "AWS EventBridge"
        EB[EventBridge Rule<br/>スケジュール実行]
    end
    
    subgraph "AWS Lambda"
        UpdateSchedule[update-schedule<br/>スケジュール更新]
        ScheduleScaling[schedule-scaling<br/>スケール実行トリガー<br/>直接RDS API呼び出し]
        GetClusterInstances[get-cluster-instances<br/>インスタンス情報取得]
        ModifyInstance[modify-instance<br/>インスタンスタイプ変更]
        CheckStatus[check-instance-status<br/>ステータス確認<br/>インスタンスタイプ検証]
        Failover[failover-cluster<br/>フェイルオーバー]
        SendNotification[send-notification<br/>通知送信]
    end
    
    subgraph "AWS Step Functions"
        SF[State Machine<br/>スケールダウンワークフロー]
    end
    
    subgraph "Amazon RDS Aurora"
        Cluster[Aurora Cluster]
        Writer[Writer Instance]
        DedicatedReader[Dedicated Reader]
        AutoScalingReaders[AutoScaling Readers<br/>1-14台]
    end
    
    subgraph "AWS SNS"
        SNS[SNS Topic<br/>通知]
    end
    
    User -->|1. スケジュール設定| UpdateSchedule
    UpdateSchedule -->|EventBridgeルール更新<br/>（デフォルトは無効）| EB
    EB -->|2. 指定時間に実行| ScheduleScaling
    ScheduleScaling -->|3. 直接RDS API呼び出し| Cluster
    Cluster -->|インスタンス一覧| ScheduleScaling
    ScheduleScaling -->|4. JSON作成して実行| SF
    SF -->|5. スケールダウン処理| ModifyInstance
    SF -->|ステータス確認<br/>インスタンスタイプ検証| CheckStatus
    SF -->|フェイルオーバー| Failover
    SF -->|インスタンス情報取得| GetClusterInstances
    ModifyInstance -->|変更| Writer
    ModifyInstance -->|変更| DedicatedReader
    ModifyInstance -->|変更| AutoScalingReaders
    CheckStatus -->|確認| Cluster
    Failover -->|フェイルオーバー| Cluster
    GetClusterInstances -->|取得| Cluster
    SF -->|完了通知| SendNotification
    SendNotification -->|通知| SNS
```

## ネットワーク構成

```mermaid
graph TB
    subgraph "VPC: 10.0.0.0/16"
        subgraph "Public Subnets"
            PublicSubnet1[Public Subnet 1<br/>AZ-1]
            PublicSubnet2[Public Subnet 2<br/>AZ-2]
        end
        
        subgraph "Private Subnets - Aurora"
            AuroraSubnet1[Aurora Subnet 1<br/>AZ-1]
            AuroraSubnet2[Aurora Subnet 2<br/>AZ-2]
            AuroraSubnet3[Aurora Subnet 3<br/>AZ-3]
        end
        
        subgraph "Private Subnets - Lambda"
            LambdaSubnet1[Lambda Subnet 1<br/>AZ-1]
            LambdaSubnet2[Lambda Subnet 2<br/>AZ-2]
            LambdaSubnet3[Lambda Subnet 3<br/>AZ-3]
        end
        
        subgraph "VPC Endpoints"
            RDSEndpoint[RDS Endpoint]
            LogsEndpoint[CloudWatch Logs Endpoint]
            StatesEndpoint[Step Functions Endpoint]
        end
        
        IGW[Internet Gateway]
        NAT1[NAT Gateway 1]
        NAT2[NAT Gateway 2]
        
        IGW --> PublicSubnet1
        IGW --> PublicSubnet2
        NAT1 --> PublicSubnet1
        NAT2 --> PublicSubnet2
        NAT1 --> LambdaSubnet1
        NAT2 --> LambdaSubnet2
        
        LambdaSubnet1 --> RDSEndpoint
        LambdaSubnet2 --> RDSEndpoint
        LambdaSubnet3 --> RDSEndpoint
        LambdaSubnet1 --> LogsEndpoint
        LambdaSubnet2 --> LogsEndpoint
        LambdaSubnet3 --> LogsEndpoint
        LambdaSubnet1 --> StatesEndpoint
        LambdaSubnet2 --> StatesEndpoint
        LambdaSubnet3 --> StatesEndpoint
    end
```

## インスタンス構成

```mermaid
graph LR
    subgraph "Aurora Cluster"
        Writer[Writer<br/>1台]
        DedicatedReader[Dedicated Reader<br/>1台]
        AutoScaling[AutoScaling Readers<br/>1-14台]
    end
    
    Writer -->|読み書き| ClusterEndpoint[Cluster Endpoint]
    DedicatedReader -->|読み取り| ReaderEndpoint[Reader Endpoint]
    AutoScaling -->|読み取り| ReaderEndpoint
```

## スケールダウン処理フロー

```mermaid
stateDiagram-v2
    [*] --> ValidateInput: Step Functions開始
    
    ValidateInput --> ScaleDedicatedReader: 入力検証
    
    ScaleDedicatedReader --> WaitForDedicatedReader: Dedicated Reader<br/>スケールダウン開始
    WaitForDedicatedReader --> CheckDedicatedReaderStatus: 60秒待機
    CheckDedicatedReaderStatus --> EvaluateDedicatedReaderStatus: ステータス確認
    
    EvaluateDedicatedReaderStatus --> FailoverToDedicatedReader: available<br/>かつ正しいインスタンスタイプ
    EvaluateDedicatedReaderStatus --> IncrementDedicatedReaderRetry: リトライカウンター<5
    EvaluateDedicatedReaderStatus --> DedicatedReaderStatusError: リトライカウンター>=5
    IncrementDedicatedReaderRetry --> WaitForDedicatedReaderRetry: カウンター+1
    WaitForDedicatedReaderRetry --> RefreshDedicatedReaderInfo: 10分待機
    RefreshDedicatedReaderInfo --> UpdateDedicatedReaderInfo: インスタンス情報更新
    UpdateDedicatedReaderInfo --> CheckDedicatedReaderStatus: 情報更新完了
    
    FailoverToDedicatedReader --> WaitForFailover: フェイルオーバー開始
    FailoverToDedicatedReader --> CheckFailoverStatus: エラー時<br/>（Catch）
    WaitForFailover --> CheckFailoverStatus: 120秒待機
    CheckFailoverStatus --> EvaluateFailoverStatus: ステータス確認<br/>インスタンスタイプ検証
    
    EvaluateFailoverStatus --> ScaleOldWriter: available<br/>かつ正しいインスタンスタイプ
    EvaluateFailoverStatus --> IncrementFailoverRetry: リトライカウンター<5
    EvaluateFailoverStatus --> FailoverStatusError: リトライカウンター>=5
    IncrementFailoverRetry --> WaitForFailoverRetry: カウンター+1
    WaitForFailoverRetry --> RefreshFailoverInfo: 10分待機
    RefreshFailoverInfo --> UpdateFailoverInfo: インスタンス情報更新
    UpdateFailoverInfo --> CheckFailoverStatus: 情報更新完了
    
    ScaleOldWriter --> WaitForOldWriter: 旧Writer<br/>スケールダウン開始
    WaitForOldWriter --> CheckOldWriterStatus: 60秒待機
    CheckOldWriterStatus --> EvaluateOldWriterStatus: ステータス確認<br/>インスタンスタイプ検証
    
    EvaluateOldWriterStatus --> ProcessAutoScalingReaders: available<br/>かつ正しいインスタンスタイプ
    EvaluateOldWriterStatus --> IncrementOldWriterRetry: リトライカウンター<5
    EvaluateOldWriterStatus --> OldWriterStatusError: リトライカウンター>=5
    IncrementOldWriterRetry --> WaitForOldWriterRetry: カウンター+1
    WaitForOldWriterRetry --> RefreshOldWriterInfo: 10分待機
    RefreshOldWriterInfo --> UpdateOldWriterInfo: インスタンス情報更新
    UpdateOldWriterInfo --> CheckOldWriterStatus: 情報更新完了
    
    ProcessAutoScalingReaders --> ScaleAutoScalingReader: AutoScaling Reader<br/>1台ずつ処理
    ScaleAutoScalingReader --> WaitForAutoScalingReader: スケールダウン開始
    WaitForAutoScalingReader --> CheckAutoScalingReaderStatus: 60秒待機
    CheckAutoScalingReaderStatus --> EvaluateAutoScalingReaderStatus: ステータス確認<br/>インスタンスタイプ検証
    
    EvaluateAutoScalingReaderStatus --> AutoScalingReaderComplete: available<br/>かつ正しいインスタンスタイプ
    EvaluateAutoScalingReaderStatus --> IncrementAutoScalingReaderRetry: リトライカウンター<5
    EvaluateAutoScalingReaderStatus --> AutoScalingReaderStatusError: リトライカウンター>=5
    IncrementAutoScalingReaderRetry --> WaitForAutoScalingReaderRetry: カウンター+1
    WaitForAutoScalingReaderRetry --> CheckAutoScalingReaderStatus: 10分待機
    
    AutoScalingReaderComplete --> ProcessAutoScalingReaders: 次のインスタンス
    ProcessAutoScalingReaders --> PrepareFinalVerification: 全インスタンス完了
    
    PrepareFinalVerification --> FinalVerification: 最終確認準備
    FinalVerification --> FinalVerificationAutoScaling: Writer/Reader確認
    FinalVerificationAutoScaling --> EvaluateFinalVerification: AutoScaling確認
    
    EvaluateFinalVerification --> CheckFinalVerificationResult: 結果評価
    CheckFinalVerificationResult --> SendCompletionNotification: 全てavailable<br/>かつ正しいインスタンスタイプ
    CheckFinalVerificationResult --> IncrementOverallRetry: 全体リトライ<3<br/>（タイプ不一致または未available）
    CheckFinalVerificationResult --> OverallRetryError: 全体リトライ>=3
    
    IncrementOverallRetry --> WaitBeforeRetry: 全体リトライ+1
    WaitBeforeRetry --> ScaleDedicatedReader: 60秒待機後<br/>最初から再実行
    
    SendCompletionNotification --> [*]: 完了
    
    DedicatedReaderStatusError --> [*]: エラー
    FailoverStatusError --> [*]: エラー
    OldWriterStatusError --> [*]: エラー
    AutoScalingReaderStatusError --> [*]: エラー
    OverallRetryError --> [*]: エラー
```

## スケジュール実行フロー

```mermaid
sequenceDiagram
    participant User as ユーザー
    participant UpdateSchedule as update-schedule<br/>Lambda
    participant EventBridge as EventBridge Rule
    participant ScheduleScaling as schedule-scaling<br/>Lambda
    participant StepFunctions as Step Functions
    participant RDS as Aurora Cluster
    
    User->>UpdateSchedule: 1. スケジュール設定<br/>(clusterIdentifier, targetClass, scheduleTime)
    Note over UpdateSchedule: scheduleTime形式:<br/>- "HH:MM" (毎日)<br/>- "YYYY-MM-DD HH:MM" (特定日時)
    UpdateSchedule->>EventBridge: 2. スケジュール式と<br/>入力パラメータを更新<br/>（ルールを有効化）
    EventBridge-->>User: 設定完了
    
    Note over EventBridge: 指定時間まで待機<br/>（デフォルトは無効状態）
    
    EventBridge->>ScheduleScaling: 3. 指定時間に実行
    ScheduleScaling->>RDS: 4. 直接RDS API呼び出し<br/>（VPCエンドポイント経由）
    RDS-->>ScheduleScaling: インスタンス情報<br/>(Writer, Dedicated Reader, AutoScaling Readers)
    ScheduleScaling->>ScheduleScaling: 5. JSON作成
    ScheduleScaling->>StepFunctions: 6. Step Functions実行開始<br/>（VPCエンドポイント経由）
    Note over ScheduleScaling: 特定日時の場合、<br/>実行後にルールを無効化
    StepFunctions->>RDS: 7. スケールダウン処理
```

## スケールダウン順序

```mermaid
graph TD
    Start[開始] --> Step1[1. Dedicated Reader<br/>スケールダウン]
    Step1 --> Step2[2. ステータス確認<br/>インスタンスタイプ検証<br/>最大5回リトライ<br/>各10分待機<br/>（削除中インスタンスは情報更新）]
    Step2 --> Step3[3. Dedicated Readerに<br/>フェイルオーバー<br/>（エラー時はリトライ）]
    Step3 --> Step4[4. フェイルオーバー完了確認<br/>インスタンスタイプ検証<br/>最大5回リトライ<br/>各10分待機<br/>（削除中インスタンスは情報更新）]
    Step4 --> Step5[5. 旧Writer<br/>スケールダウン]
    Step5 --> Step6[6. ステータス確認<br/>インスタンスタイプ検証<br/>最大5回リトライ<br/>各10分待機<br/>（削除中インスタンスは情報更新）]
    Step6 --> Step7[7. AutoScaling Readers<br/>1台ずつスケールダウン]
    Step7 --> Step8[8. 各インスタンスの<br/>ステータス確認<br/>インスタンスタイプ検証<br/>最大5回リトライ<br/>各10分待機]
    Step8 --> Step9[9. 最終確認<br/>全インスタンスがavailableかつ<br/>正しいインスタンスタイプか確認]
    Step9 --> Step10{全てavailable<br/>かつ正しいタイプ?}
    Step10 -->|Yes| End[完了通知]
    Step10 -->|No| Step11{全体リトライ<3?}
    Step11 -->|Yes| Step12[60秒待機後<br/>最初から再実行]
    Step12 --> Step1
    Step11 -->|No| Error[エラー]
```

## コンポーネント一覧

### EventBridgeルール

| 項目 | 説明 |
|------|------|
| ルール名 | `k-nakatani-dev-schedule-scaling` |
| デフォルト状態 | `DISABLED`（無効） |
| 有効化方法 | `update-schedule` Lambda関数でスケジュールを設定すると自動的に有効化 |
| スケジュール形式 | 
  - `cron()`式: 毎日同じ時間に実行
  - `cron()`式（特定日時）: 特定の日時に1回だけ実行 |
| 実行後動作 | 特定の日時を指定した場合、実行後に自動的に無効化される |

### Lambda関数

| 関数名 | 役割 | VPC接続 | タイムアウト |
|--------|------|---------|-------------|
| `update-schedule` | EventBridgeルールのスケジュール式を更新 | なし | 30秒 |
| `schedule-scaling` | スケール実行をトリガー、直接RDS API呼び出しでJSON作成 | あり | 900秒 |
| `modify-instance` | インスタンスタイプを変更 | あり | 60秒 |
| `check-instance-status` | インスタンスのステータスとインスタンスタイプを確認 | あり | 30秒 |
| `get-cluster-instances` | クラスターから現在のインスタンス情報を取得 | あり | 60秒 |
| `failover-cluster` | クラスターをフェイルオーバー | あり | 60秒 |
| `send-notification` | SNS経由で通知を送信 | なし | 30秒 |

### Step Functions ステート

| ステート名 | タイプ | 説明 |
|-----------|--------|------|
| `ValidateInput` | Pass | 入力パラメータの検証と初期化 |
| `ScaleDedicatedReader` | Task | Dedicated Readerをスケールダウン |
| `WaitForDedicatedReader` | Wait | 60秒待機 |
| `CheckDedicatedReaderStatus` | Task | Dedicated Readerのステータスとインスタンスタイプ確認 |
| `EvaluateDedicatedReaderStatus` | Choice | ステータス評価（リトライ判定） |
| `RefreshDedicatedReaderInfo` | Task | インスタンス情報を再取得（削除中インスタンス対応） |
| `UpdateDedicatedReaderInfo` | Pass | インスタンス情報を更新 |
| `FailoverToDedicatedReader` | Task | Dedicated Readerにフェイルオーバー（Catchブロック付き） |
| `WaitForFailover` | Wait | 120秒待機 |
| `CheckFailoverStatus` | Task | フェイルオーバーのステータスとインスタンスタイプ確認 |
| `RefreshFailoverInfo` | Task | インスタンス情報を再取得（削除中インスタンス対応） |
| `UpdateFailoverInfo` | Pass | インスタンス情報を更新 |
| `ScaleOldWriter` | Task | 旧Writerをスケールダウン |
| `CheckOldWriterStatus` | Task | 旧Writerのステータスとインスタンスタイプ確認 |
| `RefreshOldWriterInfo` | Task | インスタンス情報を再取得（削除中インスタンス対応） |
| `UpdateOldWriterInfo` | Pass | インスタンス情報を更新 |
| `ProcessAutoScalingReaders` | Map | AutoScaling Readersを1台ずつ処理 |
| `CheckAutoScalingReaderStatus` | Task | AutoScaling Readerのステータスとインスタンスタイプ確認 |
| `FinalVerification` | Task | 全インスタンスの最終確認（ステータスとインスタンスタイプ） |
| `FinalVerificationAutoScaling` | Task | AutoScaling Readersの最終確認（ステータスとインスタンスタイプ） |
| `SendCompletionNotification` | Task | 完了通知を送信 |

### VPCエンドポイント

| エンドポイント | サービス | 用途 |
|---------------|---------|------|
| RDS Endpoint | `com.amazonaws.ap-northeast-1.rds` | Lambda関数からRDS APIを呼び出すため |
| CloudWatch Logs Endpoint | `com.amazonaws.ap-northeast-1.logs` | Lambda関数のログをCloudWatch Logsに送信するため |
| Step Functions Endpoint | `com.amazonaws.ap-northeast-1.states` | Lambda関数からStep Functions APIを呼び出すため |

**メリット**:
- インターネット経由のアクセスが不要
- セキュリティの向上（VPC内での通信）
- パフォーマンスの向上（低レイテンシ）

### IAMロール

| ロール名 | 用途 | 主な権限 |
|---------|------|---------|
| `lambda-scaling-role` | スケーリング用Lambda関数 | RDS操作、Step Functions実行、EventBridge操作 |
| `lambda-notification-role` | 通知用Lambda関数 | SNS発行、CloudWatch Logs |
| `stepfunctions-execution-role` | Step Functions実行 | Lambda関数呼び出し |

### リトライロジック

```mermaid
graph LR
    A[ステータスチェック] --> B{available?}
    B -->|Yes| C[次のステップへ]
    B -->|No| D{リトライカウンター<br/>< 5?}
    D -->|Yes| E[カウンター+1]
    E --> F[10分待機]
    F --> A
    D -->|No| G[エラー]
    
    H[最終確認] --> I{全てavailable?}
    I -->|Yes| J[完了]
    I -->|No| K{全体リトライ<br/>< 3?}
    K -->|Yes| L[カウンター+1]
    L --> M[60秒待機]
    M --> N[最初から再実行]
    N --> A
    K -->|No| O[エラー]
```

## データフロー

### スケジュール設定時

```mermaid
graph LR
    User[ユーザー] -->|JSON入力| UpdateSchedule[update-schedule Lambda]
    UpdateSchedule -->|スケジュール式更新| EventBridge[EventBridge Rule]
    UpdateSchedule -->|入力パラメータ更新| EventBridge
    EventBridge -->|保存| Config[設定保存完了]
```

### 実行時

```mermaid
graph LR
    EventBridge[EventBridge Rule] -->|イベント| ScheduleScaling[schedule-scaling Lambda]
    ScheduleScaling -->|直接API呼び出し<br/>（VPCエンドポイント経由）| RDS[RDS API]
    RDS -->|インスタンス情報| ScheduleScaling
    ScheduleScaling -->|JSON作成| StepFunctions[Step Functions<br/>VPCエンドポイント経由]
    StepFunctions -->|実行| ModifyInstance[modify-instance Lambda]
    StepFunctions -->|確認| CheckStatus[check-instance-status Lambda]
    StepFunctions -->|フェイルオーバー| Failover[failover-cluster Lambda]
    StepFunctions -->|通知| SendNotification[send-notification Lambda]
    SendNotification -->|通知| SNS[SNS Topic]
```

## 設定パラメータ

### EventBridgeルールの入力パラメータ

```json
{
  "clusterIdentifier": "k-nakatani-dev-cluster",
  "targetClass": "db.t4g.medium"
}
```

### Step Functionsの入力JSON

```json
{
  "targetClass": "db.t4g.medium",
  "clusterIdentifier": "k-nakatani-dev-cluster",
  "writerInstanceId": "k-nakatani-dev-writer",
  "dedicatedReaderInstanceId": "k-nakatani-dev-reader-dedicated",
  "autoScalingReaderInstanceIds": [
    "k-nakatani-dev-reader-as-1"
  ]
}
```

### スケジュール更新Lambda関数の入力

#### 毎日同じ時間に実行する場合

```json
{
  "clusterIdentifier": "k-nakatani-dev-cluster",
  "targetClass": "db.t4g.medium",
  "scheduleTime": "19:15"
}
```

#### 特定の日時のみ実行する場合

```json
{
  "clusterIdentifier": "k-nakatani-dev-cluster",
  "targetClass": "db.t4g.large",
  "scheduleTime": "2025-11-18 23:14"
}
```

**注意**: 
- `scheduleTime`はJST（日本時間）で指定
- 特定の日時を指定した場合、実行後に自動的にEventBridgeルールが無効化される
- 過去の日時を指定することはできない

## リトライ戦略

### 個別インスタンスのリトライ

- **最大リトライ回数**: 5回
- **リトライ間隔**: 10分（600秒）
- **最大待機時間**: 50分（10分 × 5回）
- **リトライ時の処理**: 削除中（`deleting`）インスタンスが検出された場合、クラスター情報を再取得してインスタンスIDを更新
- **検証項目**: 
  - インスタンスステータスが`available`であること
  - インスタンスタイプがターゲットタイプと一致していること

### 全体リトライ

- **最大リトライ回数**: 3回
- **リトライ間隔**: 60秒
- **最大待機時間**: 3分（60秒 × 3回）
- **トリガー条件**: 最終確認で、いずれかのインスタンスが`available`でない、またはインスタンスタイプがターゲットと一致しない場合

## セキュリティ

### ネットワークセキュリティ

- Lambda関数はVPC内のプライベートサブネットで実行
- RDSはプライベートサブネットに配置
- VPCエンドポイント経由でAWS APIにアクセス（RDS、CloudWatch Logs、Step Functions）
  - インターネット経由のアクセスを不要にし、セキュリティとパフォーマンスを向上

### IAM権限

- 最小権限の原則に基づいて権限を分離
- スケーリング用と通知用でロールを分離
- リソースベースのポリシーでアクセス制限

## モニタリングと通知

- CloudWatch LogsでLambda関数のログを記録
- SNS経由で処理完了/失敗を通知
- Step Functionsの実行履歴で処理状況を確認

## エラーハンドリング

- 各ステップでリトライロジックを実装
- 最大リトライ回数に達した場合はエラーを返す
- エラー時はSNS経由で通知
- 詳細なエラーログを出力（エラーコード、メッセージ、トレースバック）
- 各処理ステップで残り実行時間をログに記録
- `FailoverToDedicatedReader`にCatchブロックを追加し、インスタンスが`available`でない場合のエラーをリトライロジックで処理
- 削除中（`deleting`）インスタンスが検出された場合、クラスター情報を再取得してインスタンスIDを更新
- インスタンスタイプの検証を追加し、スケールダウンが正しく完了しているかを確認
- 停止状態から起動した場合でも、インスタンスが`available`になるまで待機してから処理を続行

