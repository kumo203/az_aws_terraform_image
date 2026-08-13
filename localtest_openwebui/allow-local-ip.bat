@echo off
setlocal enabledelayedexpansion

rem Temporarily allow this workstation's public IP through the Azure Postgres
rem Flexible Server firewall so a locally-run Open WebUI container can reach
rem it directly. For ad hoc local testing only - run remove-local-ip.bat when
rem done. Not Terraform-managed on purpose (this rule should not be durable).
rem
rem Uses only the az CLI (no terraform command / az_litellm_tf checkout
rem required). Pass a server name explicitly if auto-detection is ambiguous:
rem   allow-local-ip.bat <postgres-server-name>

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
  echo Pass the server name explicitly: allow-local-ip.bat ^<server-name^>
  exit /b 1
)
if "%RG%"=="" (
  echo Could not resolve resource group for server %SERVER%.
  exit /b 1
)

for /f "usebackq delims=" %%A in (`curl -s https://ifconfig.me`) do set "MY_IP=%%A"
if "%MY_IP%"=="" (
  echo Failed to detect local public IP.
  exit /b 1
)

echo Server=%SERVER% ResourceGroup=%RG% IP=%MY_IP%

az postgres flexible-server firewall-rule create ^
  --resource-group "%RG%" ^
  --server-name "%SERVER%" ^
  --name temp-openwebui-local ^
  --start-ip-address "%MY_IP%" ^
  --end-ip-address "%MY_IP%"

endlocal
