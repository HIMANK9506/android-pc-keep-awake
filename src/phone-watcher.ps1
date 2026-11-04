<#
.SYNOPSIS
    Android PC Keep-Awake Daemon (Production Edition)
.DESCRIPTION
    Monitors Android USB connection and keeps the device screen awake
    ONLY while connected to this specific computer.
#>

param(
    [string]$ConfigFile = ""
)

# 1. Determine base directory and load config
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ConfigFile) {
    $potentialConfigs = @(
        (Join-Path $scriptDir "config.json"),
        (Join-Path (Split-Path -Parent $scriptDir) "config.json"),
        (Join-Path $env:USERPROFILE ".phone-keep-awake\config.json")
    )
    foreach ($p in $potentialConfigs) {
        if (Test-Path $p) {
            $ConfigFile = $p
            break
        }
    }
}

$config = @{
    targetDeviceId    = ""
    intervalSeconds   = 4
    autoWakeOnConnect = $true
    enableLogging     = $true
    maxLogSizeBytes   = 1048576
}

if ($ConfigFile -and (Test-Path $ConfigFile)) {
    try {
        $loaded = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        if ($loaded.targetDeviceId -ne $null)    { $config.targetDeviceId = [string]$loaded.targetDeviceId }
        if ($loaded.intervalSeconds -gt 0)      { $config.intervalSeconds = [int]$loaded.intervalSeconds }
        if ($loaded.autoWakeOnConnect -ne $null){ $config.autoWakeOnConnect = [bool]$loaded.autoWakeOnConnect }
        if ($loaded.enableLogging -ne $null)    { $config.enableLogging = [bool]$loaded.enableLogging }
        if ($loaded.maxLogSizeBytes -gt 0)      { $config.maxLogSizeBytes = [int]$loaded.maxLogSizeBytes }
    } catch {
        # Fallback to defaults if JSON parse fails
    }
}

$baseDir = if ($ConfigFile) { Split-Path -Parent $ConfigFile } else { $scriptDir }
if (-not $baseDir) { $baseDir = $PSScriptRoot }
$logFile = Join-Path $baseDir "daemon.log"

function Write-DaemonLog {
    param([string]$Message, [string]$Level = "INFO")
    if (-not $config.enableLogging) { return }

    try {
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $logLine = "[$timestamp] [$Level] $Message"

        # Rotate if log exceeds max size
        if (Test-Path $logFile) {
            $item = Get-Item $logFile -ErrorAction SilentlyContinue
            if ($item -and $item.Length -gt $config.maxLogSizeBytes) {
                $backup = "$logFile.old"
                Move-Item -Path $logFile -Destination $backup -Force -ErrorAction SilentlyContinue
            }
        }

        Add-Content -Path $logFile -Value $logLine -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # Never crash on logging error
    }
}

# 2. Locate ADB Executable
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
    Write-DaemonLog "ADB executable not found anywhere on system." "ERROR"
    exit 1
}

Write-DaemonLog "Daemon initialized. ADB path: $adb" "INFO"
if ($config.targetDeviceId) {
    Write-DaemonLog "Targeting configured device: $($config.targetDeviceId)" "INFO"
} else {
    Write-DaemonLog "Dynamic device detection mode active." "INFO"
}

# 3. Timeout-Guarded ADB Execution Helper
function Invoke-AdbTimeout {
    param(
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 5
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $adb
    $psi.Arguments = ($Arguments | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join " "
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $stdoutBuilder = New-Object System.Text.StringBuilder
    $stderrBuilder = New-Object System.Text.StringBuilder

    try {
        [void]$proc.Start()
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()

        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $proc.Kill() } catch {}
            Write-DaemonLog "ADB command timed out after ${TimeoutSeconds}s: $($psi.Arguments)" "WARN"
            return @{ ExitCode = -1; Stdout = ""; Stderr = "Timeout" }
        }

        [void]$outTask.Wait(1000)
        [void]$errTask.Wait(1000)

        return @{
            ExitCode = $proc.ExitCode
            Stdout   = $outTask.Result
            Stderr   = $errTask.Result
        }
    } catch {
        return @{ ExitCode = -1; Stdout = ""; Stderr = $_.ToString() }
    } finally {
        $proc.Dispose()
    }
}

# 4. Main Event Loop
$consecutiveFailures = 0
$lastConnectedState = $false

while ($true) {
    try {
        $res = Invoke-AdbTimeout -Arguments @("devices") -TimeoutSeconds 4
        $deviceLines = @(($res.Stdout -split "`r?`n") | Where-Object { $_ -match "\bdevice\b" -and $_ -notmatch "List of devices" })

        # Resolve active device
        $activeDevice = $null
        if ($config.targetDeviceId) {
            if ($res.Stdout -match "(?m)^$([regex]::Escape($config.targetDeviceId))\s+device\b") {
                $activeDevice = $config.targetDeviceId
            }
        } elseif ($deviceLines.Count -gt 0) {
            $activeDevice = ($deviceLines[0] -split "\s+")[0]
        }

        if ($activeDevice) {
            $consecutiveFailures = 0

            if (-not $lastConnectedState) {
                Write-DaemonLog "Device connected and authorized: $activeDevice" "INFO"
                $lastConnectedState = $true
            }

            # Check wakefulness status
            $powerRes = Invoke-AdbTimeout -Arguments @("-s", $activeDevice, "shell", "dumpsys power | grep 'mWakefulness='") -TimeoutSeconds 4
            $wakeState = $powerRes.Stdout

            # Auto-wake if device is asleep or dozing
            if ($config.autoWakeOnConnect -and ($wakeState -notmatch "mWakefulness=Awake")) {
                Write-DaemonLog "Screen was off/dozing. Sending wakeup signal..." "DEBUG"
                [void](Invoke-AdbTimeout -Arguments @("-s", $activeDevice, "shell", "cmd power wakeup") -TimeoutSeconds 3)
            }

            # Pulse gentle user activity keyevent (KEYCODE_UNKNOWN) to reset idle timer
            [void](Invoke-AdbTimeout -Arguments @("-s", $activeDevice, "shell", "input keyevent 0") -TimeoutSeconds 3)

            Start-Sleep -Seconds $config.intervalSeconds
        } else {
            if ($lastConnectedState) {
                Write-DaemonLog "Device disconnected from laptop." "INFO"
                $lastConnectedState = $false
            }

            # Check if Windows physically sees an Android USB device
            $pnpPhone = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { 
                $_.FriendlyName -match "motorola|moto|android" -or $_.InstanceId -match "VID_22B8" 
            }

            if ($pnpPhone) {
                $consecutiveFailures++
                # If physical USB is present but ADB can't see it for 3 consecutive checks (9-12s)
                if ($consecutiveFailures -ge 3) {
                    Write-DaemonLog "Hardware present but ADB socket unresponsive. Attempting recovery..." "WARN"
                    [void](Invoke-AdbTimeout -Arguments @("reconnect") -TimeoutSeconds 3)
                    [void](Invoke-AdbTimeout -Arguments @("kill-server") -TimeoutSeconds 3)
                    Start-Sleep -Seconds 1
                    [void](Invoke-AdbTimeout -Arguments @("start-server") -TimeoutSeconds 4)
                    $consecutiveFailures = 0
                }
            } else {
                $consecutiveFailures = 0
            }

            Start-Sleep -Seconds 3
        }
    } catch {
        Write-DaemonLog "Loop exception: $_" "ERROR"
        Start-Sleep -Seconds 5
    }
}
