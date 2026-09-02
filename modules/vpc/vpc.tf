resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block

  # Both are required by EKS. Without DNS hostnames the worker nodes cannot
  # resolve the cluster API endpoint and never join.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.vpc_name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# Public subnets. The worker nodes and both LoadBalancer services (Jenkins and
# Argo CD) live here.
#
# The kubernetes.io/role/elb tag is what makes the AWS cloud controller pick
# these subnets when a Service of type LoadBalancer is created. Without it the
# service stays in <pending> forever with no obvious error.
resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.vpc_name}-public-${count.index + 1}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Private subnets. Not used by the cluster in this setup, but created because
# the task asks for a VPC with both kinds, and because moving the node group
# here later is only a matter of changing one input in main.tf.
resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                        = "${var.vpc_name}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}
