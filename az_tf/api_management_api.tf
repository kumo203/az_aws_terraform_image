
resource "azurerm_api_management_api" "aoai" {
  name                = "azure-openai"
  resource_group_name = azurerm_resource_group.this.name
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
  resource_group_name = azurerm_resource_group.this.name
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
  resource_group_name = azurerm_resource_group.this.name
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

resource "azurerm_api_management_api_policy" "aoai" {
  api_name            = azurerm_api_management_api.aoai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  xml_content         = file("${path.module}/policies/aoai-api-policy.xml")

  depends_on = [time_sleep.rbac_propagation]
}
