import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client('sns')

def lambda_handler(event, context):
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if not topic_arn:
        logger.error("SNS_TOPIC_ARN environment variable is not set.")
        raise ValueError("SNS_TOPIC_ARN environment variable is not set.")

    try:
        execution_name = event.get('executionName', 'unknown')
        end_time = datetime.utcnow().isoformat()

        if 'Error' in event:
            # 失敗（Catchブロックから呼び出された）場合の処理
            status = "FAILED"
            subject = f"Aurora Scaling FAILED: {execution_name}"
            
            # エラー原因（Cause）はJSON文字列の可能性があるためパースを試みる
            try:
                cause_data = json.loads(event.get('Cause', '{}'))
                cause_str = json.dumps(cause_data, indent=2, ensure_ascii=False)
            except (json.JSONDecodeError, TypeError):
                cause_str = event.get('Cause', 'Unknown cause')
                
            message_body = f"""
[監視アラート] Aurora インスタンススケーリングが【失敗】しました。

実行名: {execution_name}
ステータス: {status}
完了時刻: {end_time}

エラータイプ: {event.get('Error')}
エラー原因: 
{cause_str}
"""
        else:
            # 正常完了した場合の処理
            status = event.get('status', 'COMPLETED') # eventから渡されたステータス
            start_time = event.get('startTime', '')
            subject = f"Aurora Scaling {status.upper()}: {execution_name}"
            
            message_body = f"""
Aurora インスタンススケーリングが【{status}】しました。

実行名: {execution_name}
ステータス: {status}
開始時刻: {start_time}
完了時刻: {end_time}

詳細（Step Functions最終出力）:
{json.dumps(event, indent=2, ensure_ascii=False)}
"""

        # SNS通知送信
        response = sns.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=message_body
        )
        
        logger.info(f"Notification sent: {response['MessageId']}")
        
        # --- 改善点1: シンプルな返り値 ---
        return {
            'message': 'Notification sent successfully',
            'messageId': response['MessageId']
        }
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")
        # --- 改善点1: エラーは raise する ---
        raise Exception(f"Failed to send notification: {str(e)}")