@echo off
setlocal
where pwsh.exe >nul 2>nul
if errorlevel 1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-patch.ps1" %*
) else (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-patch.ps1" %*
)
set "codex_patch_exit=%errorlevel%"
if "%~1"=="" pause
exit /b %codex_patch_exit%
