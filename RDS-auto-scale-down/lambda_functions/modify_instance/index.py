import json
import boto3
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

rds = boto3.client('rds')

def lambda_handler(event, context):
    """
    RDSインスタンスのインスタンスタイプを変更する
    Step Functions からの直接呼び出しを想定
    """
    try:
        instance_id = event.get('instanceId')
        target_class = event.get('targetClass')
        
        if not instance_id or not target_class:
            logger.error("Missing required parameters: instanceId or targetClass")
            # Step Functions がエラーとして扱えるように例外を発生させる
            raise ValueError("Missing required parameters: instanceId or targetClass")
            
        apply_immediately = event.get('applyImmediately', True)

        logger.info(f"Attempting to modify instance {instance_id} to {target_class} (ApplyImmediately={apply_immediately})")
        
        # インスタンスの現在の状態を確認
        response = rds.describe_db_instances(
            DBInstanceIdentifier=instance_id
        )
        
        instance_info = response['DBInstances'][0]
        current_status = instance_info['DBInstanceStatus']
        current_class = instance_info['DBInstanceClass']
        
        # deleting 状態の場合はスキップ（既に削除されるため）
        if current_status == 'deleting':
            logger.info(f'Instance {instance_id} is being deleted. Skipping modification. Current status: {current_status}')
            return {
                'message': f'Instance {instance_id} is being deleted, skipping modification',
                'instanceId': instance_id,
                'status': 'deleting',
                'currentClass': current_class,
                'targetClass': target_class,
                'skipped': True
            }
        
        # modifying 状態の場合は既に変更が進行中なので、成功として扱う
        if current_status == 'modifying':
            logger.info(f'Instance {instance_id} is already being modified. Current status: {current_status}')
            return {
                'message': f'Instance {instance_id} is already being modified',
                'instanceId': instance_id,
                'status': 'modifying',
                'currentClass': current_class,
                'targetClass': target_class
            }
        
        # available 以外の状態（rebooting, backing-up など）の場合はエラー
        if current_status != 'available':
            logger.warning(f'Instance {instance_id} is not available. Current status: {current_status}')
            # 変更不可なので、後でリトライできるようにエラーを返す
            raise Exception(f'Instance {instance_id} is not available. Current status: {current_status}')
        
        if current_class == target_class:
            logger.info(f'Instance {instance_id} is already {target_class}. No change needed.')

            return {
                'message': f'Instance {instance_id} is already {target_class}',
                'instanceId': instance_id,
                'status': 'no_change_needed'
            }
        
        # インスタンスタイプを変更
        modify_response = rds.modify_db_instance(
            DBInstanceIdentifier=instance_id,
            DBInstanceClass=target_class,
            ApplyImmediately=apply_immediately
        )
        
        logger.info(f"Successfully initiated modification of {instance_id} to {target_class}")
        
        return {
            'message': f'Successfully initiated modification of {instance_id} to {target_class}',
            'instanceId': instance_id,
            'status': 'modifying',
            'previousClass': current_class,
            'targetClass': target_class
        }
        
    except ClientError as e:
        logger.error(f"AWS Client Error: {str(e)}")
        # Step Functions がエラーとして扱えるように例外を発生させる
        raise e
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        # Step Functions がエラーとして扱えるように例外を発生させる
        raise e