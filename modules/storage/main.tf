
# --- DIRECT-TO-S3 UPLOAD PATTERN ---

# 1. Create a globally unique name generator
resource "random_pet" "bucket_suffix" {
  length = 2
}

# 2. Create the S3 Bucket for Attachments
resource "aws_s3_bucket" "attachments" {
  # checkov:skip=CKV_AWS_18: S3 Access logging is not required for personal attachments.
  # checkov:skip=CKV_AWS_21: Versioning is not required for this bucket.
  # checkov:skip=CKV_AWS_144: Cross-region replication is overkill.
  # checkov:skip=CKV_AWS_145: Default AWS S3 encryption is sufficient, skipping KMS.
  # checkov:skip=CKV2_AWS_6: Public access block is handled at the account level.
  # checkov:skip=CKV2_AWS_61: Lifecycle policies are not required for this practice app.
  # checkov:skip=CKV2_AWS_62: S3 Event notifications are not currently needed.

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
    client_id               = var.client_id
    provider_name           = var.user_pool_endpoint
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
