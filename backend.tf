# Remote state backend.
#
# Keep this commented for the very first `terraform apply`. The S3 bucket and
# the DynamoDB lock table do not exist yet, so Terraform has nowhere to put the
# state. Once module.s3_backend has created them, uncomment this block, fill in
# your account id, and run:
#
#   terraform init -migrate-state
#
# Terraform will copy the local terraform.tfstate into the bucket and lock it
# through DynamoDB from then on.

# terraform {
#   backend "s3" {
#     bucket         = "tfstate-<ACCOUNT_ID>-eu-central-1"
#     key            = "lesson-8-9/terraform.tfstate"
#     region         = "eu-central-1"
#     dynamodb_table = "lesson-8-9-terraform-locks"
#     encrypt        = true
#   }
# }
