variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version of the control plane. Left null so AWS picks the current default, which avoids pinning a version EKS has already retired"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnets the cluster and the node group are placed in"
  type        = list(string)
}

variable "node_group_name" {
  description = "Name of the managed node group"
  type        = string
  default     = "general"
}

variable "instance_type" {
  description = "EC2 instance type for the worker nodes. Must be free tier eligible on a Free Plan account, see the root variables.tf for the reasoning"
  type        = string
  default     = "m7i-flex.large"
}

variable "disk_size" {
  description = "Root volume size of each node in GiB"
  type        = number
  default     = 20
}

variable "desired_size" {
  description = "Number of nodes to start with"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3
}
