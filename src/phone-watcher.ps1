<#
.SYNOPSIS
    Android PC Keep-Awake Daemon (Resilient Version)
.DESCRIPTION
    Monitors Android USB connection and keeps the device screen awake
    ONLY while connected to this specific computer.
#>

param(
    [string]$TargetDevice = "ZA223PXXMC",
    [int]$IntervalSec = 10
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
$consecutiveFailures = 0

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
            $consecutiveFailures = 0

            # Query display power status safely joining array to single string
            $wakefulnessRaw = (& $adb -s $activeDevice shell "dumpsys power | grep 'mWakefulness='" 2>$null) -join " "

            # If device is asleep or dozing upon connection, wake it up
            if ($wakefulnessRaw -notmatch "mWakefulness=Awake") {
                & $adb -s $activeDevice shell cmd power wakeup 2>$null
            }

            # Pulse gentle user activity keyevent (KEYCODE_UNKNOWN) to reset idle timeout
            & $adb -s $activeDevice shell input keyevent 0 2>$null

            Start-Sleep -Seconds $IntervalSec
        } else {
            # Device not seen in ADB. Check if Windows physically sees the phone via USB.
            $pnpPhone = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { 
                $_.FriendlyName -match "motorola|moto|android" -or $_.InstanceId -match "VID_22B8" 
            }

            if ($pnpPhone) {
                # Phone is physically connected, but ADB server lost track of it.
                $consecutiveFailures++
                if ($consecutiveFailures -ge 3) {
                    # Restart ADB server to recover stale socket
                    & $adb reconnect 2>$null
                    & $adb kill-server 2>$null
                    Start-Sleep -Seconds 1
                    & $adb start-server 2>$null
                    $consecutiveFailures = 0
                }
            }

            Start-Sleep -Seconds 3
        }
    } catch {
        Start-Sleep -Seconds 5
    }
}
