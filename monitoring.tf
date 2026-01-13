# Security group for monitoring host (egress only)
resource "aws_security_group" "monitoring" {
  name        = "${var.name}-monitor-sg"
  description = "Monitoring host (Prom + Grafana)"
  vpc_id      = aws_vpc.this.id
  tags        = merge(var.tags, { Name = "${var.name}-monitor-sg" })
}

# Egress all (needed for SSM + pulling images + EC2 API)
resource "aws_security_group_rule" "monitor_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring.id
}

# IAM role/profile for monitoring instance
resource "aws_iam_role" "monitor" {
  name = "${var.name}-monitor-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ 
        Effect = "Allow", 
        Principal = {
             Service = "ec2.amazonaws.com" }, 
        Action = "sts:AssumeRole" 
        }]
  })
  tags = var.tags
}
# this policy allows the monitoring instance to use SSM 
resource "aws_iam_role_policy_attachment" "monitor_ssm" {
  role       = aws_iam_role.monitor.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
# this policy allows the monitoring instance to read EC2 metadata
resource "aws_iam_role_policy_attachment" "monitor_ec2_read" {
  role       = aws_iam_role.monitor.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "monitor" {
  name = "${var.name}-monitor-profile"
  role = aws_iam_role.monitor.name
}


# Monitoring instance
resource "aws_instance" "monitor" {
  ami                         = data.aws_ami.amazon_linux2.id
  instance_type               = "t2.micro" #changed from t3.micro to t2.micro for cost savings
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.monitoring.id]
  iam_instance_profile        = aws_iam_instance_profile.monitor.name
  associate_public_ip_address = false

 user_data = <<EOF
#!/bin/bash
set -euo pipefail

# 1) Install Docker
amazon-linux-extras enable docker || true
yum install -y docker
systemctl enable --now docker

# 2) Prometheus config (EC2 service discovery for Name=cs1nca-dev-web on 9100)
mkdir -p /opt/monitoring
cat >/opt/monitoring/prometheus.yml <<'PYAML'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node'
    ec2_sd_configs:
      - region: eu-central-1
        port: 9100
        filters:
          - name: tag:Name
            values: ["cs1nca-dev-web"]
    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        target_label: instance
PYAML

# 3) Docker network for Prometheus + Grafana
docker network create monitor || true

# 4) Run Prometheus (port 9090)
docker run -d --name prom --restart unless-stopped \
  --network monitor \
  -p 9090:9090 \
  -v /opt/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:latest

# 5) Prepare Grafana volume (fix permissions)
mkdir -p /opt/monitoring/grafana
chown -R 472:472 /opt/monitoring/grafana
chmod -R 755 /opt/monitoring/grafana

# 6) Run Grafana (port 3000) with IMDS access for CloudWatch
docker run -d --name grafana --restart unless-stopped \
  --network monitor \
  --add-host=169.254.169.254:169.254.169.254 \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=adminmo! \
  -v /opt/monitoring/grafana:/var/lib/grafana \
  grafana/grafana:latest

EOF
metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"         
    http_put_response_hop_limit = 2                  
  }
  tags = merge(var.tags, { Name = "${var.name}-monitor" })
}

# Allocate an Elastic IP in the VPC scope
resource "aws_eip" "monitor" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-monitor-eip" })
}

# Associate that EIP to the instance
resource "aws_eip_association" "monitor" {
  instance_id   = aws_instance.monitor.id
  allocation_id = aws_eip.monitor.id
}

resource "aws_security_group_rule" "web_in_node_from_monitor" { # allow Prometheus to scrape node_exporter
  type              = "ingress"
  from_port         = 9100
  to_port           = 9100
  protocol          = "tcp"
  security_group_id = aws_security_group.web.id
  cidr_blocks       = [var.vpc_cidr] 
}


#outputs
output "monitor_instance_id" { value = aws_instance.monitor.id }
output "monitor_private_ip"  { value = aws_instance.monitor.private_ip }
output "monitor_sg_id"       { value = aws_security_group.monitoring.id }


output "monitor_public_ip"   { value = aws_eip.monitor.public_ip }
output "monitor_public_dns"  { value = aws_instance.monitor.public_dns }

# Variables for monitoring instance , node exporter installation
locals {
  node_exporter_version = "1.8.1"
}

# SSM document that installs/starts node_exporter
resource "aws_ssm_document" "node_exporter_install" {
  name          = "${var.name}-install-node-exporter"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install and enable Prometheus Node Exporter"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "installNodeExporter"
      inputs = {
        runCommand = [
          "set -euxo pipefail",
          "cd /tmp",
          "curl -L -o ne.tar.gz https://github.com/prometheus/node_exporter/releases/download/v${local.node_exporter_version}/node_exporter-${local.node_exporter_version}.linux-amd64.tar.gz",
          "tar xzf ne.tar.gz",
          "sudo mv node_exporter-${local.node_exporter_version}.linux-amd64/node_exporter /usr/local/bin/",
          "sudo useradd --no-create-home --shell /sbin/nologin node_exporter || true",
          "cat >/tmp/node_exporter.service <<'UNIT'\n[Unit]\nDescription=Node Exporter\nAfter=network.target\n\n[Service]\nUser=node_exporter\nGroup=node_exporter\nType=simple\nExecStart=/usr/local/bin/node_exporter\n\n[Install]\nWantedBy=multi-user.target\nUNIT",
          "sudo mv /tmp/node_exporter.service /etc/systemd/system/node_exporter.service",
          "sudo systemctl daemon-reload",
          "sudo systemctl enable --now node_exporter",
          "sudo systemctl status node_exporter --no-pager -l || true"
        ]
      }
    }]
  })
}

# Run it on all running web instances (ASG members)
resource "aws_ssm_association" "node_exporter_install" {
  name = aws_ssm_document.node_exporter_install.name

  targets {
    key    = "tag:Name"
    values = ["cs1nca-dev-web"]
  }

}

variable "allowed_cidrs" {
  description = "CIDRs allowed to access Prometheus/Grafana"
  type        = list(string)
  default     = ["0.0.0.0/0"]   # or 145.116.0.0/16 for limited access only from Fontys
}

resource "aws_security_group_rule" "monitor_in_prom" {
  type              = "ingress"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidrs
  security_group_id = aws_security_group.monitoring.id
}

resource "aws_security_group_rule" "monitor_in_grafana" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidrs
  security_group_id = aws_security_group.monitoring.id
}

resource "aws_security_group_rule" "monitor_in_icmp" {
  type              = "ingress"
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
  cidr_blocks       = var.allowed_cidrs
  security_group_id = aws_security_group.monitoring.id
}
