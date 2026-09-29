Option Explicit
Dim shell, fso, scriptPath, powershellPath, command, result
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptPath = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "Watch-ClaudeKillSwitch.ps1")
powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
command = """" & powershellPath & """ -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & scriptPath & """"
result = shell.Run(command, 0, True)
WScript.Quit result
