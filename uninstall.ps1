<#
.SYNOPSIS
    Uninstaller for Android PC Keep-Awake
#>

Write-Host "Stopping any running Android PC Keep-Awake processes..." -ForegroundColor Yellow
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*phone-watcher.ps1*" } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Host "[+] Terminated Process ID: $($_.ProcessId)" -ForegroundColor Green
}

$startupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) "PhoneKeepAwake.lnk"
if (Test-Path $startupShortcut) {
    Remove-Item $startupShortcut -Force
    Write-Host "[+] Removed from Windows Startup." -ForegroundColor Green
}

$installDir = Join-Path $env:USERPROFILE ".phone-keep-awake"
if (Test-Path $installDir) {
    Remove-Item -Recurse -Force $installDir -ErrorAction SilentlyContinue
    Write-Host "[+] Cleaned installation folder: $installDir" -ForegroundColor Green
}

Write-Host ""
Write-Host "Uninstallation complete." -ForegroundColor Cyan
