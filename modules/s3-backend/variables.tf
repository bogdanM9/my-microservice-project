variable "bucket_name" {
  description = "Name of the S3 bucket for the Terraform state. Must be globally unique across all of AWS"
  type        = string
}

variable "table_name" {
  description = "Name of the DynamoDB table used for state locking"
  type        = string
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete the bucket even when it still has objects in it"
  type        = bool
  default     = true
}
