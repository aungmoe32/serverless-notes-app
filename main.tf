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
}

# 7. Create the HTTP API Gateway
resource "aws_apigatewayv2_api" "http_api" {
  name          = "NotesAPI"
  protocol_type = "HTTP"
}

# 8. Connect API Gateway to Lambda (Integration)
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.create_note_function.invoke_arn
}

# 9. Create the Route (POST /notes)
resource "aws_apigatewayv2_route" "post_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /notes"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
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

# Output the Live API URL so you can test it immediately
output "api_endpoint" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}
