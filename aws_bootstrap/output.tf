output "state_bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}

output "lock_table_name" {
  value = aws_dynamodb_table.tfstate_lock.name
}

# Feed this into aws_tf/terraform.tfvars (var.name_suffix) so aws_tf's
# resources share this same naming namespace.
output "name_suffix" {
  value = local.name_suffix
}
