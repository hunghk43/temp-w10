variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Prefix cho resource"
  type        = string
  default     = "w10-lab"
}

variable "secret_path" {
  description = "Path của secret trong AWS Secrets Manager — phải khớp với ExternalSecret remoteRef.key"
  type        = string
  default     = "prod/api/db"
}

variable "db_password" {
  description = "Giá trị DB password ban đầu — thay đổi trực tiếp trên AWS console để test rotate"
  type        = string
  sensitive   = true # ẩn khỏi terraform output/log
}
