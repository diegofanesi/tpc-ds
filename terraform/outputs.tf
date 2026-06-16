# =============================================================================
# AWS Outputs
# =============================================================================

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "s3_bucket_name" {
  description = "S3 bucket name for TPC-DS data"
  value       = aws_s3_bucket.tpcds_data.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.tpcds_data.arn
}

output "s3_bucket_path" {
  description = "S3 bucket path (s3:// URI)"
  value       = "s3://${aws_s3_bucket.tpcds_data.id}/"
}

output "iceberg_s3_path" {
  description = "S3 path used as the Snowflake external volume base"
  value       = "s3://${aws_s3_bucket.tpcds_data.id}/${var.iceberg_s3_prefix}"
}

output "databricks_iam_role_arn" {
  description = "IAM role ARN for Databricks Unity Catalog"
  value       = aws_iam_role.databricks_uc.arn
}

output "snowflake_iam_role_arn" {
  description = "IAM role ARN for Snowflake external access"
  value       = aws_iam_role.snowflake_external.arn
}

# =============================================================================
# Databricks Outputs
# =============================================================================

output "databricks_workspace_url" {
  description = "Databricks workspace URL"
  value       = var.databricks_workspace_url
}

output "databricks_catalog" {
  description = "Unity Catalog catalog name"
  value       = databricks_catalog.tpcds.name
}

output "databricks_schema" {
  description = "Unity Catalog schema name"
  value       = databricks_schema.tpcds.name
}

output "databricks_volume_name" {
  description = "External volume name"
  value       = databricks_volume.tpcds_raw_data.name
}

output "databricks_volume_path" {
  description = "External volume path"
  value       = databricks_volume.tpcds_raw_data.volume_path
}

# =============================================================================
# Snowflake Outputs
# =============================================================================

output "snowflake_account" {
  description = "Snowflake account identifier"
  value       = var.snowflake_account
}

output "snowflake_database" {
  description = "Snowflake database name"
  value       = snowflake_database.tpcds.name
}

output "snowflake_schema" {
  description = "Snowflake schema name"
  value       = snowflake_schema.tpcds.name
}

output "snowflake_storage_integration" {
  description = "Snowflake storage integration name"
  value       = snowflake_storage_integration.tpcds.name
}

output "snowflake_external_volume" {
  description = "Snowflake external volume name (managed-Iceberg target)"
  value       = snowflake_external_volume.tpcds_iceberg.name
}

output "snowflake_external_stage" {
  description = "Snowflake external stage name"
  value       = snowflake_stage.tpcds.name
}

# =============================================================================
# Generated config.json
#
# Rendered at ../config.json.generated with every non-secret field pre-filled.
# Two placeholders remain for the customer to fill:
#   - databricks.pat_token         (paste your Databricks PAT)
#   - snowflake.auth_key_path      (upload your RSA private key to the path below)
#
# The auth_key_path points into the UC volume created by this terraform, so the
# file is reachable from Databricks jobs running against this catalog/schema.
# =============================================================================

locals {
  account_locator = "${upper(var.snowflake_organization)}-${upper(var.snowflake_account)}"

  auth_key_path = "/Volumes/${databricks_catalog.tpcds.name}/${databricks_schema.tpcds.name}/${databricks_volume.tpcds_raw_data.name}/test_files/rsa_key.p8"

  config_json = {
    databricks = {
      catalog           = databricks_catalog.tpcds.name
      schema            = databricks_schema.tpcds.name
      volume            = databricks_volume.tpcds_raw_data.name
      pat_token         = "<PASTE_YOUR_DATABRICKS_PAT_HERE>"
      hourly_rate       = "2.00"
      optimize_strategy = "zorder"
    }
    snowflake = {
      account_locator = local.account_locator
      region          = var.aws_region
      database        = snowflake_database.tpcds.name
      schema          = snowflake_schema.tpcds.name
      staging         = snowflake_stage.tpcds.name
      role            = var.snowflake_service_role
      user            = var.snowflake_user
      auth_key_path   = local.auth_key_path
      hourly_rate     = "4.00"
    }
    mlflow = {
      experiment_name = "/TPC-DS Benchmark"
    }
    aws_region = var.aws_region
  }
}

resource "local_file" "config_json" {
  content         = jsonencode(local.config_json)
  filename        = "${path.module}/../config.json.generated"
  file_permission = "0644"
}

output "config_json_file" {
  description = "Path to the generated config.json template"
  value       = local_file.config_json.filename
}

output "next_steps" {
  description = "Post-apply checklist for the customer"
  value       = <<-EOT

    =========================================================================
    Terraform apply complete. Next steps:
    =========================================================================

    1. Copy the generated config into place:

         cp ${local_file.config_json.filename} ${abspath("${path.module}/..")}/config.json

    2. Edit ../config.json and paste your Databricks PAT:
         databricks.pat_token = "<your Databricks PAT>"

    3. Upload your Snowflake RSA private key (PKCS#8 .p8) to the UC volume:

         target path: ${local.auth_key_path}

       Easiest way from the Databricks workspace UI:
         Catalog > ${databricks_catalog.tpcds.name} > ${databricks_schema.tpcds.name}
                 > Volumes > ${databricks_volume.tpcds_raw_data.name}
                 > Create folder "test_files" (if missing)
                 > Upload rsa_key.p8

    4. Open the Databricks workspace, checkout the repo, and run notebook:
         0 - Job Setup.ipynb
       to create the TPC-DS jobs.

    5. Trigger the "TPC-DS Full Benchmark" job with your desired parameters.
    =========================================================================
  EOT
}
