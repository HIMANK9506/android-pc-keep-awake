<#
.SYNOPSIS
    Android PC Keep-Awake Daemon
.DESCRIPTION
    Monitors Android USB connection and keeps the device screen awake
    ONLY while connected to this specific computer.
#>

param(
    [string]$TargetDevice = "",
    [int]$IntervalSec = 3
)

# 1. Locate ADB executable
function Find-Adb {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $knownPaths = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe",
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:ProgramFiles\Android\platform-tools\adb.exe",
        "$env:ProgramFiles(x86)\Android\platform-tools\adb.exe"
    )

    foreach ($path in $knownPaths) {
        if (Test-Path $path) { return $path }
    }

    # Deep search in WinGet packages as fallback
    $wingetMatch = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet" -Recurse -Filter "adb.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wingetMatch) { return $wingetMatch.FullName }

    return $null
}

$adb = Find-Adb
if (-not $adb) {
    Write-Error "ADB executable not found. Please install Android Platform Tools."
    exit 1
}

# 2. Main Keep-Awake Loop
while ($true) {
    try {
        $rawDevices = & $adb devices 2>$null
        $deviceLines = $rawDevices | Where-Object { $_ -match "\bdevice\b" -and $_ -notmatch "List of devices" }

        # Resolve target device
        $activeDevice = $null
        if ($TargetDevice) {
            if ($rawDevices -match "$TargetDevice\s+device") {
                $activeDevice = $TargetDevice
            }
        } elseif ($deviceLines.Count -gt 0) {
            $activeDevice = ($deviceLines[0] -split "\s+")[0]
        }

        if ($activeDevice) {
            # Query display power status
            $wakefulness = & $adb -s $activeDevice shell "dumpsys power | grep 'mWakefulness='" 2>$null

            # If device is asleep or dozing upon connection, wake it up
            if ($wakefulness -notmatch "mWakefulness=Awake") {
                & $adb -s $activeDevice shell cmd power wakeup 2>$null
            }

            # Pulse user activity keyevent to prevent lockscreen and idle timeouts
            & $adb -s $activeDevice shell input keyevent 0 2>$null

            Start-Sleep -Seconds $IntervalSec
        } else {
            # Device disconnected: poll periodically with minimal CPU overhead
            Start-Sleep -Seconds 2
        }
    } catch {
        Start-Sleep -Seconds 3
    }
}
