# ------------------------------------------------------------------------------
# Resources
# ------------------------------------------------------------------------------
data "aws_availability_zones" "main" {}

data "aws_region" "current" {}

locals {
  azs               = length(var.availability_zones) > 0 ? var.availability_zones : data.aws_availability_zones.main.names
  nat_gateway_count = var.create_nat_gateways ? 1 : 0
}

resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(
    var.tags,
    {
      "Name" = "${var.vpc_name}"
    },
  )
}

resource "aws_internet_gateway" "public" {
  count      = length(var.public_subnet_cidrs) > 0 ? 1 : 0
  depends_on = [aws_vpc.main]
  vpc_id     = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      "Name" = "${var.vpc_name}-public-igw"
    },
  )
}

resource "aws_egress_only_internet_gateway" "outbound" {
  count      = length(var.public_subnet_cidrs) > 0 ? 1 : 0
  depends_on = [aws_vpc.main]
  vpc_id     = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  count      = length(var.public_subnet_cidrs) > 0 ? 1 : 0
  depends_on = [aws_vpc.main]
  vpc_id     = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      "Name" = "${var.name_prefix}-public-rt"
    },
  )
}

resource "aws_route" "public" {
  count = length(var.public_subnet_cidrs) > 0 ? 1 : 0
  depends_on = [
    aws_internet_gateway.public,
    aws_route_table.public,
  ]
  route_table_id         = aws_route_table.public[0].id
  gateway_id             = aws_internet_gateway.public[0].id
  destination_cidr_block = "0.0.0.0/0"
}


resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = element(local.azs, count.index)
  map_public_ip_on_launch = var.map_public_ip_on_launch
  tags = merge(
    var.tags,
    {
      "Name"                   = "${var.name_prefix}-public-subnet-${count.index + 1}"
      "Tier"                   = "Public"
      "Subent"                 = "Public"
      "kubernetes.io/role/elb" = "1"
    },
  )
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_eip" "private" {
  count = local.nat_gateway_count

  tags = merge(
    var.tags,
    {
      "Name" = "${var.name_prefix}-nat-gateway-${count.index + 1}"
    },
  )
}

resource "aws_nat_gateway" "private" {
  depends_on = [
    aws_internet_gateway.public,
    aws_eip.private,
  ]
  count         = local.nat_gateway_count
  allocation_id = aws_eip.private[count.index].id
  subnet_id     = element(aws_subnet.public[*].id, count.index)

  tags = merge(
    var.tags,
    {
      "Name" = "${var.name_prefix}-nat-gateway"
    },
  )
}

resource "aws_route_table" "private" {
  depends_on = [aws_vpc.main]
  count      = length(var.private_subnet_cidrs) > 0 ? 1 : 0
  vpc_id     = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      "Name" = "${var.name_prefix}-private-rt"
    },
  )
}

resource "aws_route" "private" {
  depends_on = [
    aws_nat_gateway.private,
    aws_route_table.private,
  ]
  count                  = local.nat_gateway_count > 0 ? 1 : 0
  route_table_id         = aws_route_table.private[0].id
  nat_gateway_id         = element(aws_nat_gateway.private[*].id, 0)
  destination_cidr_block = "0.0.0.0/0"
}



resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = element(local.azs, count.index)
  map_public_ip_on_launch = false
  tags = merge(
    var.tags,
    {
      "Name"                            = "${var.name_prefix}-private-subnet-${count.index + 1}"
      "Tier"                            = "Private"
      "Subent"                          = "Private"
      "eks"                             = var.name_prefix
      "kubernetes.io/role/internal-elb" = "1"
    },
  )
}


resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}


