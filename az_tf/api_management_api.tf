
resource "azurerm_api_management_api" "aoai" {
  name                = "azure-openai"
  resource_group_name = data.azurerm_resource_group.this.name
  api_management_name = azurerm_api_management.this.name
  revision            = "1"
  display_name        = "Azure OpenAI (Copilot gateway)"
  path                = ""
  protocols           = ["https"]

  # GitHub Copilot's BYOM client sends the standard AOAI "api-key" header, not
  # APIM's default "Ocp-Apim-Subscription-Key" — without this override every
  # request 401s at the gateway even with a valid subscription key.
  subscription_key_parameter_names {
    header = "api-key"
    query  = "api-key"
  }
}

resource "azurerm_api_management_api_operation" "chat_completions" {
  operation_id        = "chat-completions"
  api_name            = azurerm_api_management_api.aoai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name
  display_name        = "Chat Completions"
  method              = "POST"
  url_template        = "/openai/deployments/{deployment-id}/chat/completions"

  template_parameter {
    name     = "deployment-id"
    type     = "string"
    required = true
  }

  request {
    representation {
      content_type = "application/json"
    }
  }
}

resource "azurerm_api_management_api_operation" "embeddings" {
  operation_id        = "embeddings"
  api_name            = azurerm_api_management_api.aoai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name
  display_name        = "Embeddings"
  method              = "POST"
  url_template        = "/openai/deployments/{deployment-id}/embeddings"

  template_parameter {
    name     = "deployment-id"
    type     = "string"
    required = true
  }

  request {
    representation {
      content_type = "application/json"
    }
  }
}

# GitHub Copilot CLI's "azure" BYOK provider ignores any deployment path given
# in COPILOT_PROVIDER_BASE_URL and always calls the versionless
# "{host}/openai/v1/..." surface with the model named in the request body
# instead of the URL (confirmed via `--log-level debug`; see issue #4). Both
# Foundry and this API forward the incoming path unchanged to the backend, so
# these operations need no path parameter and no separate policy.
resource "azurerm_api_management_api_operation" "v1_chat_completions" {
  operation_id        = "v1-chat-completions"
  api_name            = azurerm_api_management_api.aoai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name
  display_name        = "Chat Completions (v1, model-in-body)"
  method              = "POST"
  url_template        = "/openai/v1/chat/completions"

  request {
    representation {
      content_type = "application/json"
    }
  }
}

resource "azurerm_api_management_api_operation" "v1_embeddings" {
  operation_id        = "v1-embeddings"
  api_name            = azurerm_api_management_api.aoai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name
  display_name        = "Embeddings (v1, model-in-body)"
  method              = "POST"
  url_template        = "/openai/v1/embeddings"

  request {
    representation {
      content_type = "application/json"
    }
  }
}

resource "azurerm_api_management_api_policy" "aoai" {
  api_name            = azurerm_api_management_api.aoai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name
  xml_content         = file("${path.module}/policies/aoai-api-policy.xml")

  depends_on = [time_sleep.rbac_propagation]
}
