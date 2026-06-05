[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Domain,

    [string]$OutputDir = (Join-Path (Get-Location) "generated"),

    [ValidateRange(1, 65535)]
    [int]$Port = 8317,

    [string[]]$ApiKey = @(),

    [string]$AuthDir = "",

    [string]$CodexUserAgent = "codex_cli_rs/0.114.0 (Mac OS 14.2.0; x86_64) vscode/1.111.0",

    [ValidateSet("Direct", "Http", "Socks5")]
    [string]$UpstreamProxyMode = "Direct",

    [string]$UpstreamProxyUrl = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Domain {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Domain is required."
    }

    if ($Value.Contains("://") -or $Value.Contains("/") -or $Value.Contains("\")) {
        throw "Domain must be a host name only, for example api.example.com."
    }
}

function New-RandomApiKey {
    $Bytes = New-Object byte[] 32
    $Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $Rng.GetBytes($Bytes)
    } finally {
        $Rng.Dispose()
    }

    $Token = [Convert]::ToBase64String($Bytes).TrimEnd("=") -replace "\+", "-" -replace "/", "_"
    return "sk-cliproxy-$Token"
}

function Get-YamlSingleQuotedContent {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

function Get-YamlSingleQuotedValue {
    param([string]$Value)
    return "'" + (Get-YamlSingleQuotedContent $Value) + "'"
}

function Read-Template {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Template not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw
}

function Render-Template {
    param(
        [string]$Template,
        [hashtable]$Values
    )

    $Rendered = $Template
    foreach ($Key in $Values.Keys) {
        $Rendered = $Rendered.Replace($Key, [string]$Values[$Key])
    }
    return $Rendered
}

function Set-JsonProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Remove-JsonProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($Object.PSObject.Properties[$Name]) {
        $Object.PSObject.Properties.Remove($Name)
    }
}

function Get-NormalizedUpstreamProxyUrl {
    param(
        [string]$Mode,
        [string]$Url
    )

    if ($Mode -eq "Direct") {
        return ""
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        throw "UpstreamProxyUrl is required when UpstreamProxyMode is $Mode."
    }

    $Trimmed = $Url.Trim()
    if ($Mode -eq "Http") {
        if ($Trimmed -match "^(?i:https?://)") {
            return $Trimmed
        }
        if ($Trimmed -match "^(?i:socks5://)") {
            throw "Http mode cannot use a socks5:// upstream proxy URL."
        }
        return "http://$Trimmed"
    }

    if ($Trimmed -match "^(?i:socks5://)") {
        return $Trimmed
    }
    if ($Trimmed -match "^(?i:https?://)") {
        throw "Socks5 mode cannot use an HTTP upstream proxy URL."
    }
    return "socks5://$Trimmed"
}

function Sync-CodexAuthMetadata {
    param(
        [string]$Directory,
        [string]$ProxyUrl
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        return 0
    }

    $Updated = 0
    foreach ($File in (Get-ChildItem -LiteralPath $Directory -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        if ($File.Name -match "settings|test|temp|^codextoclaude-") {
            continue
        }

        try {
            $Auth = Get-Content -LiteralPath $File.FullName -Raw | ConvertFrom-Json
            if ($Auth.type -ne "codex" -or $Auth.disabled -eq $true) {
                continue
            }

            if (-not $Auth.PSObject.Properties["websockets"]) {
                Set-JsonProperty $Auth "websockets" $true
            }

            if ([string]::IsNullOrWhiteSpace($ProxyUrl)) {
                Remove-JsonProperty $Auth "proxy_url"
            } else {
                Set-JsonProperty $Auth "proxy_url" $ProxyUrl
            }

            $Auth | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $File.FullName -Encoding UTF8
            $Updated += 1
        } catch {
            Write-Warning "Skipped auth metadata sync for $($File.Name): $($_.Exception.Message)"
        }
    }

    return $Updated
}

Assert-Domain $Domain

$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path -Parent $ScriptDir
$TemplateDir = Join-Path $ProjectRoot "templates"

$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
if ([string]::IsNullOrWhiteSpace($AuthDir)) {
    $AuthDir = Join-Path $OutputDir "auth"
} else {
    $AuthDir = [System.IO.Path]::GetFullPath($AuthDir)
}

$LogsDir = Join-Path $OutputDir "logs"

if ($ApiKey.Count -eq 0) {
    $ApiKey = @(New-RandomApiKey)
}

$NormalizedProxyUrl = Get-NormalizedUpstreamProxyUrl -Mode $UpstreamProxyMode -Url $UpstreamProxyUrl
$ProxyUrlBlock = ""
if (-not [string]::IsNullOrWhiteSpace($NormalizedProxyUrl)) {
    $ProxyUrlBlock = "proxy-url: `"$NormalizedProxyUrl`""
}

$ApiKeysYaml = ($ApiKey | ForEach-Object {
    "  - $(Get-YamlSingleQuotedValue $_)"
}) -join "`n"

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
New-Item -ItemType Directory -Path $AuthDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null

$ConfigTemplatePath = Join-Path $TemplateDir "cliproxy.config.template.yaml"
$CaddyTemplatePath = Join-Path $TemplateDir "Caddyfile.template"

$Config = Render-Template `
    -Template (Read-Template $ConfigTemplatePath) `
    -Values @{
        "{{PORT}}" = $Port.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        "{{PROXY_URL_BLOCK}}" = $ProxyUrlBlock
        "{{AUTH_DIR}}" = Get-YamlSingleQuotedContent ($AuthDir.Replace("\", "/"))
        "{{API_KEYS_YAML}}" = $ApiKeysYaml
        "{{CODEX_USER_AGENT}}" = Get-YamlSingleQuotedContent $CodexUserAgent
    }

$Caddyfile = Render-Template `
    -Template (Read-Template $CaddyTemplatePath) `
    -Values @{
        "{{DOMAIN}}" = $Domain
        "{{PORT}}" = $Port.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }

$ConfigPath = Join-Path $OutputDir "config.yaml"
$CaddyPath = Join-Path $OutputDir "Caddyfile"
$ClientEnvPath = Join-Path $OutputDir "client.env"

Set-Content -LiteralPath $ConfigPath -Value $Config -Encoding UTF8
Set-Content -LiteralPath $CaddyPath -Value $Caddyfile -Encoding UTF8
$ClientEnv = @(
    "ANTHROPIC_BASE_URL=https://$Domain",
    "ANTHROPIC_AUTH_TOKEN=$($ApiKey[0])"
) -join "`n"
Set-Content -LiteralPath $ClientEnvPath -Value $ClientEnv -Encoding UTF8

$SyncedAuthCount = Sync-CodexAuthMetadata -Directory $AuthDir -ProxyUrl $NormalizedProxyUrl

Write-Output "Generated config.yaml: $ConfigPath"
Write-Output "Generated Caddyfile: $CaddyPath"
Write-Output "Generated client.env: $ClientEnvPath"
Write-Output "Auth directory: $AuthDir"
Write-Output "Logs directory: $LogsDir"
Write-Output "Upstream proxy mode: $UpstreamProxyMode"
if (-not [string]::IsNullOrWhiteSpace($NormalizedProxyUrl)) {
    Write-Output "Upstream proxy URL: $NormalizedProxyUrl"
}
Write-Output "Synced Codex auth file(s): $SyncedAuthCount"
Write-Output "API keys were written to config.yaml and client.env."
