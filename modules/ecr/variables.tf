variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "scan_on_push" {
  description = "Run a vulnerability scan every time an image is pushed"
  type        = bool
  default     = true
}

variable "image_tag_mutability" {
  description = "MUTABLE allows overwriting an existing tag, IMMUTABLE blocks it"
  type        = string
  default     = "MUTABLE"
}

variable "force_delete" {
  description = "Let terraform destroy delete the repository together with the images inside it"
  type        = bool
  default     = true
}
