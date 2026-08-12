# 2. Create the DynamoDB Table
resource "aws_dynamodb_table" "notes_table" {
  name         = "NotesTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserId"
  range_key    = "NoteId"

  attribute {
    name = "UserId"
    type = "S"
  }

  attribute {
    name = "NoteId"
    type = "S"
  }
}

# 3. Create the IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "create_note_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# 4. Attach DynamoDB Access to the Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

# Attach Basic Execution Role (Allows Lambda to write logs to CloudWatch)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 5. Zip the Python Code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

# 6. Create the Lambda Function
resource "aws_lambda_function" "create_note_function" {
  filename      = "lambda_function.zip"
  function_name = "CreateNoteFunction"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.notes_table.name
    }
  }
}

# 7. Create the HTTP API Gateway
resource "aws_apigatewayv2_api" "http_api" {
  name          = "NotesAPI"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "GET", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }
}

# 8. Connect API Gateway to Lambda (Integration)
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.create_note_function.invoke_arn
}

# 9. Create the Route (POST /notes)
resource "aws_apigatewayv2_route" "post_route" {
  api_id             = aws_apigatewayv2_api.http_api.id
  route_key          = "POST /notes"
  target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

# 10. Deploy the API Gateway Stage
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# 11. Give API Gateway permission to trigger the Lambda function
resource "aws_lambda_permission" "api_gw_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_note_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# 12. Create the Cognito User Pool (The User Directory)
resource "aws_cognito_user_pool" "user_pool" {
  name = "NotesAppUsers"

  # Email IS the username — prevents duplicate accounts at sign-up time
  # (alias_attributes allows duplicates until confirmation; username_attributes does not)
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }
}

# 13. Create the Cognito App Client (For the Frontend to talk to)
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "NotesAppFrontendClient"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  # We set this to false because web browsers (JavaScript) cannot securely hide secrets
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

# 14. Create the API Gateway Authorizer (The Bouncer)
resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id           = aws_apigatewayv2_api.http_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "CognitoJWTAuthorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.user_pool_client.id]
    issuer   = "https://${aws_cognito_user_pool.user_pool.endpoint}"
  }
}

# --- SSM PARAMETER STORE (THE BRIDGE) ---

resource "aws_ssm_parameter" "api_endpoint" {
  name  = "/notesapp/prod/api-endpoint"
  type  = "String"
  value = aws_apigatewayv2_api.http_api.api_endpoint
}

resource "aws_ssm_parameter" "user_pool_id" {
  name  = "/notesapp/prod/user-pool-id"
  type  = "String"
  value = aws_cognito_user_pool.user_pool.id
}

resource "aws_ssm_parameter" "client_id" {
  name  = "/notesapp/prod/client-id"
  type  = "String"
  value = aws_cognito_user_pool_client.user_pool_client.id
}

# --- AMPLIFY IAM ROLE ---

resource "aws_iam_role" "amplify_service_role" {
  name = "AmplifyHostingServiceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "amplify_ssm_policy" {
  name = "AmplifyReadSSMParameters"
  role = aws_iam_role.amplify_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/notesapp/prod/*"
    }]
  })
}

# (You will need to add this data block at the top of your main.tf to get your AWS Account ID dynamically)
data "aws_caller_identity" "current" {}
