import boto3
import random
import time

# SQS 클라이언트 생성
sqs = boto3.client('sqs', region_name='ap-northeast-2')

# SQS 큐 URL
queue_url = 'https://sqs.ap-northeast-2.amazonaws.com/323974325951/st-sqs'

# 메시지 전송 함수
def send_messages_with_random_delay():
    message_count = 1
    while True:
        # 1초에서 15초 사이의 랜덤한 지연 시간
        delay = random.uniform(1, 15)
        time.sleep(delay)  # 지연 시간 동안 대기

        # "Hello SQS" 메시지 전송
        response = sqs.send_message(
            QueueUrl=queue_url,
            MessageBody="Hello SQS"
        )

        # 메시지 전송 완료 출력
        print(f"메시지 {message_count} 전송 완료. Message ID:", response['MessageId'])
        message_count += 1

# 메시지 전송 시작
send_messages_with_random_delay()
