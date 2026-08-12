# --- GITHUB ACTIONS OIDC (INFRASTRUCTURE CI/CD) ---

# 1. Register GitHub as a trusted Identity Provider in AWS
resource "aws_iam_openid_connect_provider" "github_oidc" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's OIDC thumbprint (This is standard across all AWS accounts)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd", "1b511abead59c6ce207077c0bf0e0043b1382612"]
}

# 2. Create the IAM Role that GitHub Actions will assume
resource "aws_iam_role" "github_actions_tf_role" {
  name = "GitHubActionsTerraformRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_oidc.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        "StringEquals" : {
          "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
        },
        "StringLike" : {
          # CRITICAL SECURITY: Only YOUR specific repository can assume this role.
          "token.actions.githubusercontent.com:sub" : "repo:aungmoe32@125842632/serverless-notes-app@1323660203:*"
        }
      }
    }]
  })
}

# 3. Give the GitHub Actions role Administrator access so it can build infrastructure
# (In a hyper-strict enterprise, you would scope this down, but Admin is standard for TF pipelines)
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions_tf_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Output the Role ARN so we can paste it into GitHub
output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_tf_role.arn
}
