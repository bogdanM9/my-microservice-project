variable "vpc_name" {
  description = "Prefix used in the Name tag of every resource in this module"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "public_subnets" {
  description = "CIDR blocks of the public subnets, one per availability zone"
  type        = list(string)
}

variable "private_subnets" {
  description = "CIDR blocks of the private subnets, one per availability zone"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones to spread the subnets across"
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name, needed for the kubernetes.io/cluster subnet tags"
  type        = string
}
