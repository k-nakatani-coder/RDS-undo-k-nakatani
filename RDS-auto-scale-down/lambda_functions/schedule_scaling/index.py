import json
import boto3
import logging
import os
import re
import traceback
from datetime import datetime
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

rds = boto3.client('rds')
sfn = boto3.client('stepfunctions')
events = boto3.client('events')

def lambda_handler(event, context):
    """
    スケジュール実行用Lambda関数
    1. パラメータストアから設定を取得
    2. クラスターから現在のインスタンス情報を取得
    3. JSONを作成
    4. Step Functionsを実行
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        logger.info(f"Remaining time: {context.get_remaining_time_in_millis()} ms")
        
        # イベントから設定を取得（EventBridgeルールの入力パラメータまたは直接実行時のパラメータ）
        cluster_identifier = event.get('clusterIdentifier')
        target_class = event.get('targetClass')
        
        # 環境変数から取得（フォールバック）
        if not cluster_identifier:
            cluster_identifier = os.environ.get('CLUSTER_IDENTIFIER')
        if not target_class:
            target_class = os.environ.get('TARGET_CLASS', 'db.t4g.medium')
        
        if not cluster_identifier:
            raise ValueError("clusterIdentifier is required (set in event or CLUSTER_IDENTIFIER env var)")
        if not target_class:
            raise ValueError("targetClass is required (set in event or TARGET_CLASS env var)")
        
        logger.info(f"Using target class: {target_class} for cluster: {cluster_identifier}")
        
        # クラスターから現在のインスタンス情報を取得
        logger.info(f"Getting instances for cluster: {cluster_identifier}")
        logger.info(f"Remaining time before RDS call: {context.get_remaining_time_in_millis()} ms")
        
        # 直接RDS APIを呼び出す（Lambda関数間の呼び出しを避けるため）
        try:
            instances_info = get_instances_from_cluster(cluster_identifier)
            logger.info(f"Successfully retrieved instances info: {json.dumps(instances_info)}")
        except Exception as e:
            logger.error(f"Error getting instances from cluster: {str(e)}")
            logger.error(f"Traceback: {traceback.format_exc()}")
            raise
        
        # JSONを作成
        step_function_input = {
            'targetClass': target_class,
            'clusterIdentifier': cluster_identifier,
            'writerInstanceId': instances_info.get('writerInstanceId'),
            'dedicatedReaderInstanceId': instances_info.get('dedicatedReaderInstanceId'),
            'autoScalingReaderInstanceIds': instances_info.get('autoScalingReaderInstanceIds', [])
        }
        
        # 必須パラメータの検証
        if not step_function_input['writerInstanceId']:
            raise ValueError("Writer instance not found")
        if not step_function_input['dedicatedReaderInstanceId']:
            raise ValueError("Dedicated Reader instance not found")
        if not step_function_input['autoScalingReaderInstanceIds']:
            logger.warning("No AutoScaling Reader instances found")
        
        logger.info(f"Created Step Functions input: {json.dumps(step_function_input, indent=2)}")
        logger.info(f"Remaining time before Step Functions call: {context.get_remaining_time_in_millis()} ms")
        
        # Step Functionsを実行
        step_function_arn = os.environ.get('STEP_FUNCTION_ARN')
        if not step_function_arn:
            raise ValueError("STEP_FUNCTION_ARN environment variable is not set")
        
        execution_name = f"scaling-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}"
        
        try:
            logger.info(f"Starting Step Functions execution: {execution_name}")
            response = sfn.start_execution(
                stateMachineArn=step_function_arn,
                name=execution_name,
                input=json.dumps(step_function_input)
            )
            logger.info(f"Successfully started Step Functions execution: {response['executionArn']}")
            
            # 実行後にEventBridgeルールを無効化（特定の日時のcron式の場合のみ）
            # 毎日実行するcron式（* * ? * *）の場合は無効化しない
            try:
                rule_name = os.environ.get('EVENTBRIDGE_RULE_NAME')
                if rule_name:
                    rule_info = events.describe_rule(Name=rule_name)
                    schedule_expression = rule_info.get('ScheduleExpression', '')
                    description = rule_info.get('Description', '')
                    
                    # 特定の日時を指定するcron式を検出（日と月が具体的な値で、年が*でない場合）
                    # 例: cron(6 14 18 11 ? *) - 11月18日14:06に実行
                    # 毎日のcron式: cron(6 14 * * ? *) - 毎日14:06に実行
                    if schedule_expression.startswith('cron('):
                        # cron式を解析して、日と月が具体的な値か確認
                        cron_match = re.match(r'cron\((\d+)\s+(\d+)\s+(\d+|\*)\s+(\d+|\*)\s+\?\s+\*\)', schedule_expression)
                        if cron_match:
                            day = cron_match.group(3)
                            month = cron_match.group(4)
                            # 日と月が具体的な値（*でない）場合は、特定の日時の実行と判断
                            if day != '*' and month != '*':
                                logger.info(f"Disabling EventBridge rule after one-time execution: {rule_name}")
                                events.put_rule(
                                    Name=rule_name,
                                    ScheduleExpression=schedule_expression,
                                    State='DISABLED',
                                    Description=description + ' (disabled after execution)'
                                )
                                logger.info(f"EventBridge rule disabled: {rule_name}")
            except Exception as e:
                # ルールの無効化に失敗しても、Step Functionsの実行は成功しているので警告のみ
                logger.warning(f"Failed to disable EventBridge rule after execution: {str(e)}")
                
        except Exception as e:
            logger.error(f"Error starting Step Functions execution: {str(e)}")
            logger.error(f"Traceback: {traceback.format_exc()}")
            raise
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Step Functions execution started',
                'executionArn': response['executionArn'],
                'executionName': execution_name,
                'input': step_function_input
            })
        }
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        logger.error(f"AWS Client Error - Code: {error_code}, Message: {error_message}")
        logger.error(f"Full error response: {json.dumps(e.response, default=str)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise
    except ValueError as e:
        logger.error(f"Value Error: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise
    except Exception as e:
        logger.error(f"Unexpected Error: {str(e)}")
        logger.error(f"Error type: {type(e).__name__}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise


def get_instances_from_cluster(cluster_identifier):
    """
    クラスターから現在のインスタンス情報を取得
    """
    try:
        logger.info(f"Calling describe_db_clusters for cluster: {cluster_identifier}")
        # クラスターのインスタンスを取得
        response = rds.describe_db_clusters(
            DBClusterIdentifier=cluster_identifier
        )
        logger.info(f"describe_db_clusters response received")
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        logger.error(f"Error calling describe_db_clusters - Code: {error_code}, Message: {error_message}")
        logger.error(f"Full error response: {json.dumps(e.response, default=str)}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error in describe_db_clusters: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise
    
    cluster = response['DBClusters'][0]
    cluster_members = cluster.get('DBClusterMembers', [])
    
    # インスタンスIDのリストを取得
    instance_ids = [member['DBInstanceIdentifier'] for member in cluster_members]
    
    if not instance_ids:
        logger.warning(f"No instances found in cluster {cluster_identifier}")
        return {
            'writerInstanceId': None,
            'dedicatedReaderInstanceId': None,
            'autoScalingReaderInstanceIds': []
        }
    
    # 各インスタンスの詳細を取得
    try:
        logger.info(f"Calling describe_db_instances for {len(instance_ids)} instances")
        instances_response = rds.describe_db_instances(
            Filters=[
                {
                    'Name': 'db-instance-id',
                    'Values': instance_ids
                }
            ]
        )
        logger.info(f"describe_db_instances response received: {len(instances_response.get('DBInstances', []))} instances")
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        logger.error(f"Error calling describe_db_instances - Code: {error_code}, Message: {error_message}")
        logger.error(f"Full error response: {json.dumps(e.response, default=str)}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error in describe_db_instances: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise
    
    instances = instances_response['DBInstances']
    
    # Writer、Dedicated Reader、AutoScaling Readerを分類
    writer_instance_id = None
    dedicated_reader_instance_id = None
    auto_scaling_reader_instance_ids = []
    
    for instance in instances:
        instance_id = instance['DBInstanceIdentifier']
        instance_status = instance.get('DBInstanceStatus', 'unknown')
        
        # 削除中または削除済みのインスタンスは除外
        if instance_status in ['deleting', 'deleted']:
            logger.info(f"Skipping instance {instance_id} with status: {instance_status}")
            continue
        
        # クラスターメンバー情報からWriterを判定
        cluster_member = next(
            (m for m in cluster_members if m['DBInstanceIdentifier'] == instance_id),
            None
        )
        is_writer = cluster_member.get('IsClusterWriter', False) if cluster_member else False
        
        # タグからRoleを取得
        try:
            tags_response = rds.list_tags_for_resource(
                ResourceName=instance['DBInstanceArn']
            )
            tags = {tag['Key']: tag['Value'] for tag in tags_response.get('TagList', [])}
            role = tags.get('Role', '')
            logger.debug(f"Instance {instance_id} tags: {tags}, role: {role}")
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            logger.warning(f"Failed to get tags for {instance_id} - Code: {error_code}, Message: {str(e)}")
            role = ''
        except Exception as e:
            logger.warning(f"Failed to get tags for {instance_id}: {str(e)}")
            logger.warning(f"Traceback: {traceback.format_exc()}")
            role = ''
        
        if is_writer:
            writer_instance_id = instance_id
        elif role == 'dedicated-reader':
            dedicated_reader_instance_id = instance_id
        elif role == 'autoscaling-reader':
            auto_scaling_reader_instance_ids.append(instance_id)
        else:
            # タグがない場合、Writer以外は分類
            if not is_writer:
                if 'dedicated' in instance_id.lower() or 'dedicated-reader' in instance_id.lower():
                    dedicated_reader_instance_id = instance_id
                elif 'as-' in instance_id.lower() or 'autoscaling' in instance_id.lower():
                    auto_scaling_reader_instance_ids.append(instance_id)
                elif dedicated_reader_instance_id is None:
                    # 最初のReaderをDedicated Readerとして扱う
                    dedicated_reader_instance_id = instance_id
                else:
                    auto_scaling_reader_instance_ids.append(instance_id)
    
    logger.info(f"Found instances - Writer: {writer_instance_id}, Dedicated Reader: {dedicated_reader_instance_id}, AutoScaling Readers: {len(auto_scaling_reader_instance_ids)}")
    
    return {
        'writerInstanceId': writer_instance_id,
        'dedicatedReaderInstanceId': dedicated_reader_instance_id,
        'autoScalingReaderInstanceIds': auto_scaling_reader_instance_ids
    }

