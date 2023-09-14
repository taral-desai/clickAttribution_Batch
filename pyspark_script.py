from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col, count
from pyspark.sql.types import StructType, StructField, IntegerType, StringType, FloatType, TimestampType
from delta import *
import sys
from awsglue.utils import getResolvedOptions

args = getResolvedOptions(sys.argv,
                          ['output_s3_bucket',
                           'kafka_topic',
                           'api_key',
                           'api_secret'])


spark = SparkSession.builder \
    .appName("KafkaReader") \
    .config("spark.streaming.stopGracefullyOnShutdown", "true") \
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension") \
    .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog") \
    .getOrCreate()

schema = StructType().add("click_id", StringType()).add("user_id", IntegerType()).add("product_id", StringType()).add("product", StringType()).add("price", FloatType()).add("url", StringType()).add("user_agent", StringType()).add("ip_address", StringType()).add("datetime_occured", StringType())

df = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "pkc-p11xm.us-east-1.aws.confluent.cloud:9092") \
    .option("kafka.security.protocol", "SASL_SSL") \
    .option("kafka.ssl.endpoint.identification.algorithm", "https") \
    .option("kafka.sasl.mechanism", "PLAIN") \
    .option("kafka.sasl.jaas.config", f'org.apache.kafka.common.security.plain.PlainLoginModule required username="{args['api_key']}" password="{args['api_secret']}";') \
    .option("subscribe", args['kafka_topic']) \
    .option("startingOffsets", "earliest") \
    .load()

df2 = df.selectExpr("CAST(value AS STRING)") \
  .select(from_json(col("value").cast("string"), schema).alias("data")).select("data.*")

df2.printSchema()

df2.writeStream \
    .format("delta") \
    .trigger(availableNow=True) \
    .option("checkpointLocation", "s3a://" + args['output_s3_bucket'] + "/checkpoint") \
    .option("path", "s3a://" + args['output_s3_bucket'] + "/delta-lake/" + args['kafka_topic']) \
    .start() \
    .awaitTermination() 