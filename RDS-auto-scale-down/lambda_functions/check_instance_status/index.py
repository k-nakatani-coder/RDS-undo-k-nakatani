import json
import boto3
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

rds = boto3.client('rds')

def lambda_handler(event, context):

    
    # --- 入力値の取得と後方互換性の確保 ---
    instance_ids = event.get('instanceIds', [])
    if not instance_ids:
        instance_id = event.get('instanceId')
        if instance_id:
            instance_ids = [instance_id]
        else:
            logger.error("No instance IDs provided (checked 'instanceIds' and 'instanceId')")
            # Step Functions がエラーとして扱えるように例外を発生させる
            raise ValueError("No instance IDs provided")

    # ターゲットインスタンスタイプ（オプション）
    target_class = event.get('targetClass')

    logger.info(f"Checking status for instances: {instance_ids}, targetClass: {target_class}")

    results = []
    all_available = True
    all_correct_class = True

    try:
        # describe_db_instances は複数のインスタンスIDを直接指定できないため、
        # Filters パラメータを使用してフィルタリングする
        response = rds.describe_db_instances(
            Filters=[
                {
                    'Name': 'db-instance-id',
                    'Values': instance_ids
                }
            ]
        )
        
        # 取得した結果を、IDをキーにした辞書に格納し直す（後で使いやすくするため）
        instance_map = {inst['DBInstanceIdentifier']: inst for inst in response['DBInstances']}

        # --- メモリ上のデータ（辞書）を使ってループ処理 ---
        for instance_id in instance_ids:
            
            # APIの応答にインスタンスIDが含まれているか確認
            if instance_id not in instance_map:
                logger.warning(f"Instance {instance_id} not found in describe_db_instances response.")
                all_available = False # 状況が不明なため
                results.append({
                    'instanceId': instance_id, 
                    'status': 'not_found', 
                    'available': False
                })
            else:
                # メモリ上のマップからインスタンス情報を取得
                instance = instance_map[instance_id]
                status = instance['DBInstanceStatus']
                instance_class = instance['DBInstanceClass']
                
                # インスタンスタイプがターゲットと一致しているかチェック
                correct_class = True
                if target_class:
                    correct_class = (instance_class == target_class)
                    if not correct_class:
                        all_correct_class = False
                        logger.warning(f"Instance {instance_id} class mismatch: expected {target_class}, got {instance_class}")
                
                instance_result = {
                    'instanceId': instance_id,
                    'status': status,
                    'instanceClass': instance_class,
                    'available': status == 'available',
                    'correctClass': correct_class
                }
                
                # 1つでも 'available' でなければ、マスターフラグを False にする
                if status != 'available':
                    all_available = False
                
                # ターゲットタイプが指定されている場合、タイプが一致していない場合も False にする
                if target_class and not correct_class:
                    all_available = False
                    
                results.append(instance_result)
                logger.info(f"Checked Instance {instance_id}: status={status}, class={instance_class}, correctClass={correct_class}")

        return {
            'instances': results,
            'allAvailable': all_available,
            'allCorrectClass': all_correct_class if target_class else True,
            'checkedCount': len(results)
        }

    except ClientError as e:
        logger.error(f"AWS Client Error describing instances {instance_ids}: {str(e)}")
        # Step Functions がエラーとして扱えるように例外を発生させる
        raise e
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        raise e