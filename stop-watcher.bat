@echo off
powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*phone-watcher.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo Android PC Keep-Awake watcher stopped.
pause
