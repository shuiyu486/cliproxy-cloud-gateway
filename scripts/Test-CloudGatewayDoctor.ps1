[CmdletBinding()]
param(
    [string]$DeploymentDir = (Join-Path (Get-Location) "generated"),
    [string]$ConfigPath = "",
    [string]$CaddyPath = "",
    [string]$AuthDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Passed = 0
$script:Failed = 0

function Assert-Check {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if ($Condition) {
        $script:Passed += 1
        Write-Output "[PASS] $Message"
    } else {
        $script:Failed += 1
        Write-Output "[FAIL] $Message"
    }
}

function Read-Text {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    return Get-Content -LiteralPath $Path -Raw
}

function Get-ConfigProxyUrl {
    param([string]$Config)

    $Match = [regex]::Match($Config, '(?m)^proxy-url:\s*"([^"]+)"\s*$')
    if ($Match.Success) {
        return $Match.Groups[1].Value
    }
    return ""
}

$DeploymentDir = [System.IO.Path]::GetFullPath($DeploymentDir)
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $DeploymentDir "config.yaml"
}
if ([string]::IsNullOrWhiteSpace($CaddyPath)) {
    $CaddyPath = Join-Path $DeploymentDir "Caddyfile"
}
if ([string]::IsNullOrWhiteSpace($AuthDir)) {
    $AuthDir = Join-Path $DeploymentDir "auth"
}

$ClientEnvPath = Join-Path $DeploymentDir "client.env"

Assert-Check (Test-Path -LiteralPath $ConfigPath) "config.yaml exists"
Assert-Check (Test-Path -LiteralPath $CaddyPath) "Caddyfile exists"
Assert-Check (Test-Path -LiteralPath $ClientEnvPath) "client.env exists"

$Config = Read-Text $ConfigPath
$Caddy = Read-Text $CaddyPath
$ProxyUrl = Get-ConfigProxyUrl $Config

Assert-Check ($Config -match '(?m)^host:\s*"127\.0\.0\.1"\s*$') "CLIProxyAPI binds to localhost"
Assert-Check ($Config -match '(?ms)^tls:\s*\r?\n\s+enable:\s*false') "CLIProxyAPI direct TLS is disabled"
Assert-Check ($Config -match '(?m)^\s*allow-remote:\s*false\s*$') "remote management is disabled"
Assert-Check ($Config -match '(?m)^\s*disable-control-panel:\s*true\s*$') "control panel is disabled"
Assert-Check ($Config -match '(?m)^passthrough-headers:\s*true\s*$') "upstream response headers are forwarded"
Assert-Check ($Config -match '(?m)^request-retry:\s*1\s*$') "request retry is bounded"
Assert-Check ($Config -match '(?m)^max-retry-credentials:\s*1\s*$') "credential retry is bounded"
Assert-Check ($Config -match '(?m)^max-retry-interval:\s*5\s*$') "retry interval is bounded"
Assert-Check ($Config -match '(?m)^\s*antigravity-credits:\s*false\s*$') "Antigravity credit fallback is disabled"
if ($Config -match '"reasoning"' -or $Config -match '"reasoning\.effort"' -or $Config -match '"thinking"') {
    Write-Output "[INFO] Codex payload filter is configured; reasoning/thinking fields are disabled."
} else {
    Write-Output "[INFO] Codex reasoning/thinking passthrough is enabled."
}
Assert-Check ($Config -match 'codex-header-defaults:\s*\r?\n\s+user-agent:') "Codex header defaults are present"
Assert-Check ($Caddy -match 'reverse_proxy\s+127\.0\.0\.1:') "Caddy proxies to localhost"

if (Test-Path -LiteralPath $AuthDir) {
    foreach ($File in (Get-ChildItem -LiteralPath $AuthDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        try {
            $Auth = Get-Content -LiteralPath $File.FullName -Raw | ConvertFrom-Json
            if ($Auth.type -ne "codex" -or $Auth.disabled -eq $true) {
                continue
            }
            Assert-Check ($null -ne $Auth.PSObject.Properties["websockets"]) "auth $($File.Name) has websockets metadata"
            if ([string]::IsNullOrWhiteSpace($ProxyUrl)) {
                Assert-Check (-not $Auth.PSObject.Properties["proxy_url"]) "auth $($File.Name) omits proxy_url in Direct mode"
            } else {
                Assert-Check ($Auth.proxy_url -eq $ProxyUrl) "auth $($File.Name) proxy_url matches config"
            }
        } catch {
            Assert-Check $false "auth $($File.Name) parses as JSON"
        }
    }
}

Write-Output ""
Write-Output "Passed: $script:Passed  Failed: $script:Failed"

if ($script:Failed -gt 0) {
    exit 1
}
