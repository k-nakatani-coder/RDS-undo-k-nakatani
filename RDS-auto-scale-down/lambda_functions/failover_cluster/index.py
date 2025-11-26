import json
import boto3
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

rds = boto3.client('rds')

def lambda_handler(event, context):
    """
    Auroraクラスターを指定したインスタンスにフェイルオーバーする
    """
    try:
        target_instance_id = event.get('targetInstanceId')
        cluster_identifier = event.get('clusterIdentifier')
        
        if not target_instance_id or not cluster_identifier:
            logger.error("Missing required parameters: targetInstanceId or clusterIdentifier")
            raise ValueError("Missing required parameters: targetInstanceId or clusterIdentifier")
        
        logger.info(f"Attempting to failover cluster {cluster_identifier} to instance {target_instance_id}")
        
        # ターゲットインスタンスのARNを取得
        response = rds.describe_db_instances(
            DBInstanceIdentifier=target_instance_id
        )
        
        target_instance_arn = response['DBInstances'][0]['DBInstanceArn']
        current_status = response['DBInstances'][0]['DBInstanceStatus']
        
        # インスタンスが利用可能でない場合はエラー
        # 停止状態から起動した場合、availableになるまで時間がかかる可能性がある
        if current_status != 'available':
            logger.warning(f'Target instance {target_instance_id} is not available. Current status: {current_status}. This may happen if the instance is starting up from a stopped state.')
            raise Exception(f'Target instance {target_instance_id} is not available. Current status: {current_status}. Please wait for the instance to become available before retrying.')
        
        # フェイルオーバーを実行
        failover_response = rds.failover_db_cluster(
            DBClusterIdentifier=cluster_identifier,
            TargetDBInstanceIdentifier=target_instance_id
        )
        
        logger.info(f"Successfully initiated failover of cluster {cluster_identifier} to instance {target_instance_id}")
        
        return {
            'message': f'Successfully initiated failover to {target_instance_id}',
            'clusterIdentifier': cluster_identifier,
            'targetInstanceId': target_instance_id,
            'status': 'failing-over'
        }
        
    except ClientError as e:
        logger.error(f"AWS Client Error: {str(e)}")
        raise e
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        raise e

