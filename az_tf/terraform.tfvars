# Values come from `terraform output` in bootstrap/ after `terraform apply`
# there. Both change on every bootstrap apply (random suffix), so update this
# file before applying az_tf/.
resource_group_name = "REPLACE_WITH_bootstrap_output_resource_group_name"
name_suffix         = "REPLACE_WITH_bootstrap_output_name_suffix"
