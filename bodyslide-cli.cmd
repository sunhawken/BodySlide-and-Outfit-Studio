@echo off
setlocal
set "BSCLI_ROOT=%~dp0"
where pwsh.exe >nul 2>nul
if not errorlevel 1 (
  pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%BSCLI_ROOT%bodyslide-cli.ps1" %*
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%BSCLI_ROOT%bodyslide-cli.ps1" %*
)
exit /b %errorlevel%
