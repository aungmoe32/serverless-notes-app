variable "env" {
  description = "The deployment environment"
  type        = string
}

variable "user_pool_endpoint" {
  description = "Endpoint of the Cognito User Pool"
  type        = string
}

variable "client_id" {
  description = "ID of the Cognito App Client"
  type        = string
}
