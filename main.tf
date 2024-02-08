terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "MainVPC"
  }
}

resource "aws_internet_gateway" "ig1" {
  vpc_id = aws_vpc.main.id
}

# Subnet for the instances and RDS
resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "eu-west-1a"
  tags = {
    Name = "MainSubnet"
  }
}

resource "aws_subnet" "additional" {
  vpc_id          = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-west-1b"
  tags = {
    Name = "AdditionalSubnet"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "my-db-subnet-group"
  subnet_ids = [aws_subnet.main.id, aws_subnet.additional.id]

  tags = {
    Name = "My DB Subnet Group"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "my-rds-sg"
  description = "Security group for RDS PostgreSQL instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "my-cache-subnet-group"
  subnet_ids = [aws_subnet.main.id] # Assuming the same subnet as for RDS

  tags = {
    Name = "My Cache Subnet Group"
  }
}

# Security Group for EC2 Instances
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-sg"
  }
}

# Security Group for ELB
resource "aws_security_group" "elb_sg" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "elb-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "main-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb_sg.id]
  subnets            = [aws_subnet.main.id, aws_subnet.additional.id]

  enable_deletion_protection = false

  tags = {
    Name = "mainLB"
  }
}

# Target Group for the Application Load Balancer
resource "aws_lb_target_group" "main" {
  name     = "main-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

resource "aws_lb_listener_rule" "block_prepare_for_deploy" {
  listener_arn = aws_lb_listener.http_listener.arn
  priority     = 100

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "This endpoint is blocked."
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = ["/prepare-for-deploy"]
    }
  }
}

resource "aws_lb_listener_rule" "block_ready_for_deploy" {
  listener_arn = aws_lb_listener.http_listener.arn
  priority     = 101

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "This endpoint is blocked."
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = ["/ready-for-deploy"]
    }
  }
}


# EC2 Instances
resource "aws_instance" "app" {
  count         = 2
  ami           = "ami-0da9e5d20774e4bac"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.main.id
  security_groups = [aws_security_group.ec2_sg.id]

  key_name        = aws_key_pair.deployer_key.key_name

  tags = {
    Name = "AppInstance-${count.index}"
  }

   associate_public_ip_address = true

   user_data = <<-EOF
              #!/bin/bash
              # Create phrase_admin user
              adduser phrase_admin
              mkdir -p /home/phrase_admin/.ssh
              echo "<phrase_admin_key>" > /home/phrase_admin/.ssh/authorized_keys
              chmod 700 /home/phrase_admin/.ssh
              chmod 600 /home/phrase_admin/.ssh/authorized_keys
              chown -R phrase_admin:phrase_admin /home/phrase_admin/.ssh
              echo "phrase_admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/phrase_admin

              # Create phrase_user user
              adduser phrase_user
              mkdir -p /home/phrase_user/.ssh
              echo "<phrase_user_key>" > /home/phrase_user/.ssh/authorized_keys
              chmod 700 /home/phrase_user/.ssh
              chmod 600 /home/phrase_user/.ssh/authorized_keys
              chown -R phrase_user:phrase_user /home/phrase_user/.ssh
              EOF
}

# Attach EC2 Instances to Target Group
resource "aws_lb_target_group_attachment" "app" {
  count            = length(aws_instance.app.*.id)

  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.app[count.index].id
  port             = 80 # Ensure this matches the port your application listens on
}

# RDS PostgreSQL Database
resource "aws_db_instance" "main_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  engine_version       = "15.5"
  instance_class       = "db.t3.micro"
  #db_name              = "postgres_db"
  username             = "dbuser"
  password             = "dbpassword"
  parameter_group_name = "default.postgres15"
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true
}

# ElastiCache Redis
resource "aws_elasticache_cluster" "main_cache" {
  cluster_id           = "redis-cluster"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  #parameter_group_name = "default.redis7.0"
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.elasticache_sg.id]
}

resource "aws_security_group" "elasticache_sg" {
  name        = "my-elasticache-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "elasticache-sg"
  }
}


resource "aws_key_pair" "deployer_key" {
  key_name   = "deployer-key"
  public_key = "<your_public_key_goes_here"
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ig1.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

# Associate the route table with your subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.public.id
}

resource "aws_ecr_repository" "phrase_repository" {
  name                 = "phrase-repository" # Name your repository
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }
  
  tags = {
    ManagedBy = "Terraform"
  }
}

output "ecr_repository_url" {
  value = aws_ecr_repository.phrase_repository.repository_url
}

# Output for PostgreSQL Endpoint
output "postgres_endpoint" {
  value       = aws_db_instance.main_db.endpoint
}

# Output for Redis Endpoint
output "redis_endpoint" {
  value       = aws_elasticache_cluster.main_cache.cache_nodes[0].address
}

output "ec2_instance_ips" {
  value = aws_instance.app[*].public_ip
}

