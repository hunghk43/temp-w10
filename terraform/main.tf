terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

# Secret: db password cho ESO sync vào K8s
resource "aws_secretsmanager_secret" "db_password" {
  name                    = var.secret_path
  description             = "DB password cho ESO lab 2.1 — sync vào ns demo"
  recovery_window_in_days = 0 # xóa ngay (lab env, không cần recovery)

  tags = local.common_tags
}

# Initial value — JSON format vì ExternalSecret dùng property: password
resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    password = var.db_password
  })
}

# IAM user cho ESO auth (lab minikube — không có IRSA)
resource "aws_iam_user" "eso" {
  name = "${var.project_name}-eso-user"
  tags = local.common_tags
}

# Policy: chỉ cho đọc secret này, không quyền gì khác
resource "aws_iam_policy" "eso_read_secret" {
  name        = "${var.project_name}-eso-read-secret"
  description = "Cho phép ESO đọc secret db_password"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.db_password.arn
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "eso" {
  user       = aws_iam_user.eso.name
  policy_arn = aws_iam_policy.eso_read_secret.arn
}

# Access key cho IAM user — dùng để tạo K8s Secret aws-creds
resource "aws_iam_access_key" "eso" {
  user = aws_iam_user.eso.name
}
