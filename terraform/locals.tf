locals {
  common_tags = {
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "terraform"
    Owner       = "cloud-accelerator-w10"
  }
}
