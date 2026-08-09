# Values come from `terraform output` in bootstrap/ after `terraform apply`
# there. resource_group_name/storage_account_name change on every bootstrap
# apply (random suffix), so update this file before initializing az_tf/.
resource_group_name  = "REPLACE_WITH_bootstrap_output_resource_group_name"
storage_account_name = "REPLACE_WITH_bootstrap_output_storage_account_name"
container_name        = "tfstate"
key                    = "az_tf.tfstate"
use_azuread_auth       = true
