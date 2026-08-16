# 12. Create the Cognito User Pool (The User Directory)
resource "aws_cognito_user_pool" "user_pool" {
  name = "NotesAppUsers-${var.env}"

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
  name         = "NotesAppFrontendClient-${var.env}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  # We set this to false because web browsers (JavaScript) cannot securely hide secrets
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}
