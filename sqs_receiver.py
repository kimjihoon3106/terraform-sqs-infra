import boto3
import random
import time

sqs = boto3.client('sqs', region_name='ap-northeast-2')

queue_url = 'https://sqs.ap-northeast-2.amazonaws.com/323974325951/st-sqs'

def receive_messages_with_random_delay():
    while True:
        delay = random.uniform(15, 30)
        time.sleep(delay)

        response = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=10
        )
        
        messages = response.get('Messages', [])
        if messages:
            for message in messages:
                print("Message ID:", message['MessageId'])
                print("Body:", message['Body'])

                sqs.delete_message(
                    QueueUrl=queue_url,
                    ReceiptHandle=message['ReceiptHandle']
                )
                print("메시지를 삭제했습니다.")
        else:
            print("대기열에 메시지가 없습니다.")

receive_messages_with_random_delay()
