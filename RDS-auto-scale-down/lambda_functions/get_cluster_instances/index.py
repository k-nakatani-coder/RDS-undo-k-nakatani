import json
import boto3
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

rds = boto3.client('rds')

def lambda_handler(event, context):
    """
    クラスターから現在のインスタンスを取得する
    Writer、Dedicated Reader、AutoScaling Readerを分類して返す
    """
    try:
        cluster_identifier = event.get('clusterIdentifier')
        
        if not cluster_identifier:
            logger.error("Missing required parameter: clusterIdentifier")
            raise ValueError("Missing required parameter: clusterIdentifier")
        
        logger.info(f"Getting instances for cluster: {cluster_identifier}")
        
        # クラスターのインスタンスを取得
        response = rds.describe_db_clusters(
            DBClusterIdentifier=cluster_identifier
        )
        
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
        instances_response = rds.describe_db_instances(
            Filters=[
                {
                    'Name': 'db-instance-id',
                    'Values': instance_ids
                }
            ]
        )
        
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
            except Exception as e:
                logger.warning(f"Failed to get tags for {instance_id}: {str(e)}")
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
        
    except ClientError as e:
        logger.error(f"AWS Client Error: {str(e)}")
        raise e
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        raise e

