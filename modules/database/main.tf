# Inside modules/database/main.tf

resource "aws_dynamodb_table" "notes_table" {
  # checkov:skip=CKV_AWS_119: Using default AWS-owned key for encryption to save KMS costs.
  name         = "NotesTable-${var.env}"
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

  point_in_time_recovery {
    enabled = true
  }
}
