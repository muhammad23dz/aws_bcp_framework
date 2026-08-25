terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.primary_region
  alias  = "primary"
}

provider "aws" {
  region = var.dr_region
  alias  = "dr"
}

# Primary S3 Bucket
resource "aws_s3_bucket" "primary" {
  provider = aws.primary
  bucket   = "${var.bucket_prefix}-primary-${var.primary_region}"

  tags = {
    Criticality = var.criticality
    RTO         = var.rto
    RPO         = var.rpo
    DR-Region   = var.dr_region
    Purpose     = "Production"
    Environment = var.environment
  }
}

# Primary Bucket Versioning
resource "aws_s3_bucket_versioning" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Primary Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Primary Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DR Region S3 Bucket (Replica)
resource "aws_s3_bucket" "replica" {
  provider = aws.dr
  bucket   = "${var.bucket_prefix}-replica-${var.dr_region}"

  tags = {
    Criticality = var.criticality
    Purpose     = "DR-Replica"
    Environment = var.environment
  }
}

# Replica Bucket Versioning
resource "aws_s3_bucket_versioning" "replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.replica.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Replica Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Replica Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role for Replication
resource "aws_iam_role" "replication" {
  provider = aws.primary
  name     = "${var.bucket_prefix}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Purpose = "DR-Replication"
  }
}

# Replication Policy
resource "aws_iam_policy" "replication" {
  provider = aws.primary
  name     = "${var.bucket_prefix}-s3-replication-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # The replication role only needs to READ the replication configuration
        # and bucket versioning from the source bucket — NOT modify them.
        # Removing s3:PutReplicationConfiguration (least-privilege fix).
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:GetBucketVersioning"
        ]
        Resource = aws_s3_bucket.primary.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = [
          aws_s3_bucket.primary.arn,
          "${aws_s3_bucket.primary.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:GetBucketVersioning"
          # Removed s3:PutBucketVersioning — versioning on replica is managed
          # by Terraform (aws_s3_bucket_versioning.replica), not this role.
        ]
        Resource = [
          aws_s3_bucket.replica.arn,
          "${aws_s3_bucket.replica.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication" {
  provider   = aws.primary
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

# Replication Configuration
resource "aws_s3_bucket_replication_configuration" "primary" {
  provider = aws.primary
  role     = aws_iam_role.replication.arn
  bucket   = aws_s3_bucket.primary.id

  rule {
    id     = "DR-Replication-Rule"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = "STANDARD"
      account       = var.account_id
    }

    delete_marker_replication {
      status = "Enabled"
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.primary,
    aws_s3_bucket_versioning.replica
  ]
}
