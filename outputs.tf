
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
