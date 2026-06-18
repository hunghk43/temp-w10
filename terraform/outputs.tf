output "secret_arn" {
  description = "ARN của secret trong AWS Secrets Manager"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "secret_path" {
  description = "Path để dùng trong ExternalSecret remoteRef.key"
  value       = aws_secretsmanager_secret.db_password.name
}

output "iam_user_name" {
  description = "IAM user cho ESO auth"
  value       = aws_iam_user.eso.name
}

output "access_key_id" {
  description = "AWS Access Key ID — dùng để tạo K8s Secret aws-creds"
  value       = aws_iam_access_key.eso.id
}

output "secret_access_key" {
  description = "AWS Secret Access Key — dùng để tạo K8s Secret aws-creds"
  value       = aws_iam_access_key.eso.secret
  sensitive   = true # chỉ hiện khi chạy: terraform output secret_access_key
}

output "kubectl_create_secret_cmd" {
  description = "Lệnh tạo K8s Secret aws-creds (chạy sau terraform apply)"
  value       = "kubectl create secret generic aws-creds --from-literal=access-key=${aws_iam_access_key.eso.id} --from-literal=secret-key=$(terraform output -raw secret_access_key) -n demo"
}
