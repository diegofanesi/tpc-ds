# Fair Comparison Methodology

This benchmark is designed for objective, reproducible comparison between Databricks and Snowflake performance. The methodology follows industry best practices for cross-platform benchmarking to ensure results reflect genuine platform capabilities rather than configuration artifacts.

## Same Region Deployment

Both platforms must access data from the same geographic region. Network latency differences between regions would introduce measurement noise unrelated to actual query performance. All infrastructure components - the S3 bucket containing TPC-DS data, the Databricks workspace, and the Snowflake account - deploy to the same AWS region. This ensures data transfer characteristics are equivalent for both platforms.

## Comparable Resource Sizing

Warehouse and compute sizes should represent equivalent resource allocation. Comparing a small Snowflake warehouse against a large Databricks cluster would produce meaningless results. The default configuration uses a MEDIUM warehouse size for Snowflake and a comparably-sized Databricks SQL warehouse. Users may adjust these sizes based on their evaluation needs, but should maintain equivalence between platforms.

## Cache Disabled

Queries execute without benefiting from cached results. Cached queries return near-instantly, hiding true query processing performance. The JMeter test plans include cache-disabling parameters: Snowflake queries set `USE_CACHED_RESULT=FALSE`, and Databricks tests use fresh execution contexts. This ensures each query measurement reflects actual computation time.

## Automatic Table Maintenance

Both platforms maintain table statistics and data layout automatically: Snowflake natively, and Databricks through Predictive Optimization. Predictive Optimization must be enabled on the Databricks catalog/schema used for the benchmark — the Databricks pipeline checks it before creating tables and again on every benchmark table, and fails if it is not enabled. No manual `OPTIMIZE` or `ANALYZE` is run on either platform, so neither side gets an un-metered setup step.

## Standard Benchmark Workload

TPC-DS provides an industry-standard reference point for decision support workloads. The benchmark is widely recognized for evaluating analytical query performance across database platforms. This implementation executes 99 TPC-DS queries at a configurable scale factor (default 100GB), covering a representative range of query patterns including joins, aggregations, and subqueries.

## Limitations

Results are specific to TPC-DS workload characteristics and may not reflect performance for other query patterns or data structures.
