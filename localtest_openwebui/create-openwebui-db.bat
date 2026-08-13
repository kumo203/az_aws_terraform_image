@echo off
setlocal enabledelayedexpansion

rem Creates the "openwebui" database on the existing az_litellm_tf Postgres
rem Flexible Server (kept separate from LiteLLM's own "litellm" database).
rem One-off; safe to re-run - az CLI just errors harmlessly if it already
rem exists.
rem
rem Uses only the az CLI (no terraform command / az_litellm_tf checkout
rem required). Pass a server name explicitly if auto-detection is ambiguous:
rem   create-openwebui-db.bat <postgres-server-name>

set "SERVER=%~1"

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
  echo Pass the server name explicitly: create-openwebui-db.bat ^<server-name^>
  exit /b 1
)
if "%RG%"=="" (
  echo Could not resolve resource group for server %SERVER%.
  exit /b 1
)

echo Creating "openwebui" database on %SERVER% (%RG%)...
az postgres flexible-server db create ^
  --resource-group "%RG%" ^
  --server-name "%SERVER%" ^
  --name openwebui

endlocal
