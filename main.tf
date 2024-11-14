provider "aws" {
    region = "ap-northeast-2"
}

# IAM 역할 (EC2가 S3에 접근 가능)
resource "aws_iam_role" "ec2_role" {
    name = "ec2_access_role"
    assume_role_policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
            { 
                Action = "sts:AssumeRole",
                Principal = {
                    Service = "ec2.amazonaws.com"
                },
                Effect = "Allow"
            }
        ]
    })
}


# S3 접근 허용 정책
resource "aws_iam_policy_attachment" "s3_access" {
    name = "s3_access_attachment"
    roles = [aws_iam_role.ec2_role.name]
    policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 인스턴스 프로파일
resource "aws_iam_instance_profile" "ec2_instance_profile" {
    name = "ec2_instance_profile"
    role = aws_iam_role.ec2_role.name
}

# 버킷 생성
resource "aws_s3_bucket" "st_bucket" {
    bucket = "sqs-demo-st-bucket"
    acl = "private"

    tags = {
        key = "Name"
        value = "aws_s3_bucket"
    }
}

# 버킷 정책 추가
resource "aws_s3_bucket_policy" "st_bucket_policy" {
    bucket = aws_s3_bucket.st_bucket.id
    policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
            {
                Action = ["s3:GetObject"],
                Effect = "Allow",
                Resource = "${aws_s3_bucket.st_bucket.arn}/*",
                Principal = {
                    AWS = aws_iam_role.ec2_role.arn
                }
            }
        ]
    })
}

# 버킷에 파일 업로드
resource "aws_s3_bucket_object" "sender_file" {
    bucket = aws_s3_bucket.st_bucket.bucket
    key = "sqs_sender.py"
    source = "./sqs_sender.py"
    acl = "private"
}

resource "aws_s3_bucket_object" "receiver_file" {
    bucket = aws_s3_bucket.st_bucket.bucket
    key = "sqs_receiver.py"
    source = "./sqs_receiver.py"
    acl = "private"
}

# 시작 템플릿(worker)에서 사용할 유저데이터
data "template_file" "st_worker_userdate" {
    template = <<-EOF
                #!/bin/bash
                sudo yum update -y
                sudo yum install -y python3 pip
                sudo pip3 install boto3 --user
                sudo aws s3 cp s3://sqs-demo-st-bucket/sqs_receiver.py /home/ec2-user/sqs_receiver.py
                sudo chmod +x /home/ec2-user/sqs_receiver.py
                sudo nohup python3 /home/ec2-user/sqs_receiver.py &>/dev/null &
            EOF
}

# 인스턴스(sender)에서 사용할 유저데이터
data "template_file" "st_sender_userdate" {
    template = <<-EOF
                #!/bin/bash
                sudo yum update -y
                sudo yum install -y python3 pip
                sudo pip3 install boto3 --user
                sudo aws s3 cp s3://sqs-demo-st-bucket/sqs_sender.py /home/ec2-user/sqs_sender.py
                sudo chmod +x /home/ec2-user/sqs_sender.py
                sudo nohup python3 /home/ec2-user/sqs_sender.py &>/dev/null &
            EOF
}

# 시작 템플릿 생성
resource "aws_launch_template" "st_launch_template" {
    name_prefix = "st_launch_template-"
    image_id = "ami-00a08b445dc0ab8c1"
    instance_type = "t3.micro"
    
    network_interfaces {
        security_groups = ["sg-0bfd022dac68d928f"]
    }

    iam_instance_profile {
        name = aws_iam_instance_profile.ec2_instance_profile.name
    }

    user_data = base64encode(data.template_file.st_worker_userdate.rendered)

    tag_specifications {
        resource_type = "instance"
        tags = {
            Name = "Worker_Server"
        }
    }
}

# Auto Scaling Group 생성
resource "aws_autoscaling_group" "st_asg" {
    desired_capacity     = 1
    max_size             = 4
    min_size             = 1
    vpc_zone_identifier  = ["subnet-0bb511c0d6f762006", "subnet-0fc1ba3d67612d836"]
    launch_template {
        id      = aws_launch_template.st_launch_template.id
        version = "$Latest"
    }

    health_check_type          = "EC2"
    health_check_grace_period = 300
    force_delete               = true
    wait_for_capacity_timeout   = "0"

    lifecycle {
        ignore_changes = [desired_capacity]
    }

    tag {
        key                 = "Name"
        value               = "Worker Server"
        propagate_at_launch = true
    }
}

resource "aws_cloudwatch_metric_alarm" "sqs_message_alarm_add" {
  alarm_name          = "sqs_message_count_alarm_add"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "alarm over 10 messages in SQS"

  dimensions = {
    QueueName = "st-sqs"
  }

  # 알람 발생 시 실행할 액션을 추가합니다
  actions_enabled = true
  alarm_actions   = [aws_autoscaling_policy.scale_out_policy.arn]  # scale_out_policy 실행
}

resource "aws_cloudwatch_metric_alarm" "sqs_message_alarm_delete" {
  alarm_name          = "sqs_message_count_alarm_delete"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "alarm under 5 messages in SQS"

  dimensions = {
    QueueName = "st-sqs"
  }

  actions_enabled = true
}

resource "aws_autoscaling_policy" "scale_out_policy" {
  name                   = "scale_out_policy"
  autoscaling_group_name    = aws_autoscaling_group.st_asg.name
  policy_type             = "SimpleScaling"  # 단순 스케일링

  adjustment_type         = "ChangeInCapacity"
  scaling_adjustment     = 1  # 인스턴스를 1개 추가

  cooldown               = 300  # 쿨다운 시간 설정 (5분)
}

resource "aws_autoscaling_policy" "scale_in_policy" {
  name                   = "scale_in_policy"
  autoscaling_group_name    = aws_autoscaling_group.st_asg.name
  policy_type             = "SimpleScaling"  # 단순 스케일링

  adjustment_type         = "ChangeInCapacity"
  scaling_adjustment     = -1  # 인스턴스를 1개 제거

  cooldown               = 300  # 쿨다운 시간 설정 (5분)
}



# 퍼블릭 서브넷에 인스턴스 생성
resource "aws_instance" "public_instance" {
  ami           = aws_launch_template.st_launch_template.image_id
  instance_type = "t3.micro"
  subnet_id     = "subnet-0824c31537806aea3"
  security_groups = ["sg-0bfd022dac68d928f"]
  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  user_data = base64encode(data.template_file.st_sender_userdate.rendered)

  tags = {
    Name = "Sender Server"
  }
}
