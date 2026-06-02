[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BinaryPath,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [string]$WorkingDirectory = "",

    [string]$TaskName = "CLIProxyAPI Cloud Gateway",

    [switch]$AtStartup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $BinaryPath)) {
    throw "CLIProxyAPI binary not found: $BinaryPath"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
    $WorkingDirectory = Split-Path -Parent $ConfigPath
}

if (-not (Test-Path -LiteralPath $WorkingDirectory)) {
    throw "Working directory not found: $WorkingDirectory"
}

$Action = New-ScheduledTaskAction `
    -Execute $BinaryPath `
    -Argument "--config `"$ConfigPath`"" `
    -WorkingDirectory $WorkingDirectory

if ($AtStartup) {
    $Trigger = New-ScheduledTaskTrigger -AtStartup
} else {
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
}

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Description "Run CLIProxyAPI with private cloud gateway config." `
    -Force | Out-Null

Write-Host "Registered scheduled task: $TaskName"
