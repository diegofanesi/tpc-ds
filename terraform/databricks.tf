# =============================================================================
# Databricks Unity Catalog Resources
#
# Creation order:
#   1. storage_credential (with pre-computed IAM role ARN; role doesn't exist yet)
#   2. aws_iam_role.databricks_uc      (in aws.tf; trust reads credential.external_id)
#   3. catalog + schema
#   4. external_location               (validates IAM role trust — gated by time_sleep)
#   5. volume
# =============================================================================

resource "databricks_storage_credential" "tpcds" {
  name = "${var.project_prefix}_storage_credential"

  aws_iam_role {
    role_arn = local.databricks_role_arn
  }

  comment = "Storage credential for TPC-DS benchmarking S3 bucket"
}

resource "databricks_catalog" "tpcds" {
  name    = var.databricks_catalog
  comment = "TPC-DS benchmarking catalog"
}

resource "databricks_schema" "tpcds" {
  catalog_name = databricks_catalog.tpcds.name
  name         = var.databricks_schema
  comment      = "TPC-DS benchmarking schema"
}

resource "databricks_external_location" "tpcds" {
  name            = "${var.project_prefix}_external_location"
  url             = "s3://${aws_s3_bucket.tpcds_data.id}/"
  credential_name = databricks_storage_credential.tpcds.name
  comment         = "External location for TPC-DS benchmarking data"

  depends_on = [time_sleep.wait_for_databricks_iam]
}

resource "databricks_volume" "tpcds_raw_data" {
  name             = var.databricks_volume_name
  catalog_name     = databricks_catalog.tpcds.name
  schema_name      = databricks_schema.tpcds.name
  volume_type      = "EXTERNAL"
  storage_location = "s3://${aws_s3_bucket.tpcds_data.id}/"
  comment          = "External volume containing TPC-DS raw data files"

  depends_on = [databricks_external_location.tpcds]
}
