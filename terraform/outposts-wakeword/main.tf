data "aws_partition" "current" {}

data "aws_ami" "gpu" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [var.ami_name_pattern]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  resolved_ami_id = coalesce(var.ami_id, try(data.aws_ami.gpu[0].id, null))
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "Ec2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = var.name
  }
}

resource "aws_subnet" "outpost" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.outpost_subnet_cidr
  availability_zone       = var.availability_zone
  outpost_arn             = var.outpost_arn
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-outpost"
  }
}

resource "aws_route_table" "outpost" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-outpost"
  }
}

resource "aws_route_table_association" "outpost" {
  subnet_id      = aws_subnet.outpost.id
  route_table_id = aws_route_table.outpost.id
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.outpost.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route" "on_premises" {
  count = var.local_gateway_id != null && var.on_premises_cidr != null ? 1 : 0

  route_table_id         = aws_route_table.outpost.id
  destination_cidr_block = var.on_premises_cidr
  local_gateway_id       = var.local_gateway_id
}

resource "aws_security_group" "training" {
  name_prefix = "${var.name}-"
  description = "No-ingress security group for the SSM-managed wake-word trainer"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "All traffic from admin IP"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["136.63.51.188/32"]
  }

  egress {
    description = "Outbound access for SSM, package repositories, GitHub, and training datasets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.name
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "training" {
  name_prefix        = "${var.name}-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = var.name
  }
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.training.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# --- S3 cache bucket and access policy (optional) ---

resource "aws_s3_bucket" "cache" {
  count  = var.cache_bucket_name != null ? 1 : 0
  bucket = var.cache_bucket_name

  tags = {
    Name = "${var.name}-cache"
  }
}

resource "aws_s3_bucket_versioning" "cache" {
  count  = var.cache_bucket_name != null ? 1 : 0
  bucket = aws_s3_bucket.cache[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cache" {
  count  = var.cache_bucket_name != null ? 1 : 0
  bucket = aws_s3_bucket.cache[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cache" {
  count  = var.cache_bucket_name != null ? 1 : 0
  bucket = aws_s3_bucket.cache[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "s3_cache_access" {
  count = var.cache_bucket_name != null ? 1 : 0

  statement {
    sid    = "ListCacheBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.cache[0].arn]
  }

  statement {
    sid    = "ReadWriteCacheObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.cache[0].arn}/*"]
  }
}

resource "aws_iam_role_policy" "s3_cache_access" {
  count  = var.cache_bucket_name != null ? 1 : 0
  name   = "${var.name}-s3-cache"
  role   = aws_iam_role.training.id
  policy = data.aws_iam_policy_document.s3_cache_access[0].json
}

resource "aws_iam_instance_profile" "training" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.training.name

  tags = {
    Name = var.name
  }
}

resource "aws_instance" "training" {
  ami                         = local.resolved_ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.outpost.id
  vpc_security_group_ids      = [aws_security_group.training.id]
  iam_instance_profile        = aws_iam_instance_profile.training.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    cache_bucket_name = var.cache_bucket_name != null ? var.cache_bucket_name : ""
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_type           = "gp2"
    volume_size           = var.root_volume_size_gib
    encrypted             = true
    kms_key_id            = var.root_volume_kms_key_id
    delete_on_termination = true
  }

  tags = {
    Name = var.name
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_managed_instance_core
  ]
}
