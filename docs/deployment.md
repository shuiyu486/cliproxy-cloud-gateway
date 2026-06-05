# Deployment Guide

## Design

This project implements Solution B:

```text
client -> https://api.example.com -> Caddy -> http://127.0.0.1:8317 -> CLIProxyAPI
```

CLIProxyAPI stays private. Caddy handles the public HTTPS listener, certificate
automation, and reverse proxying. CLIProxyAPI API keys still protect the API
surface.

## Prerequisites

- A domain with DNS pointing to the server.
- Open inbound TCP 80 and 443 for Caddy.
- CLIProxyAPI installed on the server, or downloaded by the Linux cloud installer / LAN one-click test script.
- Caddy installed on the server, or downloaded by the Linux cloud installer / LAN one-click test script.
- Existing CLIProxyAPI OAuth auth JSON files copied into the generated `auth`
  directory.

Do not expose the generated CLIProxyAPI port to the internet. Keep it bound to
`127.0.0.1`.

The generator synchronizes enabled `type=codex` auth JSON files in the auth
directory:

- missing `websockets` is set to `true`;
- explicit `websockets: false` is preserved;
- Direct mode removes stale `proxy_url`;
- Http/Socks5 mode writes a normalized `proxy_url`.

## Windows

Generate files:

```powershell
.\scripts\New-CloudGateway.ps1 `
  -Domain "api.example.com" `
  -OutputDir "C:\Services\cliproxy-gateway" `
  -Port 8317
```

If the server needs a proxy to reach Codex upstream:

```powershell
.\scripts\New-CloudGateway.ps1 `
  -Domain "api.example.com" `
  -OutputDir "C:\Services\cliproxy-gateway" `
  -UpstreamProxyMode Socks5 `
  -UpstreamProxyUrl "127.0.0.1:7897"
```

Check the generated deployment:

```powershell
.\scripts\Test-CloudGatewayDoctor.ps1 -DeploymentDir "C:\Services\cliproxy-gateway"
```

Start CLIProxyAPI manually for a first check:

```powershell
C:\Services\cli-proxy-api\cli-proxy-api.exe --config C:\Services\cliproxy-gateway\config.yaml
```

Register a scheduled task after the manual check:

```powershell
.\windows\Register-CLIProxyAPI-Task.ps1 `
  -BinaryPath "C:\Services\cli-proxy-api\cli-proxy-api.exe" `
  -ConfigPath "C:\Services\cliproxy-gateway\config.yaml" `
  -WorkingDirectory "C:\Services\cliproxy-gateway"
```

Install the generated Caddyfile according to your Caddy Windows setup, then run:

```powershell
caddy validate --config C:\Services\cliproxy-gateway\Caddyfile
caddy run --config C:\Services\cliproxy-gateway\Caddyfile
```

For a LAN smoke test, `Start-CloudGatewayLan.ps1` can download missing Windows CLIProxyAPI and Caddy binaries from fixed GitHub release sources and start both services. If `-ServerHost` is provided, it must be a LAN IPv4 address assigned to the Windows machine; otherwise the script selects a non-virtual adapter address. If private port `8317` is already occupied, the script chooses a nearby free private port and points Caddy to it. When an upstream proxy is configured, the script preflights the proxy host and port before starting services. The CLIProxyAPI console may initially print `0 clients`; check the later `full client load complete` log line. Codex OAuth JSON is counted as `auth files`, not necessarily as `Codex keys`.

For long-term Windows LAN use, do not forward the LAN port from the router to the internet. Prefer a Windows Firewall rule that allows only the trusted Mac's fixed LAN IP to reach the LAN port. The Windows host itself can use the same Caddy/CLIProxyAPI pair through `http://127.0.0.1:<LanPort>` instead of starting another CLIProxyAPI process.

## Linux

For one-click cloud deployment:

```bash
bash ./scripts/install-cloud-gateway.sh \
  --domain api.example.com \
  --install-dir /opt/cliproxy-gateway
```

The installer generates deployment files, downloads missing Linux CLIProxyAPI/Caddy binaries from fixed GitHub release sources, renders the CLIProxyAPI systemd service from `linux/cliproxy.service.template`, installs the generated Caddyfile, reloads Caddy when a systemd Caddy service exists, and runs doctor checks. It prints paths and status only; API keys remain in `client.env` and are not printed.

For a generate-only dry run that does not change services, add:

```bash
--skip-download --skip-systemd --skip-caddy-reload
```

Generate files manually:

```bash
bash ./scripts/new-cloud-gateway.sh \
  --domain api.example.com \
  --output-dir /opt/cliproxy-gateway \
  --port 8317
```

If the server needs a proxy to reach Codex upstream:

```bash
bash ./scripts/new-cloud-gateway.sh \
  --domain api.example.com \
  --output-dir /opt/cliproxy-gateway \
  --upstream-proxy-mode socks5 \
  --upstream-proxy-url 127.0.0.1:7897
```

Check the generated deployment:

```bash
bash ./scripts/test-cloud-gateway-doctor.sh --deployment-dir /opt/cliproxy-gateway
```

Install the generated Caddyfile:

```bash
sudo cp /opt/cliproxy-gateway/Caddyfile /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

For a LAN smoke test, `scripts/start-cloud-gateway-lan.sh` can download missing Linux CLIProxyAPI and Caddy binaries from fixed GitHub release sources and start both services.

Create a systemd service from `linux/cliproxy.service.template` by replacing:

```text
{{SERVICE_USER}}
{{INSTALL_DIR}}
{{BINARY_PATH}}
{{CONFIG_PATH}}
```

Then enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cliproxy
```

## Client Configuration

For Claude Code compatible clients:

```bash
source /opt/cliproxy-gateway/client.env
```

On Windows, read `C:\Services\cliproxy-gateway\client.env` and copy those values
into your client environment. The generator writes the first API key there and
does not print API keys to stdout.

For OpenAI-compatible clients, use the same base URL and put the API key in the
client's bearer token setting.

## Security Defaults

The generated `config.yaml` keeps these defaults:

```yaml
host: "127.0.0.1"

tls:
  enable: false

remote-management:
  allow-remote: false
  secret-key: ""
  disable-control-panel: true

codex-header-defaults:
  user-agent: 'codex_cli_rs/0.114.0 (Mac OS 14.2.0; x86_64) vscode/1.111.0'

passthrough-headers: true

quota-exceeded:
  switch-project: true
  switch-preview-model: true
  antigravity-credits: false

request-retry: 1
max-retry-credentials: 1
max-retry-interval: 5

payload:
  filter:
    - models:
        - name: "gpt-*"
          protocol: "codex"
      params:
        - "reasoning"
        - "reasoning.effort"
        - "thinking"
```

The TLS setting is disabled in CLIProxyAPI because Caddy terminates HTTPS. Do
not change `host` to an empty string unless you intend to expose CLIProxyAPI
directly.

## Multiple Users

Pass one or more API keys:

```powershell
.\scripts\New-CloudGateway.ps1 -Domain "api.example.com" -ApiKey @("sk-user-a", "sk-user-b")
```

```bash
bash ./scripts/new-cloud-gateway.sh --domain api.example.com --api-key sk-user-a --api-key sk-user-b
```

If no API key is supplied, the generator creates one random key. It is written to
`config.yaml` and `client.env`, but not printed to stdout.

## Upstream Proxy

`UpstreamProxyMode` controls only this leg:

```text
CLIProxyAPI -> Codex / ChatGPT upstream
```

It does not affect public users connecting to Caddy. Defaults:

| Mode | Behavior |
|---|---|
| `Direct` | omit `proxy-url` and remove stale auth JSON `proxy_url` |
| `Http` | normalize `host:port` to `http://host:port` |
| `Socks5` | normalize `host:port` to `socks5://host:port` |

Use Direct when the server can reach upstream normally. Use Http or Socks5 only
when the server must reach upstream through a known proxy exit.

## References

- CLIProxyAPI basic configuration: https://help.router-for.me/configuration/basic
- CLIProxyAPI management API behavior: https://help.router-for.me/management/api
- Caddy reverse proxy directive: https://caddyserver.com/docs/caddyfile/directives/reverse_proxy
