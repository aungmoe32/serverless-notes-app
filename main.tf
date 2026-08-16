# 1. Call the Database Module
module "database" {
  source = "./modules/database"
  env    = terraform.workspace
}

# 2. STATE REFACTORING: Prevent Data Loss!
# This tells Terraform: "The table still exists, its code just moved."
moved {
  from = aws_dynamodb_table.notes_table
  to   = module.database.aws_dynamodb_table.notes_table
}

# 2. Call the Auth Module
module "auth" {
  source = "./modules/auth"
  env    = terraform.workspace
}

# STATE REFACTORING: Protect the Cognito Database!
moved {
  from = aws_cognito_user_pool.user_pool
  to   = module.auth.aws_cognito_user_pool.user_pool
}

moved {
  from = aws_cognito_user_pool_client.user_pool_client
  to   = module.auth.aws_cognito_user_pool_client.user_pool_client
}

# 3. Call the Storage Module
module "storage" {
  source = "./modules/storage"
  env    = terraform.workspace

  # Data passing from Auth -> Storage
  user_pool_endpoint = module.auth.user_pool_endpoint
  client_id          = module.auth.client_id
}

# STATE REFACTORING: Protect S3 and Identity Pool
moved {
  from = random_pet.bucket_suffix
  to   = module.storage.random_pet.bucket_suffix
}
moved {
  from = aws_s3_bucket.attachments
  to   = module.storage.aws_s3_bucket.attachments
}
moved {
  from = aws_s3_bucket_cors_configuration.attachments_cors
  to   = module.storage.aws_s3_bucket_cors_configuration.attachments_cors
}
moved {
  from = aws_cognito_identity_pool.identity_pool
  to   = module.storage.aws_cognito_identity_pool.identity_pool
}
moved {
  from = aws_iam_role.auth_user_role
  to   = module.storage.aws_iam_role.auth_user_role
}
moved {
  from = aws_iam_role_policy.auth_user_s3_policy
  to   = module.storage.aws_iam_role_policy.auth_user_s3_policy
}
moved {
  from = aws_cognito_identity_pool_roles_attachment.main
  to   = module.storage.aws_cognito_identity_pool_roles_attachment.main
}


# 4. Call the API Module
module "api" {
  source = "./modules/api"
  env    = terraform.workspace

  # Data from Database Module
  table_name = module.database.table_name
  table_arn  = module.database.table_arn

  # Data from Auth Module
  client_id          = module.auth.client_id
  user_pool_endpoint = module.auth.user_pool_endpoint
}

# STATE REFACTORING: Protect Compute and Routing
moved {
  from = aws_iam_role.lambda_exec_role
  to   = module.api.aws_iam_role.lambda_exec_role
}
moved {
  from = aws_iam_role_policy_attachment.lambda_basic_execution
  to   = module.api.aws_iam_role_policy_attachment.lambda_basic_execution
}
moved {
  from = aws_lambda_function.create_note_function
  to   = module.api.aws_lambda_function.create_note_function
}
moved {
  from = aws_apigatewayv2_api.http_api
  to   = module.api.aws_apigatewayv2_api.http_api
}
moved {
  from = aws_apigatewayv2_integration.lambda_integration
  to   = module.api.aws_apigatewayv2_integration.lambda_integration
}
moved {
  from = aws_apigatewayv2_route.post_route
  to   = module.api.aws_apigatewayv2_route.post_route
}
moved {
  from = aws_apigatewayv2_route.get_route
  to   = module.api.aws_apigatewayv2_route.get_route
}
moved {
  from = aws_apigatewayv2_route.put_route
  to   = module.api.aws_apigatewayv2_route.put_route
}
moved {
  from = aws_apigatewayv2_route.delete_route
  to   = module.api.aws_apigatewayv2_route.delete_route
}
moved {
  from = aws_apigatewayv2_stage.default_stage
  to   = module.api.aws_apigatewayv2_stage.default_stage
}
moved {
  from = aws_lambda_permission.api_gw_permission
  to   = module.api.aws_lambda_permission.api_gw_permission
}
moved {
  from = aws_apigatewayv2_authorizer.cognito_authorizer
  to   = module.api.aws_apigatewayv2_authorizer.cognito_authorizer
}


# --- SSM PARAMETER STORE (THE BRIDGE) ---

resource "aws_ssm_parameter" "api_endpoint" {
  name  = "/notesapp/${terraform.workspace}/api-endpoint"
  type  = "String"
  value = module.api.api_endpoint
}

resource "aws_ssm_parameter" "user_pool_id" {
  name  = "/notesapp/${terraform.workspace}/user-pool-id"
  type  = "String"
  value = module.auth.user_pool_id
}

resource "aws_ssm_parameter" "client_id" {
  name  = "/notesapp/${terraform.workspace}/client-id"
  type  = "String"
  value = module.auth.client_id
}

resource "aws_ssm_parameter" "s3_bucket_name" {
  name  = "/notesapp/${terraform.workspace}/s3-bucket-name"
  type  = "String"
  value = module.storage.bucket_name
}

resource "aws_ssm_parameter" "identity_pool_id" {
  name  = "/notesapp/${terraform.workspace}/identity-pool-id"
  type  = "String"
  value = module.storage.identity_pool_id
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




# Automatically write local frontend variables ONLY if we are in the dev workspace
resource "local_file" "frontend_env" {
  count    = terraform.workspace == "dev" ? 1 : 0
  filename = "${path.module}/serverless-frontend/.env.local"
  content  = <<-EOT
    VITE_AWS_REGION="${var.aws_region}"
    VITE_USER_POOL_ID="${module.auth.user_pool_id}"
    VITE_USER_POOL_CLIENT_ID="${module.auth.client_id}"
    VITE_IDENTITY_POOL_ID="${module.storage.identity_pool_id}"
    VITE_S3_BUCKET_NAME="${module.storage.bucket_name}"
    VITE_API_ENDPOINT="${module.api.api_endpoint}"
  EOT
}

# --- AMPLIFY HOSTING (FRONTEND CI/CD) ---

resource "aws_amplify_app" "frontend" {
  count      = terraform.workspace != "dev" ? 1 : 0
  name       = "NotesAppFrontend-${terraform.workspace}"
  repository = "https://github.com/aungmoe32/serverless-notes-app"

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
