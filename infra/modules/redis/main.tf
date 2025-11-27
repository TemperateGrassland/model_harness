# Redis Module for Rate Limiting
# This module creates an ElastiCache Redis cluster for rate limiting

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for Redis"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "ECS security group ID that needs access to Redis"
  type        = string
}

variable "node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "num_cache_nodes" {
  description = "Number of cache nodes"
  type        = number
  default     = 1
}

# Redis Security Group
resource "aws_security_group" "redis_sg" {
  name_prefix = "${var.name_prefix}-redis-"
  vpc_id      = var.vpc_id
  description = "Security group for Redis cluster"

  ingress {
    description     = "Redis port from ECS"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.ecs_security_group_id]
  }

  tags = {
    Name         = "${var.name_prefix}-redis-sg"
    ResourceType = "security-group"
    Function     = "redis-access"
  }
}

# Redis Subnet Group
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "${var.name_prefix}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name         = "${var.name_prefix}-redis-subnet-group"
    ResourceType = "elasticache-subnet-group"
    Function     = "redis-networking"
  }
}

# Redis Parameter Group
resource "aws_elasticache_parameter_group" "redis_params" {
  family = "redis7"
  name   = "${var.name_prefix}-redis-params"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = {
    Name         = "${var.name_prefix}-redis-params"
    ResourceType = "elasticache-parameter-group"
    Function     = "redis-configuration"
  }
}

# ElastiCache Redis Cluster
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.name_prefix}-redis"
  engine               = "redis"
  node_type            = var.node_type
  num_cache_nodes      = var.num_cache_nodes
  parameter_group_name = aws_elasticache_parameter_group.redis_params.name
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids   = [aws_security_group.redis_sg.id]

  # Enable backups for production
  snapshot_retention_limit = 1
  snapshot_window         = "03:00-05:00"
  maintenance_window      = "sun:05:00-sun:06:00"

  tags = {
    Name         = "${var.name_prefix}-redis"
    ResourceType = "elasticache-cluster"
    Function     = "rate-limiting"
    Environment  = "production"
  }
}

# Outputs
output "redis_endpoint" {
  description = "Redis cluster endpoint"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].port
}