<#
.SYNOPSIS
    Android PC Keep-Awake - Live Diagnostics & Status
#>

$host.UI.RawUI.WindowTitle = "Android PC Keep-Awake - Status"
Clear-Host

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "       Android PC Keep-Awake - Live Diagnostics      " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Daemon Status
$daemonProcs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*phone-watcher.ps1*" }
if ($daemonProcs) {
    $proc = $daemonProcs[0]
    $p = Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue
    $memMB = if ($p) { [math]::Round($p.WorkingSet64 / 1MB, 2) } else { "N/A" }
    Write-Host "[Daemon]" -ForegroundColor Green
    Write-Host "  Status:        RUNNING" -ForegroundColor Green
    Write-Host "  Process ID:    $($proc.ProcessId)" -ForegroundColor White
    Write-Host "  Memory Usage:  $memMB MB" -ForegroundColor White
} else {
    Write-Host "[Daemon]" -ForegroundColor Red
    Write-Host "  Status:        STOPPED" -ForegroundColor Red
}

# 2. Windows Startup Shortcut
$startupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) "PhoneKeepAwake.lnk"
Write-Host ""
Write-Host "[Windows Startup]" -ForegroundColor Yellow
if (Test-Path $startupShortcut) {
    Write-Host "  Auto-Start:    ENABLED" -ForegroundColor Green
    Write-Host "  Shortcut:      $startupShortcut" -ForegroundColor Gray
} else {
    Write-Host "  Auto-Start:    DISABLED" -ForegroundColor Red
}

# 3. ADB & Device Status
Write-Host ""
Write-Host "[Android Device]" -ForegroundColor Yellow

$adbPaths = @(
    (Get-Command adb -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe",
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
)
$adb = $adbPaths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $adb) {
    Write-Host "  ADB Status:    NOT FOUND" -ForegroundColor Red
} else {
    $devicesOutput = & $adb devices 2>$null
    $deviceLines = ($devicesOutput -split "`r?`n") | Where-Object { $_ -match "\bdevice\b" -and $_ -notmatch "List of devices" }

    if ($deviceLines.Count -eq 0) {
        Write-Host "  Connected:     NO" -ForegroundColor Yellow
        $pnp = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "motorola|moto|android" }
        if ($pnp) {
            Write-Host "  Physical USB:  DETECTED ($($pnp[0].FriendlyName)) - ADB not authorized yet or offline" -ForegroundColor Yellow
        } else {
            Write-Host "  Physical USB:  Not detected" -ForegroundColor Gray
        }
    } else {
        $devId = ($deviceLines[0] -split "\s+")[0]
        $model = (& $adb -s $devId shell getprop ro.product.model 2>$null).Trim()
        $battery = (& $adb -s $devId shell "dumpsys battery | grep level" 2>$null) -replace "[^0-9]",""
        $status = (& $adb -s $devId shell "cat /sys/class/power_supply/battery/status 2>/dev/null").Trim()
        $wake = (& $adb -s $devId shell "dumpsys power | grep 'mWakefulness='" 2>$null)

        $wakeStr = if ($wake -match "mWakefulness=Awake") { "AWAKE (Screen On)" } elseif ($wake -match "mWakefulness=Dozing") { "DOZING (Ambient / Screen Off)" } else { "ASLEEP" }

        Write-Host "  Connected:     YES" -ForegroundColor Green
        Write-Host "  Device ID:     $devId" -ForegroundColor White
        Write-Host "  Model:         $model" -ForegroundColor White
        Write-Host "  Battery:       $battery% ($status)" -ForegroundColor White
        Write-Host "  Screen State:  $wakeStr" -ForegroundColor $(if ($wake -match "mWakefulness=Awake") { "Green" } else { "Yellow" })
    }
}

# 4. Recent Logs
$logFile = Join-Path $env:USERPROFILE ".phone-keep-awake\daemon.log"
Write-Host ""
Write-Host "[Recent Activity Log]" -ForegroundColor Cyan
if (Test-Path $logFile) {
    Get-Content $logFile -Tail 6 | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Gray
    }
} else {
    Write-Host "  (No log file created yet)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "Press any key to exit..." -ForegroundColor Gray
if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
    try {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } catch {}
}
