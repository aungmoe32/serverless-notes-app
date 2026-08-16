# Inside modules/database/main.tf
resource "aws_dynamodb_table" "notes_table" {
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
}
