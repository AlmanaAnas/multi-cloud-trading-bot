# modules/aws/vpc/main.tf
#
# Creates:
#   - VPC
#   - Public subnet (Internet Gateway attached)
#   - Private subnet (Lambda lives here)
#   - Internet Gateway (for Binance API calls from Lambda)
#   - Route tables for both subnets
#   - Network ACLs for private subnet
#   - Security group for Lambda
#   - VPC Endpoints: S3 (gateway, free), SSM, CloudWatch Logs, STS (interface)

data "aws_region" "current" {}

# ── VPC ───────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(var.tags, { Name = "${var.project_name}-vpc-${var.environment}" })
}

# ── Subnets ───────────────────────────────────────────────

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false  # no public IPs auto-assigned
  tags                    = merge(var.tags, { Name = "${var.project_name}-public-${var.environment}", Tier = "public" })
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.project_name}-private-${var.environment}", Tier = "private" })
}

# ── Internet Gateway ──────────────────────────────────────
# Required for Lambda to call api.binance.com
# Traffic flows: Lambda → IGW → Binance API
# (only outbound HTTPS port 443 is allowed by security group)

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.project_name}-igw-${var.environment}" })
}

# ── Route tables ──────────────────────────────────────────

# Public route table — all traffic goes to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(var.tags, { Name = "${var.project_name}-rt-public-${var.environment}" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private route table — AWS service traffic goes to VPC endpoints
# Everything else goes to IGW for Binance API
# Note: S3 gateway endpoint is added automatically via the endpoint resource
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(var.tags, { Name = "${var.project_name}-rt-private-${var.environment}" })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ── Network ACL for private subnet ────────────────────────
# Stateless — second layer of defence after security groups
# Rules are evaluated in order by number — lower number = higher priority

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private.id]
  tags       = merge(var.tags, { Name = "${var.project_name}-nacl-private-${var.environment}" })

  # Allow all outbound HTTPS - Binance API, Pub/Sub, VPC endpoints
  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow outbound ephemeral ports — return traffic acknowledgements
  egress {
    rule_no    = 110
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Deny all other outbound
  egress {
    rule_no    = 32766
    action     = "deny"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  # Allow inbound ephemeral ports — response traffic from Binance / AWS APIs
  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Deny all other inbound — Lambda should never receive traffic
  ingress {
    rule_no    = 32766
    action     = "deny"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

# ── Security Group for Lambda ──────────────────────────────
# Stateful — return traffic is automatically allowed
# Lambda only calls outbound — no inbound rules at all

resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-lambda-sg-${var.environment}"
  description = "Lambda function - outbound HTTPS only"
  vpc_id      = aws_vpc.main.id
  tags        = merge(var.tags, { Name = "${var.project_name}-lambda-sg-${var.environment}" })
}

# Allow all outbound HTTPS — Binance API, Pub/Sub, VPC endpoints
resource "aws_vpc_security_group_egress_rule" "lambda_https" {
  security_group_id = aws_security_group.lambda.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description = "Lambda function - outbound HTTPS only"
}

# ── VPC Endpoints ─────────────────────────────────────────
# These let Lambda reach AWS services WITHOUT going through NAT Gateway
# Gateway endpoints (S3, DynamoDB) are FREE
# Interface endpoints (SSM, CloudWatch, STS) have a small hourly cost

# S3 Gateway Endpoint — FREE
# Lambda uses this for Terraform state bucket access
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = merge(var.tags, { Name = "${var.project_name}-ep-s3-${var.environment}" })
}

# SSM Interface Endpoint — Lambda reads secrets from Parameter Store
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.lambda.id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.project_name}-ep-ssm-${var.environment}" })
}

# CloudWatch Logs Interface Endpoint — Lambda logs stay private
resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.lambda.id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.project_name}-ep-logs-${var.environment}" })
}

# STS Interface Endpoint — Lambda exchanges AWS identity for GCP token
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.lambda.id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.project_name}-ep-sts-${var.environment}" })
}