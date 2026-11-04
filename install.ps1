<#
.SYNOPSIS
    Automated Setup & Installer for Android PC Keep-Awake
#>

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     Android PC Keep-Awake - Automated Setup & Install    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Locate or Install ADB
$adb = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adb) {
    Write-Host "[*] ADB not found in system PATH. Attempting automated install via winget..." -ForegroundColor Yellow
    try {
        winget install --id Google.PlatformTools --exact --silent --accept-source-agreements --accept-package-agreements
        Write-Host "[+] Installed Android Platform Tools via winget." -ForegroundColor Green
        $adb = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe"
    } catch {
        Write-Warning "winget automated install failed. Please install Android Platform Tools manually."
    }
} else {
    $adb = $adb.Source
    Write-Host "[+] ADB located at: $adb" -ForegroundColor Green
}

# 2. Detect Connected Devices
$targetDevice = ""
if ($adb -and (Test-Path $adb)) {
    & $adb start-server 2>$null
    $rawDevices = & $adb devices 2>$null
    $deviceLines = ($rawDevices -split "`r?`n") | Where-Object { $_ -match "\bdevice\b" -and $_ -notmatch "List of devices" }

    if ($deviceLines.Count -gt 0) {
        $devId = ($deviceLines[0] -split "\s+")[0]
        $model = (& $adb -s $devId shell getprop ro.product.model 2>$null).Trim()
        Write-Host "[+] Detected connected device: $model (ID: $devId)" -ForegroundColor Green
        $targetDevice = $devId
    } else {
        Write-Host "[!] No authorized device detected right now. Daemon will run in dynamic detection mode." -ForegroundColor Yellow
    }
}

# 3. Setup Target Installation Directory
$installDir = Join-Path $env:USERPROFILE ".phone-keep-awake"
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

$scriptDir = $PSScriptRoot

# Create or update config.json
$configPath = Join-Path $installDir "config.json"
$configData = @{
    targetDeviceId    = $targetDevice
    intervalSeconds   = 4
    autoWakeOnConnect = $true
    enableLogging     = $true
    maxLogSizeBytes   = 1048576
}
$configData | ConvertTo-Json -Depth 4 | Set-Content -Path $configPath -Encoding UTF8
Write-Host "[+] Configuration saved to: $configPath" -ForegroundColor Green

# Copy scripts
Copy-Item (Join-Path $scriptDir "src\phone-watcher.ps1") -Destination $installDir -Force
Copy-Item (Join-Path $scriptDir "src\launch-hidden.vbs") -Destination $installDir -Force
Copy-Item (Join-Path $scriptDir "status.ps1") -Destination $installDir -Force
Copy-Item (Join-Path $scriptDir "status.bat") -Destination $installDir -Force
Copy-Item (Join-Path $scriptDir "stop-watcher.bat") -Destination $installDir -Force

# 4. Create Windows Startup Shortcut
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

Write-Host "[+] Windows Startup shortcut registered at:" -ForegroundColor Green
Write-Host "    $shortcutPath" -ForegroundColor Gray

# 5. Stop existing instances and launch freshly
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*phone-watcher.ps1*" } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

$startCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installDir\phone-watcher.ps1`""
$res = ([wmiclass]"win32_process").Create($startCmd)

Start-Sleep -Seconds 2
$running = Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -eq $res.ProcessId }

if ($running) {
    Write-Host "[+] Daemon is actively running in background (PID: $($res.ProcessId))" -ForegroundColor Green
} else {
    Write-Host "[!] Note: Daemon could not be verified immediately. Run status.bat to inspect." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Installation Successful! Your phone will stay awake      " -ForegroundColor Green
Write-Host " exclusively when plugged into this computer.             " -ForegroundColor Green
Write-Host " Run status.bat anytime to view live diagnostics.         " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
