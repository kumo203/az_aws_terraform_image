# Values come from `terraform output` in bootstrap/ after `terraform apply`
# there. Both change on every bootstrap apply (random suffix), so update this
# file before applying az_litellm_tf/. Same shared resource group as az_tf/ —
# variables.tf's resource_prefix default ("ai-prj-litellm") already differs
# from az_tf/'s ("ai-prj-sample") so resource names don't collide within it.
resource_group_name = "REPLACE_WITH_bootstrap_output_resource_group_name"
name_suffix         = "REPLACE_WITH_bootstrap_output_name_suffix"

# Verify the current stable release tag at https://github.com/berriai/litellm/pkgs/container/litellm-database
# before applying — never use `latest`/`main-latest` (see variables.tf).
litellm_image_tag = "main-v1.83.14-stable"

# Ad hoc psql access for verifying Prisma table creation etc. Uncomment and
# replace with your current local/workstation IP when needed, then comment
# out again (or apply with an empty list) once done — do not leave a real IP
# committed here.
# postgres_admin_source_ip_ranges = ["0.0.0.0"]
