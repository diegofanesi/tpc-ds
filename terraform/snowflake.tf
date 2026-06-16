# =============================================================================
# Snowflake Database (with DB-level default external volume for Iceberg)
# =============================================================================

resource "snowflake_database" "tpcds" {
  name            = var.snowflake_database_name
  external_volume = snowflake_external_volume.tpcds_iceberg.name
  comment         = "TPC-DS benchmarking database"
}

resource "snowflake_schema" "tpcds" {
  database = snowflake_database.tpcds.name
  name     = var.snowflake_schema_name
  comment  = "TPC-DS benchmarking schema"
}

# =============================================================================
# Storage Integration for S3 Access (stage + external volume share its IAM role)
# =============================================================================

resource "snowflake_storage_integration" "tpcds" {
  name = "${upper(var.project_prefix)}_S3_INTEGRATION"

  type    = "EXTERNAL_STAGE"
  enabled = true

  storage_provider          = "S3"
  storage_aws_role_arn      = local.snowflake_role_arn
  storage_allowed_locations = ["s3://${aws_s3_bucket.tpcds_data.id}/"]

  comment = "Storage integration for TPC-DS S3 bucket"

  depends_on = [aws_s3_bucket.tpcds_data]
}

# =============================================================================
# External Volume for managed-Iceberg tables
#
# Reuses the storage integration's IAM role + external_id. The role's trust
# policy accepts that external_id regardless of whether it's presented by
# the integration or the external volume.
# =============================================================================

resource "snowflake_external_volume" "tpcds_iceberg" {
  name         = "tpcds_iceberg_volume"
  allow_writes = true

  storage_location {
    storage_location_name   = "tpcds_iceberg_s3"
    storage_provider        = "S3"
    storage_base_url        = "s3://${aws_s3_bucket.tpcds_data.id}/${var.iceberg_s3_prefix}"
    storage_aws_role_arn    = local.snowflake_role_arn
    storage_aws_external_id = snowflake_storage_integration.tpcds.storage_aws_external_id
  }

  comment = "External volume for TPC-DS managed-Iceberg tables"

  depends_on = [time_sleep.wait_for_snowflake_iam]
}

# =============================================================================
# File Format for TPC-DS CSV Files
# =============================================================================

resource "snowflake_file_format" "tpcds_csv" {
  name     = "${upper(var.project_prefix)}_CSV_FORMAT"
  database = snowflake_database.tpcds.name
  schema   = snowflake_schema.tpcds.name

  format_type = "CSV"

  field_delimiter                = "|"
  record_delimiter               = "\\n"
  skip_header                    = 0
  field_optionally_enclosed_by   = "NONE"
  escape                         = "NONE"
  escape_unenclosed_field        = "NONE"
  compression                    = "NONE"
  error_on_column_count_mismatch = false # TPC-DS dsdgen produces a trailing pipe delimiter
  replace_invalid_characters     = true  # dsdgen may emit non-UTF8 characters
  null_if                        = [""]

  comment = "CSV file format for TPC-DS data (pipe-delimited)"
}

# =============================================================================
# External Stage (backs @TPCDS_EXTERNAL_STAGE used by JMeter COPY INTO)
# =============================================================================

resource "snowflake_stage" "tpcds" {
  name     = "${upper(var.project_prefix)}_EXTERNAL_STAGE"
  database = snowflake_database.tpcds.name
  schema   = snowflake_schema.tpcds.name

  url                 = "s3://${aws_s3_bucket.tpcds_data.id}/"
  storage_integration = snowflake_storage_integration.tpcds.name
  file_format         = "FORMAT_NAME = ${snowflake_database.tpcds.name}.${snowflake_schema.tpcds.name}.${snowflake_file_format.tpcds_csv.name}"

  comment = "External stage for TPC-DS S3 bucket"

  depends_on = [time_sleep.wait_for_snowflake_iam]
}

# =============================================================================
# Grants to the customer-managed service role
# =============================================================================

resource "snowflake_grant_privileges_to_account_role" "integration_usage" {
  account_role_name = var.snowflake_service_role
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "INTEGRATION"
    object_name = snowflake_storage_integration.tpcds.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "external_volume_usage" {
  account_role_name = var.snowflake_service_role
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "EXTERNAL VOLUME"
    object_name = snowflake_external_volume.tpcds_iceberg.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "database_usage" {
  account_role_name = var.snowflake_service_role
  privileges        = ["USAGE", "CREATE SCHEMA"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.tpcds.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "schema_privileges" {
  account_role_name = var.snowflake_service_role
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]

  on_schema {
    schema_name = "\"${snowflake_database.tpcds.name}\".\"${snowflake_schema.tpcds.name}\""
  }
}
