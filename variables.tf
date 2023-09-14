## AWS account level config: region
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
## AWS S3 bucket details
variable "bucket_prefix" {
  description = "Bucket prefix for our deltalake"
  type        = string
  default     = "delta-lake-"
}




