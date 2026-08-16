
output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool (For Amplify userPoolId)"
  value       = module.auth.user_pool_id
}

output "cognito_client_id" {
  description = "The ID of the Cognito App Client (For Amplify userPoolClientId)"
  value       = module.auth.client_id
}

output "api_gateway_url" {
  description = "The base URL of the API Gateway (For Amplify endpoint)"
  value       = module.api.api_endpoint
}

output "identity_pool_id" {
  description = "The ID of the Cognito Identity Pool"
  value       = module.storage.identity_pool_id
}

output "s3_bucket_name" {
  description = "The S3 Bucket name for file attachments"
  value       = module.storage.bucket_name
}

output "amplify_app_id" {
  description = "The ID of the Amplify App"
  value       = terraform.workspace == "default" ? aws_amplify_app.frontend[0].id : "Not created in dev workspace"
}
