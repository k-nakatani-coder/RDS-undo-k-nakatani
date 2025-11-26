import json
import boto3
import logging
import os
from datetime import datetime, timedelta
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

events = boto3.client('events')

def lambda_handler(event, context):
    """
    EventBridgeルールのスケジュール式を更新する
    実行時間をユーザーが指定できるようにする
    """
    try:
        # イベントから設定を取得
        cluster_identifier = event.get('clusterIdentifier')
        target_class = event.get('targetClass')
        schedule_time = event.get('scheduleTime')  # 形式: "HH:MM" (JST), "YYYY-MM-DD HH:MM" (JST), または cron式
        disable_after_execution = event.get('disableAfterExecution', True)  # 実行後に無効化するか（デフォルト: True）
        
        if not cluster_identifier:
            cluster_identifier = os.environ.get('CLUSTER_IDENTIFIER')
        if not target_class:
            target_class = os.environ.get('TARGET_CLASS', 'db.t4g.medium')
        if not schedule_time:
            raise ValueError("scheduleTime is required (format: 'HH:MM' or 'YYYY-MM-DD HH:MM' in JST, or cron expression)")
        
        if not cluster_identifier:
            raise ValueError("clusterIdentifier is required")
        
        # ルール名を取得
        rule_name = os.environ.get('EVENTBRIDGE_RULE_NAME')
        if not rule_name:
            # デフォルトのルール名を生成
            rule_name = f"{os.environ.get('PROJECT_NAME', 'k-nakatani')}-{os.environ.get('ENVIRONMENT', 'dev')}-schedule-scaling"
        
        # スケジュール式を生成
        schedule_expression, description = convert_to_schedule_expression(schedule_time)
        
        logger.info(f"Updating EventBridge rule: {rule_name}")
        logger.info(f"New schedule: {schedule_expression}")
        logger.info(f"Target class: {target_class}, Cluster: {cluster_identifier}")
        logger.info(f"Disable after execution: {disable_after_execution}")
        
        # EventBridgeルールを更新
        events.put_rule(
            Name=rule_name,
            ScheduleExpression=schedule_expression,
            State='ENABLED',
            Description=description
        )
        
        # ターゲットの入力パラメータを更新
        targets = events.list_targets_by_rule(Rule=rule_name)
        
        if targets['Targets']:
            # 既存のターゲットを更新
            target = targets['Targets'][0]
            target['Input'] = json.dumps({
                'clusterIdentifier': cluster_identifier,
                'targetClass': target_class
            })
            
            events.put_targets(
                Rule=rule_name,
                Targets=[target]
            )
        else:
            # ターゲットが存在しない場合はエラー
            raise ValueError(f"Target not found for rule: {rule_name}")
        
        logger.info(f"Successfully updated EventBridge rule: {rule_name}")
        
        response_body = {
            'message': 'EventBridge rule updated successfully',
            'ruleName': rule_name,
            'scheduleExpression': schedule_expression,
            'scheduleTime': schedule_time,
            'targetClass': target_class,
            'clusterIdentifier': cluster_identifier,
            'disableAfterExecution': disable_after_execution
        }
        
        # 実行後に無効化する必要がある場合、その旨を記録
        if disable_after_execution:
            response_body['note'] = 'Rule will be disabled after execution. Use update-schedule again to schedule another execution.'
        
        return {
            'statusCode': 200,
            'body': json.dumps(response_body)
        }
        
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        raise e


def convert_to_schedule_expression(schedule_time):
    """
    スケジュール時間をEventBridgeのスケジュール式に変換
    形式:
    - "HH:MM" (JST) -> cron式 (UTC) - 毎日同じ時間
    - "YYYY-MM-DD HH:MM" (JST) -> at()式 (UTC) - 特定の日時
    - cron式 -> そのまま返す
    
    JST = UTC + 9時間
    """
    try:
        # cron式の場合はそのまま返す
        if schedule_time.startswith('cron('):
            return schedule_time, f"Trigger Aurora scaling (cron: {schedule_time})"
        
        # "YYYY-MM-DD HH:MM"形式の場合（特定の日時）
        if len(schedule_time) > 5 and ' ' in schedule_time:
            date_str, time_str = schedule_time.split(' ', 1)
            year, month, day = map(int, date_str.split('-'))
            hour, minute = map(int, time_str.split(':'))
            
            # JSTからUTCに変換（JST = UTC + 9時間）
            jst_datetime = datetime(year, month, day, hour, minute)
            utc_datetime = jst_datetime - timedelta(hours=9)
            
            # 過去の日時でないことを確認
            now_utc = datetime.utcnow()
            if utc_datetime < now_utc:
                raise ValueError(f"Schedule time {schedule_time} JST is in the past. Please specify a future time.")
            
            # EventBridgeルールではat()式は使えないため、cron式を使用
            # cron式の形式: cron(分 時 日 月 ? 年)
            # 注意: EventBridgeのcron式は年をサポートしていないため、年は無視される
            # 特定の日時を指定するには、日と月を指定するcron式を使用
            cron_expression = f"cron({utc_datetime.minute} {utc_datetime.hour} {utc_datetime.day} {utc_datetime.month} ? *)"
            description = f"Trigger Aurora scaling at {schedule_time} JST (one-time execution on {date_str})"
            return cron_expression, description
        
        # "HH:MM"形式の場合（毎日同じ時間）
        if ':' in schedule_time and len(schedule_time) <= 5:
            hour, minute = map(int, schedule_time.split(':'))
            
            # JSTからUTCに変換（JST = UTC + 9時間）
            utc_hour = (hour - 9) % 24
            if utc_hour < 0:
                utc_hour += 24
            
            # cron式を生成: cron(分 時 * * ? *)
            cron_expression = f"cron({minute} {utc_hour} * * ? *)"
            description = f"Trigger Aurora scaling daily at {schedule_time} JST"
            return cron_expression, description
        
        raise ValueError(f"Invalid schedule time format: {schedule_time}. Use 'HH:MM' (JST), 'YYYY-MM-DD HH:MM' (JST), or cron expression")
        
    except ValueError as e:
        raise e
    except Exception as e:
        raise ValueError(f"Failed to convert schedule time: {str(e)}")

