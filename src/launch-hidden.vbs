' Launches the phone-watcher daemon without displaying a console window
Set WshShell = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
watcherScript = scriptDir & "\phone-watcher.ps1"

WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & watcherScript & """", 0, False
