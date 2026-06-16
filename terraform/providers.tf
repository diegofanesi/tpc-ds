provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "TPC-DS-Benchmark"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

provider "databricks" {
  host    = var.databricks_workspace_url
  profile = var.databricks_profile
}

provider "snowflake" {
  organization_name = var.snowflake_organization
  account_name      = var.snowflake_account
  profile           = var.snowflake_profile

  preview_features_enabled = [
    "snowflake_storage_integration_resource",
    "snowflake_stage_resource",
    "snowflake_external_volume_resource",
  ]
}
