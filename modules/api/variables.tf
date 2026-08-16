variable "env" {
  type = string
}
variable "table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}
variable "table_arn" {
  description = "ARN of the DynamoDB table for IAM permissions"
  type        = string
}
variable "client_id" {
  description = "Cognito Client ID for the Authorizer"
  type        = string
}
variable "user_pool_endpoint" {
  description = "Cognito User Pool Endpoint for the Authorizer"
  type        = string
}
