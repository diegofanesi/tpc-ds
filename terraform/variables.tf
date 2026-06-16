# =============================================================================
# General Variables
# =============================================================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "tpcds"
}

# =============================================================================
# Provider Profiles (customer-managed credentials)
# =============================================================================

variable "aws_profile" {
  description = "AWS CLI profile name (from ~/.aws/credentials or SSO cache)"
  type        = string
}

variable "databricks_profile" {
  description = "Databricks CLI profile name (from ~/.databrickscfg)"
  type        = string
}

variable "snowflake_profile" {
  description = "Snowflake CLI profile name (from ~/.snowflake/config.toml)"
  type        = string
}

# =============================================================================
# AWS Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "Name of S3 bucket for TPC-DS raw data (must be globally unique)"
  type        = string
}

variable "s3_enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "iceberg_s3_prefix" {
  description = "S3 prefix under the bucket where Snowflake writes managed-Iceberg data"
  type        = string
  default     = "iceberg/"
}

# =============================================================================
# Databricks Variables
# =============================================================================

variable "databricks_workspace_url" {
  description = "Databricks workspace URL (e.g., https://dbc-xxx.cloud.databricks.com)"
  type        = string
}

variable "databricks_account_id" {
  description = "Databricks account ID"
  type        = string
}

variable "databricks_catalog" {
  description = "Unity Catalog catalog name (created by terraform)"
  type        = string
  default     = "tpcds_sf_catalog"
}

variable "databricks_schema" {
  description = "Unity Catalog schema name (created by terraform)"
  type        = string
  default     = "tpcds"
}

variable "databricks_volume_name" {
  description = "Name of the external volume for TPC-DS data"
  type        = string
  default     = "tpcds_raw_data"
}

# =============================================================================
# Snowflake Variables
# =============================================================================

variable "snowflake_organization" {
  description = "Snowflake organization name (found in account URL: orgname-accountname)"
  type        = string
}

variable "snowflake_account" {
  description = "Snowflake account name within organization (found in account URL: orgname-accountname)"
  type        = string
}

variable "snowflake_database_name" {
  description = "Name of the Snowflake database for TPC-DS"
  type        = string
  default     = "TPCDS"
}

variable "snowflake_schema_name" {
  description = "Name of the Snowflake schema for TPC-DS"
  type        = string
  default     = "BENCHMARK"
}

variable "snowflake_user" {
  description = "Snowflake service account username (customer-managed; referenced by config.json)"
  type        = string
}

variable "snowflake_service_role" {
  description = "Snowflake role that runs the benchmark. Receives grants on integration/DB/schema/volume."
  type        = string
  default     = "SYSADMIN"
}
