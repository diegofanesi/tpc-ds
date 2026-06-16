-- SHOW WAREHOUSES;
ALTER WAREHOUSE <<warehouse>> resume
;

GRANT USAGE ON INTEGRATION s3_int TO ROLE accountadmin;
/* -----------------------
      TPC-DS SETUP
----------------------- */

-- SHOW DATABASES;


-- SHOW SCHEMAS;
GRANT CREATE STAGE ON SCHEMA public TO ROLE accountadmin;


--
CREATE OR REPLACE FILE FORMAT csv_format
  TYPE = csv
  FIELD_DELIMITER = '|'
  NULL_IF = ('NULL', 'null')
  EMPTY_FIELD_AS_NULL = true
  error_on_column_count_mismatch=false;
  
CREATE OR REPLACE STAGE tpcds_stage
  STORAGE_INTEGRATION = s3_int
  URL = 's3://tpcds-datasets/tpcds-2.13/tpcds_sf1000_text/'
  FILE_FORMAT = csv_format;



