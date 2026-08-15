# 2. Create the DynamoDB Table
resource "aws_dynamodb_table" "notes_table" {
  name         = "NotesTable-${terraform.workspace}"
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
  name = "create_note_lambda_role_${terraform.workspace}"

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
  function_name = "CreateNoteFunction-${terraform.workspace}"
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
  name          = "NotesAPI-${terraform.workspace}"
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
  name = "NotesAppUsers-${terraform.workspace}"

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
  name         = "NotesAppFrontendClient-${terraform.workspace}"
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
  name             = "CognitoJWTAuthorizer-${terraform.workspace}"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.user_pool_client.id]
    issuer   = "https://${aws_cognito_user_pool.user_pool.endpoint}"
  }
}

# --- SSM PARAMETER STORE (THE BRIDGE) ---

resource "aws_ssm_parameter" "api_endpoint" {
  name  = "/notesapp/${terraform.workspace}/api-endpoint"
  type  = "String"
  value = aws_apigatewayv2_api.http_api.api_endpoint
}

resource "aws_ssm_parameter" "user_pool_id" {
  name  = "/notesapp/${terraform.workspace}/user-pool-id"
  type  = "String"
  value = aws_cognito_user_pool.user_pool.id
}

resource "aws_ssm_parameter" "client_id" {
  name  = "/notesapp/${terraform.workspace}/client-id"
  type  = "String"
  value = aws_cognito_user_pool_client.user_pool_client.id
}

resource "aws_ssm_parameter" "s3_bucket_name" {
  name  = "/notesapp/${terraform.workspace}/s3-bucket-name"
  type  = "String"
  value = aws_s3_bucket.attachments.bucket
}

resource "aws_ssm_parameter" "identity_pool_id" {
  name  = "/notesapp/${terraform.workspace}/identity-pool-id"
  type  = "String"
  value = aws_cognito_identity_pool.identity_pool.id
}

# --- AMPLIFY IAM ROLE ---

resource "aws_iam_role" "amplify_service_role" {
  name = "AmplifyHostingServiceRole-${terraform.workspace}"

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
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/notesapp/${terraform.workspace}/*"
    }]
  })
}

# (You will need to add this data block at the top of your main.tf to get your AWS Account ID dynamically)
data "aws_caller_identity" "current" {}

# --- DIRECT-TO-S3 UPLOAD PATTERN ---

# 1. Create a globally unique name generator
resource "random_pet" "bucket_suffix" {
  length = 2
}

# 2. Create the S3 Bucket for Attachments
resource "aws_s3_bucket" "attachments" {
  bucket = "notes-attachments-${random_pet.bucket_suffix.id}-${terraform.workspace}"
}

# 3. Configure CORS on S3 so the React browser app can upload to it
resource "aws_s3_bucket_cors_configuration" "attachments_cors" {
  bucket = aws_s3_bucket.attachments.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# 4. Create the Identity Pool (The Credential Vending Machine)
resource "aws_cognito_identity_pool" "identity_pool" {
  identity_pool_name               = "NotesIdentityPool_${terraform.workspace}"
  allow_unauthenticated_identities = false # We only allow logged-in users

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.user_pool_client.id
    provider_name           = aws_cognito_user_pool.user_pool.endpoint
    server_side_token_check = false
  }
}

# 5. Create the IAM Role for Authenticated Users
resource "aws_iam_role" "auth_user_role" {
  name = "CognitoAuthRole_${terraform.workspace}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "cognito-identity.amazonaws.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        "StringEquals" : {
          "cognito-identity.amazonaws.com:aud" : aws_cognito_identity_pool.identity_pool.id
        },
        "ForAnyValue:StringLike" : {
          "cognito-identity.amazonaws.com:amr" : "authenticated"
        }
      }
    }]
  })
}

# 6. Apply the Zero-Trust IAM Policy (Notice the $$ variable injection!)
resource "aws_iam_role_policy" "auth_user_s3_policy" {
  name = "S3PrivateAccess"
  role = aws_iam_role.auth_user_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        # Terraform uses $$ to escape the string, passing the raw ${...} variable to AWS IAM
        Resource = "${aws_s3_bucket.attachments.arn}/private/$${cognito-identity.amazonaws.com:sub}/*"
      }
    ]
  })
}

# 7. Attach the Role to the Identity Pool
resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.identity_pool.id
  roles = {
    "authenticated" = aws_iam_role.auth_user_role.arn
  }
}

# Automatically write local frontend variables ONLY if we are in the dev workspace
resource "local_file" "frontend_env" {
  count    = terraform.workspace == "dev" ? 1 : 0
  filename = "${path.module}/serverless-frontend/.env.local"
  content  = <<-EOT
    VITE_AWS_REGION="${var.aws_region}"
    VITE_USER_POOL_ID="${aws_cognito_user_pool.user_pool.id}"
    VITE_USER_POOL_CLIENT_ID="${aws_cognito_user_pool_client.user_pool_client.id}"
    VITE_IDENTITY_POOL_ID="${aws_cognito_identity_pool.identity_pool.id}"
    VITE_S3_BUCKET_NAME="${aws_s3_bucket.attachments.bucket}"
    VITE_API_ENDPOINT="${aws_apigatewayv2_api.http_api.api_endpoint}"
  EOT
}

# --- AMPLIFY HOSTING (FRONTEND CI/CD) ---

resource "aws_amplify_app" "frontend" {
  count      = terraform.workspace != "dev" ? 1 : 0
  name       = "NotesAppFrontend-${terraform.workspace}"
  repository = "https://github.com/aungmoemyintthu/serverless-notes-app"

  # The GitHub token to connect the repo
  access_token = var.github_token

  # The IAM Role we created earlier so Amplify can read SSM Parameters
  iam_service_role_arn = aws_iam_role.amplify_service_role.arn

  # The SPA Redirect Rule (Fixes React Router 404 errors)
  custom_rule {
    source = "</^[^.]+$|\\.(?!(css|gif|ico|jpg|js|png|txt|svg|woff|woff2|ttf|map|json|webp)$)([^.]+$)/>"
    status = "200"
    target = "/index.html"
  }

  # The build script injected via code
  build_spec = <<-EOT
    version: 1
    applications:
      - frontend:
          phases:
            preBuild:
              commands:
                - npm install -g pnpm
                - pnpm install --frozen-lockfile
                - echo "Fetching backend variables from AWS SSM..."
                - echo "VITE_AWS_REGION=${var.aws_region}" >> .env
                - echo "VITE_API_ENDPOINT=$(aws ssm get-parameter --name '/notesapp/${terraform.workspace}/api-endpoint' --query 'Parameter.Value' --output text)" >> .env
                - echo "VITE_USER_POOL_ID=$(aws ssm get-parameter --name '/notesapp/${terraform.workspace}/user-pool-id' --query 'Parameter.Value' --output text)" >> .env
                - echo "VITE_USER_POOL_CLIENT_ID=$(aws ssm get-parameter --name '/notesapp/${terraform.workspace}/client-id' --query 'Parameter.Value' --output text)" >> .env
                - echo "VITE_S3_BUCKET_NAME=$(aws ssm get-parameter --name '/notesapp/${terraform.workspace}/s3-bucket-name' --query 'Parameter.Value' --output text)" >> .env
                - echo "VITE_IDENTITY_POOL_ID=$(aws ssm get-parameter --name '/notesapp/${terraform.workspace}/identity-pool-id' --query 'Parameter.Value' --output text)" >> .env
            build:
              commands:
                - pnpm run build
          artifacts:
            baseDirectory: dist
            files:
              - '**/*'
          cache:
            paths:
              - node_modules/**/*
              - ~/.local/share/pnpm/store/**/*
        appRoot: serverless-frontend
  EOT
}

# Map the GitHub branch to the Amplify App
resource "aws_amplify_branch" "main" {
  count       = terraform.workspace != "dev" ? 1 : 0
  app_id      = aws_amplify_app.frontend[0].id
  branch_name = "main"

  # We set this to false because our GitHub Actions
  # pipeline triggers Amplify after Terraform finishes
  enable_auto_build = false
}
