<#
.SYNOPSIS
    Complete Uninstaller for Android PC Keep-Awake
#>

Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host "         Android PC Keep-Awake - Uninstaller              " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "[*] Stopping running daemon processes..." -ForegroundColor Yellow
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*phone-watcher.ps1*" } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Host "[+] Terminated Process ID: $($_.ProcessId)" -ForegroundColor Green
}

$startupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) "PhoneKeepAwake.lnk"
if (Test-Path $startupShortcut) {
    Remove-Item $startupShortcut -Force
    Write-Host "[+] Removed Windows Startup shortcut." -ForegroundColor Green
}

$installDir = Join-Path $env:USERPROFILE ".phone-keep-awake"
if (Test-Path $installDir) {
    Remove-Item -Recurse -Force $installDir -ErrorAction SilentlyContinue
    Write-Host "[+] Removed installation directory: $installDir" -ForegroundColor Green
}

# Optional phone reset check
$adb = Get-Command adb -ErrorAction SilentlyContinue
if ($adb) {
    $devs = & $adb.Source devices 2>$null | Where-Object { $_ -match "\bdevice\b" -and $_ -notmatch "List of devices" }
    if ($devs) {
        $devId = ($devs[0] -split "\s+")[0]
        & $adb.Source -s $devId shell settings put global stay_on_while_plugged_in 0 2>$null
        Write-Host "[+] Verified phone default sleep timeout is restored." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Uninstallation complete. All components have been removed." -ForegroundColor Cyan
