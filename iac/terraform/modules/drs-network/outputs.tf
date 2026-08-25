output "dr_vpc_id" {
  description = "ID of the DR VPC"
  value       = aws_vpc.dr_vpc.id
}

output "dr_subnet_id" {
  description = "ID of the DR staging subnet"
  value       = aws_subnet.dr_staging_subnet.id
}

output "dr_security_group_id" {
  description = "ID of the DR staging security group"
  value       = aws_security_group.dr_staging.id
}

output "dr_kms_key_arn" {
  description = "ARN of the DR KMS key"
  value       = aws_kms_key.dr_encryption.arn
}

output "drs_source_server_id" {
  description = "ID of the DRS source server"
  value       = var.source_server_id
}
