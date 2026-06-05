Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if ($Condition) {
        $script:Passed += 1
        Write-Host "[PASS] $Message"
    } else {
        $script:Failed += 1
        Write-Host "[FAIL] $Message"
    }
}

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Message
    )

    Assert-True -Condition ($Text.Contains($Needle)) -Message $Message
}

function Assert-NotContains {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Message
    )

    Assert-True -Condition (-not $Text.Contains($Needle)) -Message $Message
}

function Read-TextIfPresent {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw
    }

    return $null
}

$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$DefaultCodexUserAgent = "codex_cli_rs/0.114.0 (Mac OS 14.2.0; x86_64) vscode/1.111.0"

$RequiredFiles = @(
    "README.md",
    "README.en-US.md",
    "CLAUDE.md",
    "docs/deployment.md",
    "templates/cliproxy.config.template.yaml",
    "templates/Caddyfile.template",
    "scripts/New-CloudGateway.ps1",
    "scripts/Start-CloudGatewayLan.ps1",
    "scripts/start-cloud-gateway-lan.sh",
    "scripts/new-cloud-gateway.sh",
    "scripts/Test-CloudGatewayDoctor.ps1",
    "scripts/test-cloud-gateway-doctor.sh",
    "windows/Register-CLIProxyAPI-Task.ps1",
    "linux/cliproxy.service.template",
    ".gitignore"
)

foreach ($RelativePath in $RequiredFiles) {
    $FullPath = Join-Path $Root $RelativePath
    Assert-True -Condition (Test-Path -LiteralPath $FullPath) -Message "required file exists: $RelativePath"
}

$ReadmePath = Join-Path $Root "README.md"
$EnglishReadmePath = Join-Path $Root "README.en-US.md"
$MemoryPath = Join-Path $Root "CLAUDE.md"

$Readme = Read-TextIfPresent $ReadmePath
if ($null -ne $Readme) {
    Assert-Contains $Readme '中文 | [English](README.en-US.md)' "default README links to English README"
    Assert-Contains $Readme '# CLIProxyAPI Cloud Gateway' "default README keeps project title"
    Assert-Contains $Readme '## 项目如何生效' "default README explains how the project works"
    Assert-Contains $Readme 'flowchart LR' "default README includes Mermaid flowchart"
    Assert-Contains $Readme 'subgraph CallerZone["调用方设备"]' "default README separates caller device zone"
    Assert-Contains $Readme 'subgraph PublicZone["公网入口"]' "default README separates public entry zone"
    Assert-Contains $Readme 'subgraph ServerZone["云服务器本机"]' "default README separates cloud server localhost zone"
    Assert-Contains $Readme 'subgraph ProxyZone["可选上游代理"]' "default README separates optional upstream proxy zone"
    Assert-Contains $Readme 'subgraph UpstreamZone["OpenAI 上游"]' "default README separates upstream zone"
    Assert-Contains $Readme 'Caller["Claude Code / Codex 兼容客户端"]' "default README flowchart starts with caller"
    Assert-Contains $Readme 'Caddy["Caddy\n公网 HTTPS :443"]' "default README flowchart includes Caddy HTTPS"
    Assert-Contains $Readme 'CLIProxyAPI["CLIProxyAPI\n127.0.0.1:8317"]' "default README flowchart includes localhost CLIProxyAPI"
    Assert-Contains $Readme 'Auth["auth/*.json\nCodex OAuth 凭据"]' "default README flowchart includes auth JSON input"
    Assert-Contains $Readme 'Upstream["Codex / ChatGPT API"]' "default README flowchart includes upstream"
    Assert-Contains $Readme 'client -> Caddy HTTPS -> CLIProxyAPI -> Codex / ChatGPT 上游' "default README includes plain-text flow"
    Assert-Contains $Readme '生成器输出如何落地' "default README includes generated-files flow section"
    Assert-Contains $Readme 'Generator["New-CloudGateway 生成器"]' "default README generated-files diagram starts with generator"
    Assert-Contains $Readme 'ClientEnv["client.env\n调用方参考，不是服务端运行依赖"]' "default README generated-files diagram clarifies client.env role"
    Assert-Contains $Readme 'CLIProxyAPI -. "写入" .-> Logs' "default README uses GitHub-compatible forward log edge"
    Assert-NotContains $Readme '<-.' "default README avoids reverse dotted Mermaid edges"
    Assert-Contains $Readme '## 快速开始' "default README has quick start"
    Assert-Contains $Readme '## 上游代理' "default README explains upstream proxy"
    Assert-Contains $Readme '## 安全默认值' "default README documents security defaults"
    Assert-Contains $Readme '## 获取 Codex OAuth JSON' "default README explains how to get Codex auth JSON"
    Assert-Contains $Readme './cli-proxy-api -config ./config.yaml -codex-device-login' "default README documents Linux device login"
    Assert-Contains $Readme 'Linux 云服务器不需要图形浏览器' "default README explains headless Linux login"
    Assert-Contains $Readme '不要直接把 `~/.codex/auth.json` 当作这里的 OAuth 文件' "default README warns against copying Codex CLI auth"
    Assert-Contains $Readme '不要让本机和云服务器长期并发使用同一份 OAuth JSON' "default README warns against concurrent auth reuse"
    Assert-Contains $Readme '## Doctor 检查' "default README documents doctor checks"
    Assert-Contains $Readme 'https://github.com/shuiyu486/cliproxy-cloud-gateway' "default README references GitHub repository"
}

$EnglishReadme = Read-TextIfPresent $EnglishReadmePath
if ($null -ne $EnglishReadme) {
    Assert-Contains $EnglishReadme '[中文](README.md) | English' "English README links back to Chinese README"
    Assert-Contains $EnglishReadme '## How It Works' "English README explains how the project works"
    Assert-Contains $EnglishReadme 'flowchart LR' "English README includes Mermaid flowchart"
    Assert-Contains $EnglishReadme 'subgraph CallerZone["Caller device"]' "English README separates caller device zone"
    Assert-Contains $EnglishReadme 'subgraph PublicZone["Public entry"]' "English README separates public entry zone"
    Assert-Contains $EnglishReadme 'subgraph ServerZone["Cloud server localhost"]' "English README separates cloud server localhost zone"
    Assert-Contains $EnglishReadme 'subgraph ProxyZone["Optional upstream proxy"]' "English README separates optional upstream proxy zone"
    Assert-Contains $EnglishReadme 'subgraph UpstreamZone["OpenAI upstream"]' "English README separates upstream zone"
    Assert-Contains $EnglishReadme 'Caller["Claude Code / Codex-compatible client"]' "English README flowchart starts with caller"
    Assert-Contains $EnglishReadme 'Caddy["Caddy\nPublic HTTPS :443"]' "English README flowchart includes Caddy HTTPS"
    Assert-Contains $EnglishReadme 'CLIProxyAPI["CLIProxyAPI\n127.0.0.1:8317"]' "English README flowchart includes localhost CLIProxyAPI"
    Assert-Contains $EnglishReadme 'Auth["auth/*.json\nCodex OAuth credentials"]' "English README flowchart includes auth JSON input"
    Assert-Contains $EnglishReadme 'Upstream["Codex / ChatGPT API"]' "English README flowchart includes upstream"
    Assert-Contains $EnglishReadme 'client -> Caddy HTTPS -> CLIProxyAPI -> Codex / ChatGPT upstream' "English README includes plain-text flow"
    Assert-Contains $EnglishReadme 'How Generated Files Are Used' "English README includes generated-files flow section"
    Assert-Contains $EnglishReadme 'Generator["New-CloudGateway generator"]' "English README generated-files diagram starts with generator"
    Assert-Contains $EnglishReadme 'ClientEnv["client.env\nCaller reference, not a service dependency"]' "English README generated-files diagram clarifies client.env role"
    Assert-Contains $EnglishReadme 'CLIProxyAPI -. "writes" .-> Logs' "English README uses GitHub-compatible forward log edge"
    Assert-NotContains $EnglishReadme '<-.' "English README avoids reverse dotted Mermaid edges"
    Assert-Contains $EnglishReadme '## Quick Start' "English README has quick start"
    Assert-Contains $EnglishReadme '## Upstream Proxy' "English README explains upstream proxy"
    Assert-Contains $EnglishReadme '## Security Defaults' "English README documents security defaults"
    Assert-Contains $EnglishReadme '## Get Codex OAuth JSON' "English README explains how to get Codex auth JSON"
    Assert-Contains $EnglishReadme './cli-proxy-api -config ./config.yaml -codex-device-login' "English README documents Linux device login"
    Assert-Contains $EnglishReadme 'The server does not need a graphical browser' "English README explains headless Linux login"
    Assert-Contains $EnglishReadme 'Do not use `~/.codex/auth.json` directly as this OAuth file' "English README warns against copying Codex CLI auth"
    Assert-Contains $EnglishReadme 'Do not keep the same OAuth JSON in long-term concurrent use on both your local machine and the server' "English README warns against concurrent auth reuse"
}

$Memory = Read-TextIfPresent $MemoryPath
if ($null -ne $Memory) {
    Assert-Contains $Memory '# cliproxy-cloud-gateway 常驻上下文' "CLAUDE.md has project memory title"
    Assert-Contains $Memory '按需路由' "CLAUDE.md uses on-demand routing"
    Assert-Contains $Memory '渐进式披露' "CLAUDE.md mentions progressive disclosure"
    Assert-Contains $Memory '## 先读什么' "CLAUDE.md routes maintainers to relevant files"
    Assert-Contains $Memory '## 架构边界' "CLAUDE.md documents architecture boundaries"
    Assert-Contains $Memory '## 不可破坏契约' "CLAUDE.md documents non-breaking contracts"
    Assert-Contains $Memory '## 配置契约' "CLAUDE.md documents config contracts"
    Assert-Contains $Memory '## 验证标准' "CLAUDE.md documents verification standards"
    Assert-Contains $Memory '## GitHub 发布检查' "CLAUDE.md documents GitHub release checks"
    Assert-Contains $Memory '禁止提交或输出 Codex OAuth JSON' "CLAUDE.md forbids credential leakage"
}

$ConfigTemplatePath = Join-Path $Root "templates/cliproxy.config.template.yaml"
$ConfigTemplate = Read-TextIfPresent $ConfigTemplatePath
if ($null -ne $ConfigTemplate) {
    Assert-Contains $ConfigTemplate 'host: "127.0.0.1"' "CLIProxyAPI template binds to localhost"
    Assert-Contains $ConfigTemplate 'tls:' "CLIProxyAPI template has TLS section"
    Assert-Contains $ConfigTemplate 'enable: false' "CLIProxyAPI template disables direct TLS by default"
    Assert-Contains $ConfigTemplate 'allow-remote: false' "remote management is not exposed"
    Assert-Contains $ConfigTemplate 'secret-key: ""' "management API is disabled without a secret key"
    Assert-Contains $ConfigTemplate 'disable-control-panel: true' "control panel route is disabled"
    Assert-Contains $ConfigTemplate 'codex-header-defaults:' "Codex header defaults section exists"
    Assert-Contains $ConfigTemplate $DefaultCodexUserAgent "Codex default user-agent is pinned"
    Assert-Contains $ConfigTemplate 'session-affinity: true' "routing keeps Codex sessions sticky"
    Assert-Contains $ConfigTemplate '{{PROXY_URL_BLOCK}}' "CLIProxyAPI template has optional upstream proxy block"
    Assert-Contains $ConfigTemplate 'passthrough-headers: true' "CLIProxyAPI template forwards upstream response headers"
    Assert-Contains $ConfigTemplate 'quota-exceeded:' "CLIProxyAPI template has quota fallback policy"
    Assert-Contains $ConfigTemplate 'switch-project: true' "CLIProxyAPI template can switch project on quota exhaustion"
    Assert-Contains $ConfigTemplate 'switch-preview-model: true' "CLIProxyAPI template can switch preview model on quota exhaustion"
    Assert-Contains $ConfigTemplate 'antigravity-credits: false' "CLIProxyAPI template disables Antigravity credit fallback"
    Assert-Contains $ConfigTemplate 'request-retry: 1' "CLIProxyAPI template keeps request retry bounded"
    Assert-Contains $ConfigTemplate 'max-retry-credentials: 1' "CLIProxyAPI template keeps credential retry bounded"
    Assert-Contains $ConfigTemplate 'max-retry-interval: 5' "CLIProxyAPI template keeps retry interval bounded"
    Assert-Contains $ConfigTemplate 'payload:' "CLIProxyAPI template has payload filter"
    Assert-Contains $ConfigTemplate '"reasoning"' "CLIProxyAPI template filters reasoning"
    Assert-Contains $ConfigTemplate '"reasoning.effort"' "CLIProxyAPI template filters reasoning effort"
    Assert-Contains $ConfigTemplate '"thinking"' "CLIProxyAPI template filters thinking"
}

$CaddyTemplatePath = Join-Path $Root "templates/Caddyfile.template"
$CaddyTemplate = Read-TextIfPresent $CaddyTemplatePath
if ($null -ne $CaddyTemplate) {
    Assert-Contains $CaddyTemplate '{{DOMAIN}}' "Caddy template has domain placeholder"
    Assert-Contains $CaddyTemplate 'reverse_proxy 127.0.0.1:{{PORT}}' "Caddy proxies to private CLIProxyAPI"
}

$PowerShellGenerator = Join-Path $Root "scripts/New-CloudGateway.ps1"
if (Test-Path -LiteralPath $PowerShellGenerator) {
    $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxy-cloud-gateway-test-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        $Output = & $PowerShellGenerator `
            -Domain "api.example.test" `
            -OutputDir $TempDir `
            -Port 18444 `
            -ApiKey @("sk-test-one", "sk-test-two") 2>&1 | Out-String

        Assert-True -Condition $true -Message "PowerShell generator exits cleanly"
        Assert-Contains $Output "config.yaml" "PowerShell generator reports config path"

        $GeneratedConfigPath = Join-Path $TempDir "config.yaml"
        $GeneratedCaddyPath = Join-Path $TempDir "Caddyfile"
        $GeneratedClientEnvPath = Join-Path $TempDir "client.env"
        Assert-True -Condition (Test-Path -LiteralPath $GeneratedConfigPath) -Message "PowerShell generator writes config.yaml"
        Assert-True -Condition (Test-Path -LiteralPath $GeneratedCaddyPath) -Message "PowerShell generator writes Caddyfile"
        Assert-True -Condition (Test-Path -LiteralPath $GeneratedClientEnvPath) -Message "PowerShell generator writes client.env"

        $GeneratedConfig = Read-TextIfPresent $GeneratedConfigPath
        $GeneratedCaddy = Read-TextIfPresent $GeneratedCaddyPath
        $GeneratedClientEnv = Read-TextIfPresent $GeneratedClientEnvPath

        Assert-Contains $GeneratedConfig 'host: "127.0.0.1"' "generated config binds to localhost"
        Assert-Contains $GeneratedConfig 'port: 18444' "generated config uses requested port"
        Assert-Contains $GeneratedConfig "sk-test-one" "generated config includes first API key"
        Assert-Contains $GeneratedConfig "sk-test-two" "generated config includes second API key"
        Assert-NotContains $GeneratedConfig 'proxy-url:' "generated Direct config omits upstream proxy-url"
        Assert-Contains $GeneratedConfig 'passthrough-headers: true' "generated config forwards upstream response headers"
        Assert-Contains $GeneratedConfig 'request-retry: 1' "generated config keeps request retry bounded"
        Assert-Contains $GeneratedConfig 'max-retry-credentials: 1' "generated config keeps credential retry bounded"
        Assert-Contains $GeneratedConfig 'max-retry-interval: 5' "generated config keeps retry interval bounded"
        Assert-Contains $GeneratedConfig 'antigravity-credits: false' "generated config disables Antigravity fallback"
        Assert-Contains $GeneratedConfig '"reasoning.effort"' "generated config filters reasoning effort"
        Assert-Contains $GeneratedConfig $DefaultCodexUserAgent "generated config includes Codex user-agent"
        Assert-Contains $GeneratedCaddy "api.example.test" "generated Caddyfile includes domain"
        Assert-Contains $GeneratedCaddy "reverse_proxy 127.0.0.1:18444" "generated Caddyfile proxies to requested port"
        Assert-Contains $GeneratedClientEnv "ANTHROPIC_BASE_URL=https://api.example.test" "client.env includes base URL"
        Assert-Contains $GeneratedClientEnv "ANTHROPIC_AUTH_TOKEN=sk-test-one" "client.env includes first client key"
        Assert-NotContains $Output "sk-test-one" "PowerShell generator does not print first API key"
        Assert-NotContains $Output "sk-test-two" "PowerShell generator does not print second API key"
    } catch {
        Assert-True -Condition $false -Message "PowerShell generator exits cleanly"
        Write-Host $_
    } finally {
        if (Test-Path -LiteralPath $TempDir) {
            Remove-Item -LiteralPath $TempDir -Recurse -Force
        }
    }
}

$PowerShellLanStarter = Join-Path $Root "scripts/Start-CloudGatewayLan.ps1"
if ((Test-Path -LiteralPath $PowerShellGenerator) -and (Test-Path -LiteralPath $PowerShellLanStarter)) {
    $LanTempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxy-cloud-gateway-lan-test-" + [System.Guid]::NewGuid().ToString("N"))
    $LanAuthDir = Join-Path $LanTempDir "auth"
    try {
        New-Item -ItemType Directory -Path $LanAuthDir -Force | Out-Null
        @{
            type = "codex"
            email = "lan@example.test"
            disabled = $false
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $LanAuthDir "codex-lan.json") -Encoding UTF8

        $LanOutput = & $PowerShellLanStarter `
            -DeploymentDir $LanTempDir `
            -Domain "lan.example.test" `
            -ServerHost "192.0.2.10" `
            -Port 18448 `
            -LanPort 18080 `
            -SkipStart 2>&1 | Out-String

        Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "PowerShell LAN starter exits cleanly in SkipStart mode"
        Assert-Contains $LanOutput "Enabled Codex auth JSON file(s): 1" "PowerShell LAN starter reports enabled Codex auth count"
        Assert-NotContains $LanOutput "Downloading router-for-me/CLIProxyAPI" "PowerShell LAN starter SkipStart does not download CLIProxyAPI"
        Assert-NotContains $LanOutput "Downloading caddyserver/caddy" "PowerShell LAN starter SkipStart does not download Caddy"
        Assert-NotContains $LanOutput "access_token" "PowerShell LAN starter does not print access token values"
        Assert-NotContains $LanOutput "refresh_token" "PowerShell LAN starter does not print refresh token values"

        $LanCaddy = Read-TextIfPresent (Join-Path $LanTempDir "Caddyfile.lan")
        $LanConfig = Read-TextIfPresent (Join-Path $LanTempDir "config.yaml")
        $LanAuth = Get-Content -LiteralPath (Join-Path $LanAuthDir "codex-lan.json") -Raw | ConvertFrom-Json
        Assert-Contains $LanCaddy "http://192.0.2.10:18080" "PowerShell LAN starter writes LAN HTTP Caddyfile"
        Assert-Contains $LanCaddy "reverse_proxy 127.0.0.1:18448" "PowerShell LAN starter proxies to local CLIProxyAPI port"
        Assert-Contains $LanConfig 'host: "127.0.0.1"' "PowerShell LAN starter keeps CLIProxyAPI private"
        Assert-True -Condition ($LanAuth.websockets -eq $true) -Message "PowerShell LAN starter synchronizes auth metadata through generator"

        $LanStarterSource = Read-TextIfPresent $PowerShellLanStarter
        Assert-Contains $LanStarterSource "router-for-me/CLIProxyAPI" "PowerShell LAN starter can download CLIProxyAPI from GitHub releases"
        Assert-Contains $LanStarterSource "caddyserver/caddy" "PowerShell LAN starter can download Caddy from GitHub releases"
        Assert-Contains $LanStarterSource "Dependency exists, skip download" "PowerShell LAN starter skips existing binaries"
        Assert-NotContains $LanStarterSource 'Write-Output "Dependency exists, skip download' "PowerShell LAN starter does not mix dependency messages into returned paths"
    } catch {
        Assert-True -Condition $false -Message "PowerShell LAN starter scenario"
        Write-Host $_
    } finally {
        if (Test-Path -LiteralPath $LanTempDir) {
            Remove-Item -LiteralPath $LanTempDir -Recurse -Force
        }
    }
}

$PowerShellDoctor = Join-Path $Root "scripts/Test-CloudGatewayDoctor.ps1"
if ((Test-Path -LiteralPath $PowerShellGenerator) -and (Test-Path -LiteralPath $PowerShellDoctor)) {
    $ProxyTempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxy-cloud-gateway-proxy-test-" + [System.Guid]::NewGuid().ToString("N"))
    $ProxyAuthDir = Join-Path $ProxyTempDir "auth"
    try {
        New-Item -ItemType Directory -Path $ProxyAuthDir -Force | Out-Null
        @{
            type = "codex"
            email = "enabled@example.test"
            disabled = $false
            proxy_url = "http://old-proxy.example:8080"
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $ProxyAuthDir "codex-enabled.json") -Encoding UTF8
        @{
            type = "codex"
            email = "explicit-false@example.test"
            disabled = $false
            websockets = $false
            note = "keep-me"
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $ProxyAuthDir "codex-explicit-false.json") -Encoding UTF8

        $ProxyOutput = & $PowerShellGenerator `
            -Domain "proxy.example.test" `
            -OutputDir $ProxyTempDir `
            -AuthDir $ProxyAuthDir `
            -Port 18446 `
            -ApiKey "sk-proxy-test" `
            -UpstreamProxyMode Socks5 `
            -UpstreamProxyUrl "127.0.0.1:7897" 2>&1 | Out-String

        Assert-NotContains $ProxyOutput "sk-proxy-test" "PowerShell proxy generator does not print API key"

        $ProxyConfig = Read-TextIfPresent (Join-Path $ProxyTempDir "config.yaml")
        Assert-Contains $ProxyConfig 'proxy-url: "socks5://127.0.0.1:7897"' "Socks5 upstream proxy is normalized in config"

        $EnabledAuth = Get-Content -LiteralPath (Join-Path $ProxyAuthDir "codex-enabled.json") -Raw | ConvertFrom-Json
        $ExplicitFalseAuth = Get-Content -LiteralPath (Join-Path $ProxyAuthDir "codex-explicit-false.json") -Raw | ConvertFrom-Json
        Assert-True -Condition ($EnabledAuth.websockets -eq $true) -Message "auth metadata sync adds missing websockets true"
        Assert-True -Condition ($EnabledAuth.proxy_url -eq "socks5://127.0.0.1:7897") -Message "auth metadata sync writes normalized proxy_url"
        Assert-True -Condition ($ExplicitFalseAuth.websockets -eq $false) -Message "auth metadata sync preserves explicit websockets false"
        Assert-True -Condition ($ExplicitFalseAuth.proxy_url -eq "socks5://127.0.0.1:7897") -Message "auth metadata sync still writes proxy_url when websockets is explicit false"
        Assert-True -Condition ($ExplicitFalseAuth.note -eq "keep-me") -Message "auth metadata sync preserves unknown fields"

        $DoctorOutput = & $PowerShellDoctor -DeploymentDir $ProxyTempDir 2>&1 | Out-String
        Assert-True -Condition ($DoctorOutput.Contains("Failed: 0")) -Message "PowerShell doctor exits cleanly"
        Assert-Contains $DoctorOutput "Passed:" "PowerShell doctor reports pass count"
    } catch {
        Assert-True -Condition $false -Message "PowerShell upstream proxy and doctor scenario"
        Write-Host $_
    } finally {
        if (Test-Path -LiteralPath $ProxyTempDir) {
            Remove-Item -LiteralPath $ProxyTempDir -Recurse -Force
        }
    }
}

if (Test-Path -LiteralPath $PowerShellGenerator) {
    $DirectTempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxy-cloud-gateway-direct-test-" + [System.Guid]::NewGuid().ToString("N"))
    $DirectAuthDir = Join-Path $DirectTempDir "auth"
    try {
        New-Item -ItemType Directory -Path $DirectAuthDir -Force | Out-Null
        @{
            type = "codex"
            email = "direct@example.test"
            disabled = $false
            proxy_url = "http://stale-proxy.example:8080"
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $DirectAuthDir "codex-direct.json") -Encoding UTF8

        & $PowerShellGenerator `
            -Domain "direct.example.test" `
            -OutputDir $DirectTempDir `
            -AuthDir $DirectAuthDir `
            -Port 18447 `
            -ApiKey "sk-direct-test" `
            -UpstreamProxyMode Direct 2>&1 | Out-Null

        $DirectConfig = Read-TextIfPresent (Join-Path $DirectTempDir "config.yaml")
        $DirectAuth = Get-Content -LiteralPath (Join-Path $DirectAuthDir "codex-direct.json") -Raw | ConvertFrom-Json
        Assert-NotContains $DirectConfig 'proxy-url:' "Direct upstream mode omits config proxy-url"
        Assert-True -Condition (-not $DirectAuth.PSObject.Properties["proxy_url"]) -Message "Direct upstream mode removes stale auth proxy_url"
        Assert-True -Condition ($DirectAuth.websockets -eq $true) -Message "Direct upstream mode still adds missing websockets true"
    } catch {
        Assert-True -Condition $false -Message "PowerShell Direct proxy cleanup scenario"
        Write-Host $_
    } finally {
        if (Test-Path -LiteralPath $DirectTempDir) {
            Remove-Item -LiteralPath $DirectTempDir -Recurse -Force
        }
    }
}

$BashGenerator = Join-Path $Root "scripts/new-cloud-gateway.sh"
$BashLanStarter = Join-Path $Root "scripts/start-cloud-gateway-lan.sh"
$Bash = Get-Command bash -ErrorAction SilentlyContinue
if ((Test-Path -LiteralPath $BashGenerator) -and $Bash) {
    $EscapedBashGenerator = $BashGenerator.Replace("'", "'\''")
    $BashPathOutput = & $Bash.Source -lc "if command -v wslpath >/dev/null 2>&1; then wslpath -a '$EscapedBashGenerator'; elif command -v cygpath >/dev/null 2>&1; then cygpath -u '$EscapedBashGenerator'; else printf '%s\n' '$EscapedBashGenerator'; fi"
    $BashGeneratorForShell = ($BashPathOutput | Select-Object -First 1)

    & $Bash.Source -n $BashGeneratorForShell
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Bash generator has valid syntax"

    $BashTempDir = "/tmp/cliproxy-cloud-gateway-test-$([System.Guid]::NewGuid().ToString("N"))"
    try {
        $BashRunOutput = & $Bash.Source $BashGeneratorForShell `
            --domain "bash.example.test" `
            --output-dir $BashTempDir `
            --port 18445 `
            --api-key "sk-bash-test" `
            --upstream-proxy-mode http `
            --upstream-proxy-url "127.0.0.1:7897" 2>&1 | Out-String

        Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Bash generator exits cleanly"
        Assert-Contains $BashRunOutput "config.yaml" "Bash generator reports config path"
        Assert-NotContains $BashRunOutput "sk-bash-test" "Bash generator does not print API key"

        $BashCheck = @"
test -f '$BashTempDir/config.yaml' &&
test -f '$BashTempDir/Caddyfile' &&
test -f '$BashTempDir/client.env' &&
grep -q 'host: "127.0.0.1"' '$BashTempDir/config.yaml' &&
grep -q 'port: 18445' '$BashTempDir/config.yaml' &&
grep -q 'sk-bash-test' '$BashTempDir/config.yaml' &&
grep -q 'proxy-url: "http://127.0.0.1:7897"' '$BashTempDir/config.yaml' &&
grep -q 'passthrough-headers: true' '$BashTempDir/config.yaml' &&
grep -q 'request-retry: 1' '$BashTempDir/config.yaml' &&
grep -q 'max-retry-credentials: 1' '$BashTempDir/config.yaml' &&
grep -q 'max-retry-interval: 5' '$BashTempDir/config.yaml' &&
grep -q 'ANTHROPIC_BASE_URL=https://bash.example.test' '$BashTempDir/client.env' &&
grep -q 'ANTHROPIC_AUTH_TOKEN=sk-bash-test' '$BashTempDir/client.env' &&
grep -q '$DefaultCodexUserAgent' '$BashTempDir/config.yaml' &&
grep -q 'bash.example.test' '$BashTempDir/Caddyfile' &&
grep -q 'reverse_proxy 127.0.0.1:18445' '$BashTempDir/Caddyfile'
"@
        & $Bash.Source -lc $BashCheck
        Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Bash generator writes expected config and Caddyfile"

        if (Test-Path -LiteralPath $BashLanStarter) {
            $EscapedBashLanStarter = $BashLanStarter.Replace("'", "'\''")
            $BashLanStarterPathOutput = & $Bash.Source -lc "if command -v wslpath >/dev/null 2>&1; then wslpath -a '$EscapedBashLanStarter'; elif command -v cygpath >/dev/null 2>&1; then cygpath -u '$EscapedBashLanStarter'; else printf '%s\n' '$EscapedBashLanStarter'; fi"
            $BashLanStarterForShell = ($BashLanStarterPathOutput | Select-Object -First 1)
            & $Bash.Source -n $BashLanStarterForShell
            Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Bash LAN starter has valid syntax"

            $BashLanPrep = @"
mkdir -p '$BashTempDir/auth' &&
printf '%s\n' '{"type":"codex","email":"bash-lan@example.test","disabled":false}' > '$BashTempDir/auth/codex-lan.json'
"@
            & $Bash.Source -lc $BashLanPrep
            Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Bash LAN starter test auth is prepared"

            $BashLanOutput = & $Bash.Source $BashLanStarterForShell `
                --output-dir $BashTempDir `
                --domain "bash-lan.example.test" `
                --server-host "192.0.2.20" `
                --port 18449 `
                --lan-port 18081 `
                --skip-start 2>&1 | Out-String
            Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Bash LAN starter exits cleanly in skip-start mode"
            Assert-Contains $BashLanOutput "Enabled Codex auth JSON file(s): 1" "Bash LAN starter reports enabled Codex auth count"
            Assert-NotContains $BashLanOutput "Downloading router-for-me/CLIProxyAPI" "Bash LAN starter skip-start does not download CLIProxyAPI"
            Assert-NotContains $BashLanOutput "Downloading caddyserver/caddy" "Bash LAN starter skip-start does not download Caddy"
            Assert-NotContains $BashLanOutput "access_token" "Bash LAN starter does not print access token values"
            Assert-NotContains $BashLanOutput "refresh_token" "Bash LAN starter does not print refresh token values"

            $BashLanCheck = @"
grep -q 'http://192.0.2.20:18081' '$BashTempDir/Caddyfile.lan' &&
grep -q 'reverse_proxy 127.0.0.1:18449' '$BashTempDir/Caddyfile.lan'
"@
            & $Bash.Source -lc $BashLanCheck
            Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Bash LAN starter writes LAN Caddyfile"

            $BashLanSource = Read-TextIfPresent $BashLanStarter
            Assert-Contains $BashLanSource "router-for-me/CLIProxyAPI" "Bash LAN starter can download CLIProxyAPI from GitHub releases"
            Assert-Contains $BashLanSource "caddyserver/caddy" "Bash LAN starter can download Caddy from GitHub releases"
            Assert-Contains $BashLanSource "Dependency exists, skip download" "Bash LAN starter skips existing binaries"
        }

        $BashDoctor = Join-Path $Root "scripts/test-cloud-gateway-doctor.sh"
        if (Test-Path -LiteralPath $BashDoctor) {
            $EscapedBashDoctor = $BashDoctor.Replace("'", "'\''")
            $BashDoctorPathOutput = & $Bash.Source -lc "if command -v wslpath >/dev/null 2>&1; then wslpath -a '$EscapedBashDoctor'; elif command -v cygpath >/dev/null 2>&1; then cygpath -u '$EscapedBashDoctor'; else printf '%s\n' '$EscapedBashDoctor'; fi"
            $BashDoctorForShell = ($BashDoctorPathOutput | Select-Object -First 1)
            & $Bash.Source -n $BashDoctorForShell
            Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Bash doctor has valid syntax"
            $BashDoctorOutput = & $Bash.Source $BashDoctorForShell --deployment-dir $BashTempDir 2>&1 | Out-String
            Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Bash doctor exits cleanly"
            Assert-Contains $BashDoctorOutput "Passed:" "Bash doctor reports pass count"
        }
    } finally {
        & $Bash.Source -lc "rm -rf '$BashTempDir'" | Out-Null
    }
}

Write-Host ""
Write-Host "Passed: $script:Passed  Failed: $script:Failed"

if ($script:Failed -gt 0) {
    exit 1
}
