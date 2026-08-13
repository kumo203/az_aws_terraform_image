@echo off
rem Thin wrapper - the actual logic (az CLI lookups, JSON handling, .env
rem generation) lives in setup-env.ps1. Forwards optional override args, e.g.:
rem   setup-env.bat -ServerName ai-prj-litellm-5b2e176d-pg
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-env.ps1" %*
