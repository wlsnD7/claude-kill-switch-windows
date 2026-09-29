#Requires -Version 5.1
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$source = 'ClaudeKillSwitch.ProcessStart'
$updateScript = Join-Path $PSScriptRoot 'Update-ClaudeKillSwitch.ps1'
$logPath = Join-Path $PSScriptRoot 'watcher.log'
$mutex = New-Object Threading.Mutex($false, 'Local\ClaudeKillSwitchWatcherV2')
$ownsMutex = $false
$subscribed = $false
$exitCode = 0
try {
    try { $ownsMutex = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { exit 0 }
    # Subscribe before scanning so startup events during the scan remain queued.
    Register-CimIndicationEvent -Namespace root/cimv2 `
        -Query "SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName = 'claude.exe' OR ProcessName = 'Claude.exe'" `
        -SourceIdentifier $source | Out-Null
    $subscribed = $true
    & $updateScript | Out-Null
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) watcher started; initial refresh completed"
    while ($true) {
        $eventRecord = Wait-Event -SourceIdentifier $source
        try {
            # Scan all matching processes; do not discard another version's event.
            & $updateScript | Out-Null
            Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) process event; refresh completed"
        } finally {
            Remove-Event -EventIdentifier $eventRecord.EventIdentifier -ErrorAction SilentlyContinue
        }
    }
} catch {
    $exitCode = 1
    $failure = "$(Get-Date -Format o) ERROR: $($_.Exception.Message)"
    try { Add-Content -LiteralPath $logPath -Value $failure } catch { }
    Write-Error $failure -ErrorAction Continue
} finally {
    if ($subscribed) {
        Unregister-Event -SourceIdentifier $source -ErrorAction SilentlyContinue
        Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
    }
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
exit $exitCode
