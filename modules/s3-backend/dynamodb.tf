# DynamoDB table used as the Terraform state lock.
#
# Terraform writes a row here while an apply is running, so a second person
# running apply at the same time gets "Error acquiring the state lock" instead
# of both of them writing over each other.
#
# The partition key must be called LockID. Terraform hardcodes that name.

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "Terraform state locks"
  }
}
