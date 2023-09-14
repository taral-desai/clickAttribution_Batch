terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region  = var.aws_region
  profile = "default"
}

# Create our S3 bucket (Deltalake)
resource "aws_s3_bucket" "delta-lake" {
  bucket_prefix = var.bucket_prefix
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "delta-lake" {
  bucket = aws_s3_bucket.delta-lake.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}


resource "aws_s3_bucket_acl" "delta-lake-acl" {
   depends_on = [aws_s3_bucket_ownership_controls.delta-lake]
  bucket = aws_s3_bucket.delta-lake.id
  acl    = "private"
}

locals {
  pyspark_file_path = "./pyspark_script.py"
}

resource "aws_s3_object" "pyspark_script" {
  bucket = aws_s3_bucket.delta-lake.id
  key    = "src/code/pyspark_script.py"
  source = local.pyspark_file_path
  etag = filemd5(local.pyspark_file_path)
}

# IAM role for Glue to connect to AWS S3
resource "aws_iam_role" "AWSGlueServiceRole_Delta-lake-access" {
  name = "AWSGlueServiceRole_Delta-lake-access"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      },
    ]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]
}

# IAM role for Glue Crawler to connect to AWS S3 and Glue Data Catalog Database
resource "aws_iam_role" "AWSGlueServiceRole_Crawler" {
  name = "AWSGlueServiceRole_Crawler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      },
    ]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonS3FullAccess", "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"]
}

resource "aws_glue_job" "pyspark_clicks_job" {
  for_each = toset( ["pyspark_clicks_job", "pyspark_checkout_job"] )
  name         = each.key
  role_arn     = aws_iam_role.AWSGlueServiceRole_Delta-lake-access.arn
  glue_version = "4.0"
  worker_type  = "Standard"
  number_of_workers = 3

  command {
    script_location = "s3://${aws_s3_bucket.delta-lake.id}/${aws_s3_object.pyspark_script.key}"
  }

  default_arguments = {
    "--enable-metrics" = ""
    "--datalake-formats" = "delta"
    "--packages" = "org.apache.spark:spark-sql-kafka-0-10_2.12:3.4.1,io.delta:delta-core_2.12:2.1.1"
    "--output_s3_bucket" = "${aws_s3_bucket.delta-lake.id}"
    # "--kafka_topic" = "clicks"
  }

  execution_property {
    max_concurrent_runs = 2
  }
}

resource "aws_glue_catalog_database" "delta-lake_catalog" {
  name = "delta-lake_catalog"
  description = "Database tables are populated by Glue Crawler"
}

resource "aws_glue_crawler" "delta_crawler" {
  database_name = aws_glue_catalog_database.delta-lake_catalog.name
  name          = "delta_crawler"
  role          = aws_iam_role.AWSGlueServiceRole_Crawler.arn
  description = "delta-lake_catalog databse is populated with delta tables by this Glue Crawler"

  delta_target {
    delta_tables = ["s3://${aws_s3_bucket.delta-lake.id}/delta-lake/clicks/"]
    write_manifest  = true
  }
}

# Setting as budget monitor, so we don't go over 10 USD per month
resource "aws_budgets_budget" "cost" {
  budget_type  = "COST"
  limit_amount = "10"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
}

module "redshift_serverless" {
  source = "./terraform-aws-redshift-serverless"
  ##########################
# Application Definition # 
##########################
app_name        = "lakehouse" # Do NOT enter any spaces
app_environment = "dev" # Dev, Test, Staging, Prod, etc

#########################
# Network Configuration #
#########################
redshift_serverless_vpc_cidr      = "10.20.0.0/16"
redshift_serverless_subnet_1_cidr = "10.20.1.0/24"
redshift_serverless_subnet_2_cidr = "10.20.2.0/24"
redshift_serverless_subnet_3_cidr = "10.20.3.0/24"

###################################
## Redshift Serverless Variables ##
###################################
redshift_serverless_namespace_name      = "lakehose-namespace"
redshift_serverless_database_name       = "lakehousedb" //must contain only lowercase alphanumeric characters, underscores, and dollar signs
redshift_serverless_admin_username      = "dbtadmin"
redshift_serverless_admin_password      = "M3ss1G0at10"
redshift_serverless_workgroup_name      = "lakehouse-workgroup"
redshift_serverless_base_capacity       = 32 // 32 RPUs to 512 RPUs in units of 8 (32,40,48...512)
redshift_serverless_publicly_accessible = false
}