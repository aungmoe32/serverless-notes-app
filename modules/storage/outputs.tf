output "identity_pool_id" {
  value = aws_cognito_identity_pool.identity_pool.id
}

output "bucket_name" {
  value = aws_s3_bucket.attachments.bucket
}
