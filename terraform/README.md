# TPC-DS Benchmarking Infrastructure — Terraform

This Terraform configuration provisions everything the TPC-DS benchmark needs on
AWS, Databricks, and Snowflake — **except** user identities and credentials,
which you create and manage yourself.

It is an alternative to doing the setup manually. After apply, a single
`config.json.generated` file is written to the repo root with every non-secret
value pre-filled. You paste in your Databricks PAT, upload your Snowflake RSA
key to the UC volume, open the workspace, and run the `0 - Job Setup` notebook.

## What Terraform creates

| Where | Resource |
|---|---|
| AWS | S3 bucket (versioning + AES256 + public-access block) with a bucket policy granting both Databricks and Snowflake IAM roles |
| AWS | IAM role `{prefix}-databricks-uc-{env}` — self-trusting, for Databricks Unity Catalog |
| AWS | IAM role `{prefix}-snowflake-external-{env}` — trusted by the Snowflake storage integration (read + write) |
| Databricks | Catalog, schema, storage credential, external location, external volume (points at the bucket root) |
| Snowflake | Database (with DB-level default external volume), schema, storage integration, external volume `tpcds_iceberg_volume`, CSV file format, external stage |
| Snowflake | Grants on integration / DB / schema / external volume to your service role |

## What Terraform does **not** create

- Users or credentials on Databricks (SSO / PAT) or Snowflake (user + RSA keypair)
- Benchmark warehouses (`TPCDS_{scale}_{size}_{strategy}`) — provisioned per-combo at runtime
- Results tables (`results_queries`, `results_prices`) — created by notebook `6` via Autoloader

## Prerequisites

### Software

| Tool | Minimum version | Notes |
|---|---|---|
| Terraform | 1.5 | |
| AWS CLI | v2 | |
| Databricks CLI | 0.2 | `databricks auth login --profile …` |
| Snowflake CLI | v2 (`snow`) | `snow connection add …` → `~/.snowflake/config.toml` |

### Accounts & permissions

- **AWS** account with permission to create S3 buckets, IAM roles, and bucket policies.
- **Databricks** workspace with Unity Catalog; a workspace admin token; account-level access for storage credentials.
- **Snowflake** account with `ACCOUNTADMIN` (for storage integration / external volume / grants) and an already-created service user using RSA keypair auth.

## Step-by-step

### 1. Configure CLI profiles

```bash
aws sso login --profile tpcds-dev
databricks auth login --host https://dbc-xxxxxxx.cloud.databricks.com --profile tpcds-dev
snow connection add tpcds-dev \
  --account <org>-<acct> --user <admin_user> \
  --authenticator SNOWFLAKE_JWT --private-key-file /path/to/admin_rsa_key.p8
```

### 2. Fill in variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
```

At minimum set: the three `*_profile` names, `s3_bucket_name`,
`databricks_workspace_url`, `databricks_account_id`, `snowflake_organization`,
`snowflake_account`, `snowflake_user`.

### 3. Apply

```bash
terraform init
terraform apply
```

Apply takes ~2 minutes. When it succeeds, read the `next_steps` output for
the exact commands and paths for the remaining steps.

### 4. Fill in the two secrets

```bash
# Copy the generated config into place
cp config.json.generated ../config.json
```

Edit `../config.json`:
- Replace `<PASTE_YOUR_DATABRICKS_PAT_HERE>` with your Databricks PAT
  (User Settings → Developer → Access tokens).
- `snowflake.auth_key_path` is already set to a path inside the UC volume
  Terraform created (see next step). Leave it as is.

### 5. Upload your Snowflake RSA private key to the volume

From the Databricks workspace UI:
Catalog → `<databricks_catalog>` → `<databricks_schema>` → Volumes →
`<databricks_volume_name>` → create folder `test_files` → upload
`rsa_key.p8` (PKCS#8).

The resulting path must match the `snowflake.auth_key_path` in `config.json`.

### 6. Create jobs and run the benchmark

In the Databricks workspace, checkout this repo and open `0 - Job Setup.ipynb`.
Run it. It creates three jobs:
1. **TPC-DS Databricks** (single-combo)
2. **TPC-DS Snowflake** (single-combo)
3. **TPC-DS Full Benchmark** (orchestrator)

Trigger the orchestrator — see the root `README.md` for parameter reference.

## File layout

```
terraform/
├── README.md                  # this file
├── versions.tf                # terraform + provider versions
├── providers.tf               # AWS / Databricks / Snowflake providers (profile-based)
├── variables.tf               # inputs
├── terraform.tfvars.example   # example inputs
├── terraform.tfvars           # your inputs (gitignored)
├── aws.tf                     # S3 + IAM roles + bucket policy + time_sleep gates
├── databricks.tf              # catalog, schema, storage credential, external location, volume
├── snowflake.tf               # DB, schema, integration, external volume, file format, stage, grants
└── outputs.tf                 # outputs + renders ../config.json.generated
```

## Common issues

**`databricks_catalog ... already exists`** — the catalog you named already
exists in your metastore. Either pick a different name in `terraform.tfvars` or
run `terraform import databricks_catalog.tpcds <name>` before applying.
Same applies to `databricks_schema`.

**`snowflake_database ... already exists`** — same pattern; rename or import.

**IAM role not yet assumable by storage credential** — the `time_sleep`
resources give AWS IAM ~20s to propagate. If you hit a transient trust-policy
error on first apply, rerun `terraform apply`; the second run picks up with the
role fully propagated.

**`ConfigurationLoadFailed` on Snowflake provider** — your `snow` profile name
doesn't match `snowflake_profile` in `terraform.tfvars`, or the profile in
`~/.snowflake/config.toml` is missing `account` / `user` / private key path.

## Destroy

**Warning — this deletes the S3 bucket and all benchmark data.**

```bash
terraform destroy
```

If the bucket has objects, empty it first:

```bash
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive --profile $(terraform output -raw aws_profile 2>/dev/null || echo default)
```

## References

- [Databricks Unity Catalog storage credentials](https://docs.databricks.com/en/connect/unity-catalog/storage-credentials.html)
- [Databricks Terraform examples](https://github.com/databricks/terraform-databricks-examples)
- [Snowflake storage integration](https://docs.snowflake.com/en/sql-reference/sql/create-storage-integration)
- [Snowflake external volumes for Iceberg](https://docs.snowflake.com/en/sql-reference/sql/create-external-volume)
- [TPC-DS specification](http://www.tpc.org/tpcds/)
