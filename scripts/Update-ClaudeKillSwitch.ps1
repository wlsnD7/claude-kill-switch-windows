#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$config = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'KillSwitch.config.psd1')
$aliases = @($config.BlockedInterfaceAliases | Sort-Object -Unique)
if ($aliases.Count -eq 0 -or $aliases -contains 'REPLACE_WITH_YOUR_INTERFACE_ALIAS') {
    throw 'Configure BlockedInterfaceAliases before running this script.'
}
foreach ($alias in $aliases) {
    if ([string]::IsNullOrWhiteSpace($alias) -or $alias -match '[*?\[\]]') {
        throw 'Interface aliases must be non-empty literal names, without wildcards.'
    }
}
$group = 'Claude Auto KillSwitch v2'
$paths = @(
    Get-CimInstance Win32_Process -Filter "Name = 'claude.exe'" |
        Where-Object {
            $_.ExecutablePath -like '*\WindowsApps\Claude_*\app\Claude.exe' -or
            $_.ExecutablePath -like "$env:APPDATA\Claude\claude-code\*\claude.exe"
        } | Select-Object -ExpandProperty ExecutablePath
    Get-AppxPackage | Where-Object { $_.Name -eq 'Claude' } | ForEach-Object {
        $candidate = Join-Path $_.InstallLocation 'app\Claude.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $candidate }
    }
    $config.ExtraProgramPaths
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
if (-not $paths) { Write-Warning 'No matching executable found; existing rules were kept.' }
$existing = @(Get-NetFirewallRule -PolicyStore PersistentStore |
    Where-Object { $_.Group -eq $group })
foreach ($programPath in $paths) {
    if ($programPath -notmatch '^[A-Za-z]:\\' -or $programPath -match '[*?]' -or
        [IO.Path]::GetExtension($programPath) -ine '.exe') {
        throw "Expected an absolute executable path: $programPath"
    }
    foreach ($alias in $aliases) {
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes(($programPath.ToLowerInvariant() + '|' + $alias.ToLowerInvariant()))
            $key = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
        } finally { $sha.Dispose() }
        $ruleName = 'ClaudeKS-v2-' + $key
        $rule = $existing | Where-Object { $_.Name -eq $ruleName }
        $parameters = @{
            PolicyStore = 'PersistentStore'
            Program = $programPath
            InterfaceAlias = $alias
            InterfaceType = 'Any'
            Direction = 'Outbound'
            Action = 'Block'
            Enabled = 'True'
            Profile = 'Any'
            Protocol = 'Any'
            LocalAddress = 'Any'
            RemoteAddress = 'Any'
        }
        if ($rule) {
            Set-NetFirewallRule -Name $ruleName @parameters | Out-Null
        } else {
            New-NetFirewallRule -Name $ruleName -Group $group `
                -DisplayName "Claude Auto KillSwitch - $alias - $key" @parameters | Out-Null
        }
    }
}
Write-Output ("Refreshed {0} executable path(s); old rules retained." -f @($paths).Count)
