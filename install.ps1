<#
.SYNOPSIS
    Installer for Android PC Keep-Awake
#>

$ErrorActionPreference = "Stop"

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   Android PC Keep-Awake - Setup & Install   " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# 1. Check for ADB
$adb = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adb) {
    Write-Host "[*] ADB not found in PATH. Checking via winget..." -ForegroundColor Yellow
    try {
        winget install --id Google.PlatformTools --exact --silent --accept-source-agreements --accept-package-agreements
        Write-Host "[+] Installed Android Platform Tools via winget." -ForegroundColor Green
    } catch {
        Write-Warning "Could not install via winget automatically. Please ensure ADB is installed."
    }
} else {
    Write-Host "[+] ADB found: $($adb.Source)" -ForegroundColor Green
}

# 2. Setup user app folder
$installDir = Join-Path $env:USERPROFILE ".phone-keep-awake"
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

$scriptDir = $PSScriptRoot
Copy-Item (Join-Path $scriptDir "src\phone-watcher.ps1") -Destination $installDir -Force
Copy-Item (Join-Path $scriptDir "src\launch-hidden.vbs") -Destination $installDir -Force

# 3. Create Windows Startup shortcut
$wsh = New-Object -ComObject WScript.Shell
$startupFolder = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupFolder "PhoneKeepAwake.lnk"

$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "wscript.exe"
$shortcut.Arguments = "`"$installDir\launch-hidden.vbs`""
$shortcut.WorkingDirectory = $installDir
$shortcut.WindowStyle = 7
$shortcut.Description = "Keeps Android phone awake while connected to this PC"
$shortcut.Save()

Write-Host "[+] Startup shortcut registered at:" -ForegroundColor Green
Write-Host "    $shortcutPath" -ForegroundColor Gray

# 4. Stop existing instance & launch
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*phone-watcher.ps1*" } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

$startCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installDir\phone-watcher.ps1`""
$res = ([wmiclass]"win32_process").Create($startCmd)

if ($res.ReturnValue -eq 0) {
    Write-Host "[+] Watcher daemon is running in background (PID: $($res.ProcessId))" -ForegroundColor Green
} else {
    Write-Host "[!] Failed to launch background process automatically." -ForegroundColor Red
}

Write-Host ""
Write-Host "Setup complete! Your phone will stay awake whenever connected to this PC." -ForegroundColor Cyan
