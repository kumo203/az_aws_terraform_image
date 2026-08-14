@echo off
setlocal enabledelayedexpansion

rem Prints the LiteLLM Admin UI login credentials. When UI_USERNAME/
rem UI_PASSWORD aren't set (they aren't, in container_apps.tf), LiteLLM
rem defaults to Username=admin / Password=<LITELLM_MASTER_KEY>, read here
rem straight from Key Vault.
rem
rem Uses only the az CLI (no terraform command required). Pass names
rem explicitly if auto-detection is ambiguous:
rem   show-master-key.bat <postgres-server-name> <key-vault-name>

set "SERVER=%~1"
set "KV=%~2"

if "%SERVER%"=="" (
  for /f "usebackq tokens=1,2" %%A in (`az postgres flexible-server list --query "[?contains(name, 'litellm')].[name,resourceGroup]" -o tsv`) do (
    set "SERVER=%%A"
    set "RG=%%B"
  )
) else (
  for /f "usebackq delims=" %%A in (`az postgres flexible-server list --query "[?name=='%SERVER%'].resourceGroup" -o tsv`) do set "RG=%%A"
)

if "%SERVER%"=="" (
  echo Could not find a Postgres Flexible Server matching "litellm" in this subscription.
  echo Pass the server name explicitly: show-master-key.bat ^<server-name^> ^<key-vault-name^>
  exit /b 1
)
if "%RG%"=="" (
  echo Could not resolve resource group for server %SERVER%.
  exit /b 1
)

if "%KV%"=="" (
  for /f "usebackq delims=" %%A in (`az keyvault list --resource-group "%RG%" --query "[?contains(name,'litellm')].name" -o tsv`) do set "KV=%%A"
)
if "%KV%"=="" (
  echo Could not find a Key Vault matching "litellm" in resource group %RG%.
  echo Pass the key vault name explicitly: show-master-key.bat %SERVER% ^<key-vault-name^>
  exit /b 1
)

for /f "usebackq delims=" %%A in (`az keyvault secret show --vault-name "%KV%" --name litellm-master-key --query value -o tsv`) do set "MASTER_KEY=%%A"
if "%MASTER_KEY%"=="" (
  echo Failed to read litellm-master-key from Key Vault %KV%.
  echo Check you have the "Key Vault Secrets User" RBAC role ^(or higher^) on it.
  exit /b 1
)

echo.
echo LiteLLM Admin UI login:
echo   Username: admin
echo   Password: %MASTER_KEY%
echo.

endlocal
