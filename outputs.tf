
output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool (For Amplify userPoolId)"
  value       = aws_cognito_user_pool.user_pool.id
}

output "cognito_client_id" {
  description = "The ID of the Cognito App Client (For Amplify userPoolClientId)"
  value       = aws_cognito_user_pool_client.user_pool_client.id
}

output "api_gateway_url" {
  description = "The base URL of the API Gateway (For Amplify endpoint)"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "identity_pool_id" {
  description = "The ID of the Cognito Identity Pool"
  value       = aws_cognito_identity_pool.identity_pool.id
}

output "s3_bucket_name" {
  description = "The S3 Bucket name for file attachments"
  value       = aws_s3_bucket.attachments.bucket
}

output "amplify_app_id" {
  description = "The ID of the Amplify App"
  value       = terraform.workspace == "default" ? aws_amplify_app.frontend[0].id : "Not created in dev workspace"
}
