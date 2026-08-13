# Values come from `terraform output` in aws_bootstrap/ after `terraform
# apply` there. bucket/dynamodb_table change on every bootstrap apply
# (random suffix), so update this file before initializing aws_tf/.
bucket         = "REPLACE_WITH_bootstrap_output_state_bucket_name"
key            = "aws_tf.tfstate"
region         = "us-east-1"
dynamodb_table = "REPLACE_WITH_bootstrap_output_lock_table_name"
encrypt        = true
