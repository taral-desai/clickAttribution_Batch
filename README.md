# Click Stream Lambda Architecture - Data & Analytics Engineering Project

The project is my effort to put in my Data Engineering ideas into 1 single project. I have used Lambda Architecture which composes of Speed and Batch Layer. The Project consists of 3 GitHub repos.

- **`Speed layer`**: https://github.com/taral-desai/clickAttribution_Streaming
- **`Batch layer`**: https://github.com/taral-desai/clickAttribution_Batch
- **`DBT layer`**: https://github.com/taral-desai/clickAttribution_DBT

![image](https://dbt-demo12.s3.amazonaws.com/arch2_white_f.png)

### Problem Statement 
(https://www.startdataengineering.com/post/data-engineering-project-for-beginners-stream-edition/)

Let's imagine we operate an e-commerce platform where it's common to track the source of each product purchase, specifically the click that directly contributed to the sale. This process is known as attribution, which involves linking the act of making a purchase to a specific click event. There are multiple types of **[attribution](https://www.shopify.com/blog/marketing-attribution#3)**; we will focus on `First Click Attribution`. 

Our objectives are:
 1. Enrich checkout data with the user name. The user data is in a transactional database.
 2. Identify which click leads to a checkout (aka attribution). For every product checkout, we consider **the earliest(first) click a user made on that product in the previous hour to be the click that led to a checkout**.
 3. Log the checkouts and their corresponding attributed clicks (if any) into a table.
 4. Log all the clicks and checkouts data to delta tables for historical snapshots.
 5. Use these external delta tables to derive insights within Redshift, data transformed, modelled and versioned using DBT.  


## 
**`Application`**: Website generates clicks and checkout event data.

**`Queue`**: The clicks and checkout data are sent to their corresponding confluent cloud Kafka topics.

### **`Speed Layer:`** https://github.com/taral-desai/clickAttribution_Streaming
   1. Flink reads data from the Kafka topics.
   2. The click data is stored in our cluster state. Note that we only store click information for the last hour, and we only store one click per user-product combination. 
   3. The checkout data is enriched with user information by querying the user table in Postgres.
   4. The checkout data is left joined with the click data( in the cluster state) to see if the checkout can be attributed to a click.
   5. The enriched and attributed checkout data is logged into a Postgres sink table.
&nbsp;

**`Monitoring & Alerting`**: Apache Flink metrics are pulled by Prometheus and visualized using Graphana.

### **`Batch Layer:`** https://github.com/taral-desai/clickAttribution_Batch

   1. Spark structured streaming app reads data from the Kafka topics in AvailableNow() mode. (Triggered daily)
   2. The data is written to Delta Tables in s3.  
   3. Glue Crawler is used to crawl though delta table and register schema to Glue Data Catalog database.
   4. The delta tables are used by Redshift as external tables and querried using Redshift Spectrum.
   5. Amazon Redshift now supports automatic mounting of AWS Glue Data Catalog to be used as raw schema for our DBT layer. 

### **`DBT Layer:`** https://github.com/taral-desai/clickAttribution_DBT

To be added!

# Considerations and Viewpoints: 

1. Batch job vs structured streaming:
      - **`Checkpointing`**: When running a batch job that does incremental updates, you must generally determine what data is new, what you should analyse, and what you should not. Structured Streaming already takes care of all of this.
      - **`Table Level Atomicity`**: In big data processing, the key feature is fault tolerance. When processing jobs fail, it's vital to clean up their outputs to avoid corrupt data. Structured Streaming in Spark helps by logging all files created during successful runs, ensuring that failures don't contaminate downstream applications by identifying and using only valid files.

2. Use of Delta Lake
    - ACID transactions
    - Scalable metadata handline
    - Unified streaming and batch processing
    - Time travel (data versioning)
    - Schema enforcement and evolution
    - Audit history
    - Parquet format
    - Compatible with Apache Spark API

3. I tried to avoid using Glue Crawler and directly register delta lake tables to Glue Catalog after writing it to delta lake but I guess its not supported yet as it creates a generic Hive table with an array field. (Discussion: https://repost.aws/questions/QUiauLmKeOSZqz76BR8vI4lg/creating-a-delta-table-from-spark-using-the-glue-catalog) 

4. Why Flink ? 
Fun to learn new real time engine and its way of defining source and sink as unbounded tables using FlinkSQL API intrigued me. 
Otherwise, I found it very easy to use if you get the hang of it. Would recommend Flink course by Confluent (https://developer.confluent.io/courses/apache-flink/intro/)


### TO DO's

- Documentation to easily replicate this project
- The project is still WIP when it comes to automating infrastructure, DBT modelling and CI/CD.
- Decision on gettting user data into redshift.
- Testing
- Schema evolution in Flink (in state & external: using schema registry with kafka)
- Data Quality Framework

## Data Tech Stack

- AWS GLue
- AWS Redshift
- Terraform
- FlinkSQL
- DBT (One Big Table model)
- Spark Structured Streaming ( AvailableNow() mode, i.e., Batch processing of data from source untill the job triggered)
- Docker and Docker Compose
- Github Actions (CI/CD) 







