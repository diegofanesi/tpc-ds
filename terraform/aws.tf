# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# =============================================================================
# S3 Bucket for TPC-DS Raw Data
# =============================================================================

resource "aws_s3_bucket" "tpcds_data" {
  bucket = var.s3_bucket_name

  tags = {
    Name       = var.s3_bucket_name
    Purpose    = "TPC-DS raw data storage"
    SharedWith = "Databricks and Snowflake"
  }
}

resource "aws_s3_bucket_versioning" "tpcds_data" {
  bucket = aws_s3_bucket.tpcds_data.id

  versioning_configuration {
    status = var.s3_enable_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tpcds_data" {
  bucket = aws_s3_bucket.tpcds_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tpcds_data" {
  bucket = aws_s3_bucket.tpcds_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# IAM Role ARNs (pre-computed to break the credential <-> role circular dep)
#
# Both storage credentials (Databricks UC + Snowflake integration) need the
# IAM role ARN baked into their config, and both IAM roles need the
# credential-generated external_id baked into their trust policy. We resolve
# this by pre-computing the role ARN in a local, creating the credential with
# that ARN, then creating the role afterwards with trust that references
# the credential's external_id.
# =============================================================================

locals {
  databricks_role_name = "${var.project_prefix}-databricks-uc-${var.environment}"
  databricks_role_arn  = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.databricks_role_name}"

  snowflake_role_name = "${var.project_prefix}-snowflake-external-${var.environment}"
  snowflake_role_arn  = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.snowflake_role_name}"
}

# =============================================================================
# IAM Role for Databricks Unity Catalog (self-trusting)
#
# Created AFTER databricks_storage_credential.tpcds so the trust policy can
# read the credential-generated external_id.
# =============================================================================

resource "aws_iam_role" "databricks_uc" {
  name        = local.databricks_role_name
  description = "Self-trusting IAM role for Databricks Unity Catalog external storage"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = local.databricks_role_arn }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = databricks_storage_credential.tpcds.aws_iam_role[0].external_id
          }
        }
      }
    ]
  })

  tags = {
    Name    = local.databricks_role_name
    Purpose = "Databricks Unity Catalog storage access"
  }

  depends_on = [databricks_storage_credential.tpcds]
}

resource "aws_iam_role_policy" "databricks_uc_s3" {
  name = "databricks-uc-s3-access"
  role = aws_iam_role.databricks_uc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.tpcds_data.arn,
          "${aws_s3_bucket.tpcds_data.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = local.databricks_role_arn
      }
    ]
  })
}

# =============================================================================
# IAM Role for Snowflake External Access
#
# Created AFTER snowflake_storage_integration.tpcds so the trust policy can
# read the integration-generated principal ARN and external ID. The external
# volume reuses this same role + external_id (see snowflake.tf).
#
# S3 policy includes Put/Delete so the managed-Iceberg external volume can
# write Iceberg data and metadata under iceberg/ prefix.
# =============================================================================

resource "aws_iam_role" "snowflake_external" {
  name        = local.snowflake_role_name
  description = "IAM role for Snowflake external storage access (stage reads + Iceberg writes)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = snowflake_storage_integration.tpcds.storage_aws_iam_user_arn }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = snowflake_storage_integration.tpcds.storage_aws_external_id
        }
      }
    }]
  })

  tags = {
    Name    = local.snowflake_role_name
    Purpose = "Snowflake external storage access"
  }

  depends_on = [snowflake_storage_integration.tpcds]
}

resource "aws_iam_role_policy" "snowflake_external_s3" {
  name = "snowflake-s3-access"
  role = aws_iam_role.snowflake_external.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.tpcds_data.arn,
          "${aws_s3_bucket.tpcds_data.arn}/*"
        ]
      }
    ]
  })
}

# Wait for IAM eventual consistency before resources that validate the role
resource "time_sleep" "wait_for_databricks_iam" {
  depends_on = [
    aws_iam_role.databricks_uc,
    aws_iam_role_policy.databricks_uc_s3
  ]
  create_duration = "20s"
}

resource "time_sleep" "wait_for_snowflake_iam" {
  depends_on = [
    aws_iam_role.snowflake_external,
    aws_iam_role_policy.snowflake_external_s3
  ]
  create_duration = "20s"
}

# =============================================================================
# S3 Bucket Policy
# =============================================================================

resource "aws_s3_bucket_policy" "tpcds_data" {
  bucket = aws_s3_bucket.tpcds_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DatabricksAccess"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.databricks_uc.arn }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.tpcds_data.arn,
          "${aws_s3_bucket.tpcds_data.arn}/*"
        ]
      },
      {
        Sid       = "SnowflakeAccess"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.snowflake_external.arn }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.tpcds_data.arn,
          "${aws_s3_bucket.tpcds_data.arn}/*"
        ]
      }
    ]
  })

  depends_on = [
    time_sleep.wait_for_databricks_iam,
    time_sleep.wait_for_snowflake_iam
  ]
}
