
# 3. Create the IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "create_note_lambda_role_${var.env}"

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

# 4. Attach Strict Least-Privilege DynamoDB Policy to the Lambda Role
resource "aws_iam_role_policy" "lambda_strict_dynamodb" {
  name = "LambdaStrictDynamoDBAccess"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query"
        ]
        Resource = var.table_arn
      }
    ]
  })
}

# Grant Lambda permission to send Trace Data to X-Ray
resource "aws_iam_role_policy_attachment" "lambda_xray_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}

# Attach Basic Execution Role (Allows Lambda to write logs to CloudWatch)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 5. Zip the Python Code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# 6. Create the Lambda Function
resource "aws_lambda_function" "create_note_function" {
  # checkov:skip=CKV_AWS_117: This function does not access VPC resources like RDS.
  # checkov:skip=CKV_AWS_116: This is a synchronous API Gateway integration, DLQ is not applicable.
  # checkov:skip=CKV_AWS_173: Environment variables do not contain sensitive secrets requiring a custom KMS key.
  # checkov:skip=CKV_AWS_272: Code signing is overkill for this architecture.
  # checkov:skip=CKV_AWS_115: Not applying concurrency limits to allow maximum serverless scaling.
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "CreateNoteFunction-${var.env}"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  tracing_config {
    mode = "Active"
  }

  layers = ["arn:aws:lambda:us-east-1:017000801446:layer:AWSLambdaPowertoolsPythonV2:77"]

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME                   = var.table_name
      POWERTOOLS_SERVICE_NAME      = "NotesAPI"
      POWERTOOLS_METRICS_NAMESPACE = "NotesApp"
      LOG_LEVEL                    = "INFO"
    }
  }
}

# 7. Create the HTTP API Gateway
resource "aws_apigatewayv2_api" "http_api" {
  name          = "NotesAPI-${var.env}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "GET", "DELETE", "PUT", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }
}

# 8. Connect API Gateway to Lambda (Integration)
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.create_note_function.invoke_arn
  payload_format_version = "2.0"
}

# 9. Create the Route (POST /notes)
resource "aws_apigatewayv2_route" "post_route" {
  api_id             = aws_apigatewayv2_api.http_api.id
  route_key          = "POST /notes"
  target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

# 9b. Create the Route (GET /notes)
resource "aws_apigatewayv2_route" "get_route" {
  api_id             = aws_apigatewayv2_api.http_api.id
  route_key          = "GET /notes"
  target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

# 9c. Create the Route (DELETE /notes/{id})
resource "aws_apigatewayv2_route" "delete_route" {
  api_id             = aws_apigatewayv2_api.http_api.id
  route_key          = "DELETE /notes/{id}"
  target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

# 9d. Create the Route (PUT /notes/{id})
resource "aws_apigatewayv2_route" "put_route" {
  api_id             = aws_apigatewayv2_api.http_api.id
  route_key          = "PUT /notes/{id}"
  target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

# 10. Deploy the API Gateway Stage
resource "aws_apigatewayv2_stage" "default_stage" {
  # checkov:skip=CKV_AWS_76: Access logging is disabled to save CloudWatch log costs (relying on X-Ray instead).
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



# 14. Create the API Gateway Authorizer (The Bouncer)
resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id           = aws_apigatewayv2_api.http_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "CognitoJWTAuthorizer-${var.env}"

  jwt_configuration {
    audience = [var.client_id]
    issuer   = "https://${var.user_pool_endpoint}"
  }
}
