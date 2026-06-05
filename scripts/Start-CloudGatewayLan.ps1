[CmdletBinding()]
param(
    [string]$DeploymentDir = (Join-Path (Get-Location) "cliproxy-gateway"),

    [string]$BinaryPath = "",

    [string]$Domain = "cliproxy.lan",

    [ValidateRange(1, 65535)]
    [int]$Port = 8317,

    [ValidateRange(1, 65535)]
    [int]$LanPort = 8080,

    [string]$ServerHost = "",

    [ValidateSet("Direct", "Http", "Socks5")]
    [string]$UpstreamProxyMode = "Direct",

    [string]$UpstreamProxyUrl = "",

    [string]$CaddyPath = "caddy",

    [switch]$NoRegenerate,

    [switch]$SkipStart,

    [switch]$SkipCaddy,

    [switch]$SkipDownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-YamlSingleQuotedContent {
    param([string]$Value)
    return $Value.Replace("''", "'")
}

function Get-ExistingApiKeys {
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return @()
    }

    $Config = Get-Content -LiteralPath $ConfigPath -Raw
    $Match = [regex]::Match($Config, '(?ms)^api-keys:\s*\r?\n(?<block>(?:\s+-\s*''.*?''\s*\r?\n?)+)')
    if (-not $Match.Success) {
        return @()
    }

    $Keys = @()
    foreach ($LineMatch in [regex]::Matches($Match.Groups["block"].Value, "(?m)^\s+-\s*'(?<key>(?:''|[^'])*)'\s*$")) {
        $Keys += Get-YamlSingleQuotedContent $LineMatch.Groups["key"].Value
    }
    return $Keys
}

function Get-LanHost {
    param([string]$RequestedHost)

    if (-not [string]::IsNullOrWhiteSpace($RequestedHost)) {
        return $RequestedHost
    }

    $Address = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.PrefixOrigin -ne "WellKnown"
        } |
        Sort-Object InterfaceMetric, InterfaceIndex |
        Select-Object -First 1 -ExpandProperty IPAddress

    if ([string]::IsNullOrWhiteSpace($Address)) {
        return "127.0.0.1"
    }

    return $Address
}

function Write-LanCaddyfile {
    param(
        [string]$Path,
        [string]$ListenHost,
        [int]$ListenPort,
        [int]$UpstreamPort
    )

    $Content = @"
http://$($ListenHost):$($ListenPort) {
    encode zstd gzip

    reverse_proxy 127.0.0.1:$($UpstreamPort) {
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
    }
}
"@

    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Get-AuthSummary {
    param([string]$AuthDir)

    $Summary = @()
    if (-not (Test-Path -LiteralPath $AuthDir)) {
        return $Summary
    }

    foreach ($File in (Get-ChildItem -LiteralPath $AuthDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        $Item = [ordered]@{
            File = $File.Name
            Type = ""
            Disabled = ""
            Websockets = ""
            HasAccessToken = $false
            HasRefreshToken = $false
            Status = ""
        }

        if ($File.Name -match "settings|test|temp|^codextoclaude-") {
            $Item.Status = "ignored-by-generator-name"
            $Summary += [pscustomobject]$Item
            continue
        }

        try {
            $Auth = Get-Content -LiteralPath $File.FullName -Raw | ConvertFrom-Json
            $Item.Type = [string]$Auth.type
            $Item.Disabled = [string]$Auth.disabled
            if ($Auth.PSObject.Properties["websockets"]) {
                $Item.Websockets = [string]$Auth.websockets
            } else {
                $Item.Websockets = "missing"
            }
            $Item.HasAccessToken = [bool]$Auth.PSObject.Properties["access_token"]
            $Item.HasRefreshToken = [bool]$Auth.PSObject.Properties["refresh_token"]

            if ($Auth.type -eq "codex" -and $Auth.disabled -ne $true) {
                $Item.Status = "enabled-codex"
            } else {
                $Item.Status = "not-enabled-codex"
            }
        } catch {
            $Item.Status = "invalid-json"
        }

        $Summary += [pscustomobject]$Item
    }

    return $Summary
}

function Resolve-CommandPath {
    param([string]$PathOrCommand)

    if (Test-Path -LiteralPath $PathOrCommand) {
        return (Resolve-Path -LiteralPath $PathOrCommand).Path
    }

    $Command = Get-Command $PathOrCommand -ErrorAction SilentlyContinue
    if ($null -eq $Command) {
        return ""
    }

    return $Command.Source
}

function Get-GitHubLatestReleaseAsset {
    param(
        [string]$Repo,
        [string]$AssetRegex,
        [string[]]$NameCandidates
    )

    $Headers = @{ "User-Agent" = "cliproxy-cloud-gateway" }
    if ($env:GH_TOKEN) {
        $Headers["Authorization"] = "Bearer $env:GH_TOKEN"
    } elseif ($env:GITHUB_TOKEN) {
        $Headers["Authorization"] = "Bearer $env:GITHUB_TOKEN"
    }

    $Tag = ""
    try {
        $Atom = Invoke-WebRequest -Uri "https://github.com/$Repo/releases.atom" -UseBasicParsing -Headers $Headers -TimeoutSec 30
        $TagMatch = [regex]::Match($Atom.Content, '<link rel="alternate" type="text/html" href="https://github\.com/[^/]+/[^/]+/releases/tag/([^"]+)"')
        if ($TagMatch.Success) {
            $Tag = $TagMatch.Groups[1].Value
        }
    } catch { }

    if ([string]::IsNullOrWhiteSpace($Tag)) {
        try {
            $Response = Invoke-WebRequest -Uri "https://github.com/$Repo/releases/latest" -UseBasicParsing -Headers $Headers -TimeoutSec 30
            if ($Response.BaseResponse -and $Response.BaseResponse.ResponseUri) {
                $FinalUri = $Response.BaseResponse.ResponseUri.AbsoluteUri
                if ($FinalUri -match '/releases/tag/([^/]+)$') {
                    $Tag = $Matches[1]
                }
            }
        } catch { }
    }

    if (-not [string]::IsNullOrWhiteSpace($Tag)) {
        try {
            $AssetsPage = Invoke-WebRequest -Uri "https://github.com/$Repo/releases/expanded_assets/$Tag" -UseBasicParsing -Headers $Headers -TimeoutSec 30
            $EscapedTag = [regex]::Escape($Tag)
            $AssetMatches = [regex]::Matches($AssetsPage.Content, "href=`"/$Repo/releases/download/$EscapedTag/([^`"]+)`"")
            foreach ($Match in $AssetMatches) {
                $Name = $Match.Groups[1].Value
                if ($Name -match $AssetRegex) {
                    return [pscustomobject]@{
                        Tag = $Tag
                        Name = $Name
                        Url = "https://github.com/$Repo/releases/download/$Tag/$Name"
                    }
                }
            }
        } catch { }

        foreach ($Candidate in $NameCandidates) {
            $Url = "https://github.com/$Repo/releases/download/$Tag/$Candidate"
            try {
                $Response = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -Headers $Headers -TimeoutSec 15
                if ($Response.StatusCode -eq 200) {
                    return [pscustomobject]@{ Tag = $Tag; Name = $Candidate; Url = $Url }
                }
            } catch { }
        }
    }

    try {
        $Release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing -Headers $Headers -TimeoutSec 30
        $Asset = $Release.assets | Where-Object { $_.name -match $AssetRegex } | Select-Object -First 1
        if ($Asset) {
            return [pscustomobject]@{ Tag = $Release.tag_name; Name = $Asset.name; Url = $Asset.browser_download_url }
        }
    } catch {
        throw "GitHub release lookup failed for $Repo`: $($_.Exception.Message). Set GH_TOKEN to avoid rate limits, or download manually."
    }

    throw "No matching asset found for $Repo latest release."
}

function Install-ReleaseAssetIfMissing {
    param(
        [string]$Repo,
        [string]$AssetRegex,
        [string[]]$NameCandidates,
        [string]$TargetPath,
        [string]$TargetFileName
    )

    if (Test-Path -LiteralPath $TargetPath) {
        Write-Host "Dependency exists, skip download: $TargetPath"
        return
    }

    $TargetDir = Split-Path -Parent $TargetPath
    if (-not (Test-Path -LiteralPath $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $Asset = Get-GitHubLatestReleaseAsset -Repo $Repo -AssetRegex $AssetRegex -NameCandidates $NameCandidates
    Write-Host "Downloading $Repo $($Asset.Tag): $($Asset.Name)"

    $TempDir = Join-Path $TargetDir ("download-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    try {
        $DownloadPath = Join-Path $TempDir $Asset.Name
        Invoke-WebRequest -Uri $Asset.Url -OutFile $DownloadPath -UseBasicParsing -TimeoutSec 300

        if ($Asset.Name -match '\.exe$') {
            Copy-Item -LiteralPath $DownloadPath -Destination $TargetPath -Force
        } else {
            $ExtractDir = Join-Path $TempDir "extract"
            Expand-Archive -Path $DownloadPath -DestinationPath $ExtractDir -Force
            $Binary = Get-ChildItem -LiteralPath $ExtractDir -Recurse -Filter $TargetFileName -File | Select-Object -First 1
            if (-not $Binary) {
                throw "Downloaded archive does not contain $TargetFileName."
            }
            Copy-Item -LiteralPath $Binary.FullName -Destination $TargetPath -Force
        }

        Write-Host "Installed dependency: $TargetPath"
    } finally {
        if (Test-Path -LiteralPath $TempDir) {
            Remove-Item -LiteralPath $TempDir -Recurse -Force
        }
    }
}

function Ensure-CLIProxyApiBinary {
    param([string]$Path)

    Install-ReleaseAssetIfMissing `
        -Repo "router-for-me/CLIProxyAPI" `
        -AssetRegex "(?i)(windows|win).*(amd64|x64|x86_64).*\.(zip|exe)$" `
        -NameCandidates @("cli-proxy-api-windows-amd64.zip", "CLIProxyAPI-windows-amd64.zip", "CLIProxyAPI_windows_amd64.zip", "cli-proxy-api-windows-amd64.exe", "CLIProxyAPI-windows-amd64.exe", "cli-proxy-api.exe") `
        -TargetPath $Path `
        -TargetFileName "cli-proxy-api.exe"
}

function Ensure-CaddyBinary {
    param(
        [string]$PathOrCommand,
        [string]$DeploymentDir
    )

    $Resolved = Resolve-CommandPath -PathOrCommand $PathOrCommand
    if (-not [string]::IsNullOrWhiteSpace($Resolved)) {
        Write-Host "Dependency exists, skip download: $Resolved"
        return $Resolved
    }

    $TargetPath = $PathOrCommand
    if ($PathOrCommand -eq "caddy") {
        $TargetPath = Join-Path $DeploymentDir "caddy\caddy.exe"
    }
    $TargetPath = [System.IO.Path]::GetFullPath($TargetPath)

    Install-ReleaseAssetIfMissing `
        -Repo "caddyserver/caddy" `
        -AssetRegex "(?i)windows.*amd64.*\.zip$" `
        -NameCandidates @("caddy_windows_amd64.zip", "caddy_2.10.2_windows_amd64.zip") `
        -TargetPath $TargetPath `
        -TargetFileName "caddy.exe"

    return $TargetPath
}

$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path -Parent $ScriptDir
$GeneratorPath = Join-Path $ScriptDir "New-CloudGateway.ps1"

$DeploymentDir = [System.IO.Path]::GetFullPath($DeploymentDir)
$ConfigPath = Join-Path $DeploymentDir "config.yaml"
$AuthDir = Join-Path $DeploymentDir "auth"
$LanCaddyPath = Join-Path $DeploymentDir "Caddyfile.lan"

if ([string]::IsNullOrWhiteSpace($BinaryPath)) {
    $BinaryPath = Join-Path $DeploymentDir "cli-proxy-api\cli-proxy-api.exe"
}
$BinaryPath = [System.IO.Path]::GetFullPath($BinaryPath)

if (-not (Test-Path -LiteralPath $GeneratorPath)) {
    throw "Generator not found: $GeneratorPath"
}

$ExistingApiKeys = @(Get-ExistingApiKeys -ConfigPath $ConfigPath)
if (-not $NoRegenerate) {
    $GeneratorParams = @{
        Domain = $Domain
        OutputDir = $DeploymentDir
        Port = $Port
        UpstreamProxyMode = $UpstreamProxyMode
    }

    if (-not [string]::IsNullOrWhiteSpace($UpstreamProxyUrl)) {
        $GeneratorParams.UpstreamProxyUrl = $UpstreamProxyUrl
    }

    if ($ExistingApiKeys.Count -gt 0) {
        $GeneratorParams.ApiKey = $ExistingApiKeys
        Write-Output "Reusing existing API key(s): $($ExistingApiKeys.Count)"
    } else {
        Write-Output "No existing API key found; generator will create a new key."
    }

    & $GeneratorPath @GeneratorParams
}

$LanHost = Get-LanHost -RequestedHost $ServerHost
Write-LanCaddyfile -Path $LanCaddyPath -ListenHost $LanHost -ListenPort $LanPort -UpstreamPort $Port

$AuthSummary = @(Get-AuthSummary -AuthDir $AuthDir)
$EnabledCodexCount = @($AuthSummary | Where-Object { $_.Status -eq "enabled-codex" }).Count

Write-Output ""
Write-Output "Deployment directory: $DeploymentDir"
Write-Output "CLIProxyAPI config: $ConfigPath"
Write-Output "Auth directory: $AuthDir"
Write-Output "LAN Caddyfile: $LanCaddyPath"
Write-Output "LAN base URL: http://$($LanHost):$($LanPort)"
Write-Output "Enabled Codex auth JSON file(s): $EnabledCodexCount"

if ($AuthSummary.Count -gt 0) {
    Write-Output ""
    $AuthSummary | Format-Table File, Type, Disabled, Websockets, HasAccessToken, HasRefreshToken, Status -AutoSize | Out-String | Write-Output
} else {
    Write-Warning "No root-level *.json files found in auth directory."
}

if ($EnabledCodexCount -eq 0) {
    Write-Warning "CLIProxyAPI will likely still report 0 Codex keys. Put enabled type=codex OAuth JSON files directly under the auth directory."
    Write-Warning "Do not use the raw ~/.codex/auth.json file directly as this deployment auth JSON."
}

if ($SkipStart) {
    Write-Output "SkipStart is set; services were not started."
    exit 0
}

if (-not (Test-Path -LiteralPath $BinaryPath)) {
    if ($SkipDownload) {
        throw "CLIProxyAPI binary not found: $BinaryPath"
    }
    Ensure-CLIProxyApiBinary -Path $BinaryPath
}

$CliArgs = @("--config", $ConfigPath)
Start-Process -FilePath $BinaryPath -ArgumentList $CliArgs -WorkingDirectory $DeploymentDir
Write-Output "Started CLIProxyAPI in a new window."

if (-not $SkipCaddy) {
    $ResolvedCaddyPath = Resolve-CommandPath -PathOrCommand $CaddyPath
    if ([string]::IsNullOrWhiteSpace($ResolvedCaddyPath) -and -not $SkipDownload) {
        $ResolvedCaddyPath = Ensure-CaddyBinary -PathOrCommand $CaddyPath -DeploymentDir $DeploymentDir
    }

    if ([string]::IsNullOrWhiteSpace($ResolvedCaddyPath)) {
        Write-Warning "Caddy not found: $CaddyPath"
        Write-Warning "Install Caddy or pass -CaddyPath, then run: caddy run --config `"$LanCaddyPath`""
    } else {
        & $ResolvedCaddyPath validate --config $LanCaddyPath
        if ($LASTEXITCODE -ne 0) {
            throw "Caddyfile validation failed: $LanCaddyPath"
        }

        Start-Process -FilePath $ResolvedCaddyPath -ArgumentList @("run", "--config", $LanCaddyPath) -WorkingDirectory $DeploymentDir
        Write-Output "Started Caddy in a new window."
    }
}

Write-Output ""
Write-Output "On your Mac, use:"
Write-Output "  export ANTHROPIC_BASE_URL=`"http://$($LanHost):$($LanPort)`""
Write-Output "  export ANTHROPIC_AUTH_TOKEN=`"<copy from $DeploymentDir\client.env>`""
