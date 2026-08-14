@echo off
setlocal enabledelayedexpansion

rem Removes the temporary firewall rule added by allow-local-ip.bat. Run this
rem once local Open WebUI testing is done.
rem
rem Uses only the az CLI (no terraform command / az_litellm_tf checkout
rem required). Pass a server name explicitly if auto-detection is ambiguous:
rem   remove-local-ip.bat <postgres-server-name>

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
  echo Pass the server name explicitly: remove-local-ip.bat ^<server-name^>
  exit /b 1
)
if "%RG%"=="" (
  echo Could not resolve resource group for server %SERVER%.
  exit /b 1
)

echo Removing temp-openwebui-local firewall rule from %SERVER% (%RG%)...
az postgres flexible-server firewall-rule delete ^
  --resource-group "%RG%" ^
  --server-name "%SERVER%" ^
  --name temp-openwebui-local ^
  --yes

endlocal
