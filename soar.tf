# Enable detections & aggregation
# Enable GuardDuty
resource "aws_guardduty_detector" "this" { enable = true }

# Enable Macie
resource "aws_macie2_account" "this" {
  finding_publishing_frequency = "FIFTEEN_MINUTES"
  status                       = "ENABLED"
}

# Enable Security Hub
resource "aws_securityhub_account" "this" {}

# Enable AWS Foundational Security Best Practices standard
resource "aws_securityhub_standards_subscription" "afs" {
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

# SNS: notify me through email and lambda when SOAR finds something interesting
resource "aws_sns_topic" "soar" {
  name = "nca-soar-alerts"
  tags = var.tags
}

# Subscribe my email to the SNS topic
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.soar.arn
  protocol  = "email"
  endpoint  = var.soc_email
}

# Evidence bucket
resource "aws_s3_bucket" "soar_evidence" {
  bucket        = "nca-soar-evidence-131464424832-eu-central-1"
  force_destroy = true
  tags          = merge(var.tags, { Purpose = "soar-evidence" })
}
# Enable versioning for the evidence bucket so that evidence is not accidentally deleted
resource "aws_s3_bucket_versioning" "evidence" {
  bucket = aws_s3_bucket.soar_evidence.id
  versioning_configuration { status = "Enabled" }
}
# Enable server-side encryption  for the evidence bucket so that evidence is encrypted
resource "aws_s3_bucket_server_side_encryption_configuration" "evidence" {
  bucket = aws_s3_bucket.soar_evidence.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# Lambda: isolate EC2 + deregister from ALB + write evidence + tag
data "archive_file" "soar_zip" {
  type        = "zip"
  output_path = "${path.module}/soar_handler.zip"
  source {
    filename = "lambda_function.py"
    content  = <<EOF
import boto3, json, os, datetime

ec2 = boto3.client('ec2')
elb = boto3.client('elbv2')
s3  = boto3.client('s3')
sns = boto3.client('sns')

QUARANTINE_SG    = os.environ['QUARANTINE_SG']
EVIDENCE_BUCKET  = os.environ['EVIDENCE_BUCKET']
TARGET_GROUP_ARN = os.environ.get('TARGET_GROUP_ARN', '')
SNS_TOPIC_ARN    = os.environ.get('SNS_TOPIC_ARN', '')

def _instance_ids_from_event(event):
    ids = set()
    for f in event.get("detail", {}).get("findings", []):
        for r in f.get("Resources", []):
            if r.get("Type") == "AwsEc2Instance":
                rid = r.get("Id", "")
                if ":instance/" in rid:
                    ids.add(rid.split(":instance/")[-1])
                elif rid.startswith("i-"):
                    ids.add(rid)
            det = r.get("Details", {}).get("AwsEc2Instance", {})
            if isinstance(det, dict) and det.get("InstanceId"):
                ids.add(det["InstanceId"])
    return list(ids)

def _all_enis(instance_id):
    res = ec2.describe_instances(InstanceIds=[instance_id])
    enis = []
    for r in res.get("Reservations", []):
        for inst in r.get("Instances", []):
            for ni in inst.get("NetworkInterfaces", []):
                enis.append(ni["NetworkInterfaceId"])
    return enis

def _apply_isolation(eni_id):
    ec2.modify_network_interface_attribute(
        NetworkInterfaceId=eni_id,
        Groups=[QUARANTINE_SG]
    )

def _deregister_from_tg(instance_id):
    if not TARGET_GROUP_ARN:
        return
    try:
        elb.deregister_targets(
            TargetGroupArn=TARGET_GROUP_ARN,
            Targets=[{"Id": instance_id}]
        )
    except Exception as e:
        print(f"TargetGroup deregister warn for {instance_id}: {e}")

def _tag_quarantined(instance_id, reason):
    try:
        safe = (reason or "").replace("\n"," ").replace("\r"," ").replace("\t"," ")[:200]
        ec2.create_tags(Resources=[instance_id], Tags=[
            {"Key": "Quarantined", "Value": "true"},
            {"Key": "QuarantineReason", "Value": safe}
        ])
    except Exception as e:
        print(f"Tag warn for {instance_id}: {e}")

def _send_notification(summary):
    if not SNS_TOPIC_ARN:
        print("SNS_TOPIC_ARN not set; skipping notification")
        return
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=(f"SOAR Alert: {summary.get('Title','(no title)')} "
                     f"({summary.get('Severity','UNKNOWN')})")[:100],
            Message=json.dumps(summary, indent=2)
        )
    except Exception as e:
        print(f"SNS publish error: {e}")

def handler(event, context):
    ts = datetime.datetime.utcnow().isoformat() + "Z"

    # Store full event as evidence
    key = f"securityhub/{ts}.json"
    s3.put_object(
        Bucket=EVIDENCE_BUCKET, Key=key,
        Body=json.dumps(event, indent=2).encode("utf-8"),
        ContentType="application/json"
    )

    findings = event.get("detail", {}).get("findings", [])
    f0 = findings[0] if findings else {}
    title = f0.get("Title", "")
    severity = (f0.get("Severity") or {}).get("Label", "UNKNOWN")

    ids = _instance_ids_from_event(event)
    isolated = []

    if not ids:
        summary = {
            "Time": ts,
            "FindingId": f0.get("Id", ""),
            "Title": title,
            "Severity": severity,
            "Region": event.get("region", ""),
            "Instances": [],
            "EvidenceS3Key": key,
            "Status": "No EC2 – no isolation"
        }
        _send_notification(summary)
        return {"status": "noop", "evidence_key": key}

    for iid in ids:
        try:
            enis = _all_enis(iid)
            for eni in enis:
                _apply_isolation(eni)
            _deregister_from_tg(iid)
            _tag_quarantined(iid, title)
            isolated.append({"instance": iid, "enis": enis})
        except Exception as e:
            print(f"Quarantine error for {iid}: {e}")

    summary = {
        "Time": ts,
        "FindingId": f0.get("Id", ""),
        "Title": title,
        "Severity": severity,
        "Region": event.get("region", ""),
        "Instances": ids,
        "EvidenceS3Key": key,
        "Status": "Isolated" if isolated else "No action"
    }
    _send_notification(summary)

    return {"status": "ok", "evidence_key": key, "isolated": isolated}
`
EOF
  }
}
# this role ensures the lambda function has the right permissions
resource "aws_iam_role" "soar_fn" {
  name = "nca-soar-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect="Allow", Principal={ Service="lambda.amazonaws.com" }, Action="sts:AssumeRole"}]
  })
  tags = var.tags
}

resource "aws_iam_policy" "soar_fn" {
  name = "nca-soar-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [ #allow lambda describe and modify enis
      { Effect="Allow", Action:[
          "ec2:DescribeInstances","ec2:DescribeNetworkInterfaces",
          "ec2:ModifyNetworkInterfaceAttribute","ec2:CreateTags"
        ], Resource:"*"
      },
      { # allow lambda to publish to sns
        "Effect": "Allow",
        "Action": ["sns:Publish"],
        "Resource": "${aws_sns_topic.soar.arn}"
      },
      { #allow lambda to deregister from target group
        Effect="Allow", 
        Action:[
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth"
        ], Resource:"*"
      },
      { # allow lambda to write evidence to s3
        Effect="Allow", Action:["s3:PutObject"], Resource:["${aws_s3_bucket.soar_evidence.arn}/*"] },
      { # allow lambda to write logs to cloudwatch
        Effect="Allow", Action:[
          "logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"
        ], Resource:"*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "soar_attach" {
  role       = aws_iam_role.soar_fn.name
  policy_arn = aws_iam_policy.soar_fn.arn
}

resource "aws_lambda_function" "soar" {
  function_name = "nca-soar-handler"
  role          = aws_iam_role.soar_fn.arn
  runtime       = "python3.12"
  handler       = "lambda_function.handler"
  filename      = data.archive_file.soar_zip.output_path
  timeout       = 60
  environment {
    variables = {
      QUARANTINE_SG    = aws_security_group.quarantine.id
      EVIDENCE_BUCKET  = aws_s3_bucket.soar_evidence.bucket
      TARGET_GROUP_ARN = aws_lb_target_group.web.arn 
       SNS_TOPIC_ARN    = aws_sns_topic.soar.arn
    }
  }
  depends_on = [aws_iam_role_policy_attachment.soar_attach]
}

# Quarantine SG for isolating instances
resource "aws_security_group" "quarantine" {
  name        = "nca-quarantine-sg"
  description = "Isolate instance (no inbound or outbound)"
  vpc_id      = aws_vpc.this.id

  # No ingress or egress rules
  ingress = []
  egress  = []
  tags = merge(var.tags, { Name = "nca-quarantine-sg", Purpose = "isolation" })
}

# CloudWatch Event Rule to trigger on GuardDuty HIGH/CRITICAL findings via Security Hub
resource "aws_cloudwatch_event_rule" "soar" {
  name        = "nca-soar-sechub"
  description = "Trigger on HIGH/CRITICAL GuardDuty findings"
  event_pattern = jsonencode({
    "source":      ["aws.securityhub"],
    "detail-type": ["Security Hub Findings - Imported"],
    "detail": {
      "findings": {
        "ProductName": [{ "prefix": "GuardDuty" }],
        "Severity":    { "Label": ["HIGH", "CRITICAL"] }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "to_lambda" {
  rule      = aws_cloudwatch_event_rule.soar.name
  target_id = "soar-lambda"
  arn       = aws_lambda_function.soar.arn
}


resource "aws_lambda_permission" "events_invoke" {
  statement_id  = "AllowEventsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.soar.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.soar.arn
}