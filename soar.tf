############################
# Variables
############################
variable "soc_email" { type = string }

############################
# Who am I (for bucket naming)
############################
data "aws_caller_identity" "me" {}

############################
# Evidence bucket
############################
resource "aws_s3_bucket" "soar_evidence" {
  bucket        = "${var.name}-soar-evidence-${data.aws_caller_identity.me.account_id}-${var.region}"
  force_destroy = true
  tags          = merge(var.tags, { Purpose = "soar-evidence" })
}

resource "aws_s3_bucket_versioning" "evidence" {
  bucket = aws_s3_bucket.soar_evidence.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "evidence" {
  bucket = aws_s3_bucket.soar_evidence.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

############################
# Quarantine SG for isolating instances
############################
resource "aws_security_group" "quarantine" {
  name        = "${var.name}-quarantine-sg"
  description = "Isolate instance: no inbound; allow egress"
  vpc_id      = aws_vpc.this.id

  # No ingress rules. block all inbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-quarantine-sg", Purpose = "isolation" })
}

############################
# Enable detections & aggregation
############################
resource "aws_guardduty_detector" "this" { enable = true }

# resource "aws_inspector2_enabler" "this" { # blocked by org SCP, keep disabled
#   account_ids    = [data.aws_caller_identity.me.account_id]
#   resource_types = ["EC2", "ECR", "LAMBDA"]
# }

resource "aws_macie2_account" "this" {
  finding_publishing_frequency = "FIFTEEN_MINUTES"
  status                       = "ENABLED"
}

resource "aws_securityhub_account" "this" {}

# Baseline standard subscription for Security Hub. standards are rulesets that check for best practices for security
resource "aws_securityhub_standards_subscription" "afs" {
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

############################
# SNS: notify SOC
############################
resource "aws_sns_topic" "soar" {
  name = "${var.name}-soar-alerts"
  tags = var.tags
}

resource "aws_sns_topic_policy" "soar" {
  arn = aws_sns_topic.soar.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid      = "AllowEventBridge",
      Effect   = "Allow",
      Principal= { Service = "events.amazonaws.com" },
      Action   = "sns:Publish",
      Resource = aws_sns_topic.soar.arn
    }]
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.soar.arn
  protocol  = "email"
  endpoint  = var.soc_email
}

############################
# Lambda: isolate EC2 + deregister from ALB + write evidence + tag
############################
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

QUARANTINE_SG   = os.environ['QUARANTINE_SG']
EVIDENCE_BUCKET = os.environ['EVIDENCE_BUCKET']
TARGET_GROUP_ARN = os.environ.get('TARGET_GROUP_ARN', '')

def _instance_ids_from_event(event):
    ids = set()
    for f in event.get("detail", {}).get("findings", []):
        # Primary: normalized SecurityHub resource entries
        for r in f.get("Resources", []):
            if r.get("Type") in ("AwsEc2Instance",):
                rid = r.get("Id","")
                if ":instance/" in rid:
                    ids.add(rid.split(":instance/")[-1])
                elif rid.startswith("i-"):
                    ids.add(rid)
            # Fallback path: Details.AwsEc2Instance.InstanceId
            det = r.get("Details", {}).get("AwsEc2Instance", {})
            if isinstance(det, dict) and det.get("InstanceId"):
                ids.add(det["InstanceId"])
    return list(ids)

def _primary_enis(instance_id):
    res = ec2.describe_instances(InstanceIds=[instance_id])
    enis = []
    for r in res["Reservations"]:
        for inst in r["Instances"]:
            for ni in inst.get("NetworkInterfaces", []):
                # Quarantine all attached ENIs (safer)
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
        ec2.create_tags(Resources=[instance_id], Tags=[
            {"Key": "Quarantined", "Value": "true"},
            {"Key": "QuarantineReason", "Value": (reason or "")[:200]}
        ])
    except Exception as e:
        print(f"Tag warn for {instance_id}: {e}")

def handler(event, context):
    ts = datetime.datetime.utcnow().isoformat() + "Z"
    # Store full event as evidence
    key = f"securityhub/{ts}.json"
    s3.put_object(Bucket=EVIDENCE_BUCKET, Key=key,
                  Body=json.dumps(event, indent=2).encode("utf-8"),
                  ContentType="application/json")

    ids = _instance_ids_from_event(event)
    if not ids:
        print("No EC2 instances in finding")
        return {"status":"noop","evidence_key":key}

    # Best-effort friendly title
    title = ""
    try:
        title = event["detail"]["findings"][0].get("Title","")
    except Exception:
        pass

    isolated = []
    for iid in ids:
        try:
            enis = _primary_enis(iid)
            for eni in enis:
                _apply_isolation(eni)
            _deregister_from_tg(iid)
            _tag_quarantined(iid, title)
            isolated.append({"instance": iid, "enis": enis})
        except Exception as e:
            print(f"Quarantine error for {iid}: {e}")

    return {"status":"ok","evidence_key":key,"isolated":isolated}
EOF
  }
}

resource "aws_iam_role" "soar_fn" {
  name = "${var.name}-soar-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect="Allow", Principal={ Service="lambda.amazonaws.com" }, Action="sts:AssumeRole"}]
  })
  tags = var.tags
}

resource "aws_iam_policy" "soar_fn" {
  name = "${var.name}-soar-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect="Allow", Action:[
          "ec2:DescribeInstances","ec2:DescribeNetworkInterfaces",
          "ec2:ModifyNetworkInterfaceAttribute","ec2:CreateTags"
        ], Resource:"*"
      },
      { Effect="Allow", Action:[
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth"
        ], Resource:"*"
      },
      { Effect="Allow", Action:["s3:PutObject"], Resource:["${aws_s3_bucket.soar_evidence.arn}/*"] },
      { Effect="Allow", Action:[
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
  function_name = "${var.name}-soar-handler"
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
    }
  }
  depends_on = [aws_iam_role_policy_attachment.soar_attach]
}

############################
# EventBridge: match findings → Lambda + SNS
############################
resource "aws_cloudwatch_event_rule" "soar" {
  name        = "${var.name}-soar-sechub"
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

resource "aws_cloudwatch_event_target" "to_sns" {
  rule      = aws_cloudwatch_event_rule.soar.name
  target_id = "soar-sns"
  arn       = aws_sns_topic.soar.arn
}

resource "aws_lambda_permission" "events_invoke" {
  statement_id  = "AllowEventsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.soar.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.soar.arn
}
#to add CloudWatchReadOnlyAccess policy to the soar lambda function so that it can read CloudWatch logs and then grafana can fetch metrics from there
resource "aws_iam_role_policy_attachment" "monitor_cw_read" {
  role       = aws_iam_role.monitor.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}
