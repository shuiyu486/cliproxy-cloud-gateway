# Deployment Guide

## Design

The gateway has one fixed private service and one selectable public entry:

```text
client -> public HTTPS entry -> http://127.0.0.1:8317 -> CLIProxyAPI -> Codex / ChatGPT upstream
```

Rules that do not change:

- CLIProxyAPI stays private and binds to `127.0.0.1`.
- port `8317` must not be exposed publicly.
- The public HTTPS entry handles certificates and reverse proxying.
- `UpstreamProxyMode` controls only outbound `CLIProxyAPI -> Codex / ChatGPT upstream` traffic.

## Public Entry Options

| Scenario | Public entry | Private target |
|---|---|---|
| New cloud server where this project may own 80/443 | Caddy | `http://127.0.0.1:8317` |
| Existing BaoTa / aaPanel Apache already owns 80/443 | Panel-managed Apache | `http://127.0.0.1:8317` |

The default deployment path is Caddy. Use the BaoTa / aaPanel path only when an
existing panel-managed site already owns ports 80/443.

## Common Prerequisites

- A domain with DNS pointing to the server.
- CLIProxyAPI installed on the server, or downloaded by the Linux cloud installer / LAN one-click test script.
- Existing CLIProxyAPI OAuth auth JSON files copied into the generated `auth`
  directory.
- For the default Caddy path, inbound TCP 80 and 443 must be available to Caddy.
- For the BaoTa / aaPanel path, the panel site must provide HTTPS and reverse proxying.

The generator synchronizes enabled `type=codex` auth JSON files in the auth
directory:

- missing `websockets` is set to `true`;
- explicit `websockets: false` is preserved;
- Direct mode removes stale `proxy_url`;
- Http/Socks5 mode writes a normalized `proxy_url`.

## Existing BaoTa / aaPanel Apache on 80/443

Use this flow when a BaoTa / aaPanel Apache site already handles the public 80/443
ports:

```text
client -> Apache HTTPS (BaoTa / aaPanel) -> http://127.0.0.1:8317 -> CLIProxyAPI -> Codex / ChatGPT upstream
```

Minimal panel-side flow:

1. Generate and start the gateway normally so CLIProxyAPI listens on
   `127.0.0.1:8317`.
2. In BaoTa / aaPanel, create or select the API domain site, for example
   `api.example.com`.
3. Enable HTTPS for that site in the panel.
4. Add a reverse proxy from the API domain to `http://127.0.0.1:8317`.
5. Keep caller configuration pointed at the public HTTPS domain from
   `client.env`, not at `127.0.0.1`.

### WAF notes

This API domain carries JSON POST requests, authorization headers, query-string
requests such as `/v1/messages?beta=true`, and streaming responses. Generic
website WAF / request filtering rules can mistake these API requests for invalid
web traffic and return `416` or an Apache website firewall page.

For the API site, disable the panel WAF or at least allowlist `/v1/*`, including
query-string requests and streaming responses. Prefer a path-scoped exception
for `/v1/*` instead of changing protection for unrelated websites on the same
server.

Do not confuse this with `UpstreamProxyMode`: BaoTa / aaPanel Apache is inbound
`client -> gateway` traffic, while `UpstreamProxyMode` controls outbound
`CLIProxyAPI -> Codex / ChatGPT upstream` traffic.

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

`client.env` is not a runtime dependency for CLIProxyAPI or Caddy. It is only a
caller-side reference file. If you regenerate deployment files, preserve the old
API key by passing `--api-key` / `-ApiKey`; otherwise the generator creates a new
key and existing callers may stop working.

## After Installation

After the Linux installer or manual setup finishes, the normal post-install flow
is:

1. Put enabled `type=codex` OAuth JSON files under the generated `auth/`
   directory, or run CLIProxyAPI device login on the server.
2. Restart CLIProxyAPI so it reloads `auth/*.json` and `config.yaml`.
3. Configure callers with only the public base URL and client API key from
   `client.env`.
4. Keep callers pointed at the public HTTPS entry. Do not point them at
   `127.0.0.1:8317` unless the caller runs on the same host for a local-only
   diagnostic.

For the default Linux service name:

```bash
sudo systemctl restart cliproxy
sudo systemctl status cliproxy --no-pager
sudo systemctl status caddy --no-pager
```

If you changed `--service-name`, replace `cliproxy` with the actual service
name.

## First Verification

Check the public HTTPS entry first:

```bash
curl -i https://api.example.com/v1/messages
```

A `404` or `405` response can still be useful at this stage because it proves the
request reached the public entry and was reverse-proxied to the server-side API
path. Connection, DNS, or TLS failures should be fixed before debugging
CLIProxyAPI auth.

Then send a minimal Anthropic-compatible `/v1/messages` request using the values
from `client.env`:

```bash
source /opt/cliproxy-gateway/client.env

curl "$ANTHROPIC_BASE_URL/v1/messages" \
  -H "content-type: application/json" \
  -H "x-api-key: $ANTHROPIC_AUTH_TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "gpt-5",
    "max_tokens": 64,
    "messages": [
      {"role": "user", "content": "ping"}
    ]
  }'
```

The important wire shape is:

- endpoint: `POST <ANTHROPIC_BASE_URL>/v1/messages`;
- auth header: `x-api-key: <client API key from client.env>`;
- version header: `anthropic-version: 2023-06-01`;
- JSON body with `model`, `max_tokens`, and `messages`.

If this request reaches CLIProxyAPI but fails upstream, check CLIProxyAPI logs,
`auth/*.json`, account entitlement, server egress, and `UpstreamProxyMode`.

## Routine Maintenance

Common Linux checks:

```bash
sudo systemctl status cliproxy --no-pager
sudo systemctl status caddy --no-pager
sudo journalctl -u cliproxy -n 100 --no-pager
```

Change handling:

| Change | Required action |
|---|---|
| Add, remove, or edit `auth/*.json` | Restart CLIProxyAPI. |
| Edit `config.yaml` | Restart CLIProxyAPI. |
| Edit `Caddyfile` | Run `caddy validate`, then reload Caddy. |
| Edit caller environment variables | Restart or reopen the caller only. |
| Change `UpstreamProxyMode` / `UpstreamProxyUrl` | Regenerate or edit config, synchronize auth metadata, then restart CLIProxyAPI. |

Caddy automatic certificate renewal only applies when Caddy directly owns the
public 80/443 entry and the domain resolves to this server. When BaoTa / aaPanel
Apache owns 80/443, certificate lifecycle is managed by the panel site instead.

## Upgrade and Backup

Before replacing binaries or regenerating files, back up the deployment state:

```bash
sudo tar -czf /root/cliproxy-gateway-backup.tgz \
  -C /opt/cliproxy-gateway \
  config.yaml Caddyfile client.env auth
```

Keep these rules in mind:

- `auth/` and `client.env` are sensitive. Do not commit or paste them into issue
  reports.
- Re-running a generator without `--api-key` / `-ApiKey` creates a new client API
  key. Pass the existing key explicitly if callers must keep working.
- If you only replace the CLIProxyAPI binary, restart CLIProxyAPI.
- If you only replace the Caddy binary or Caddyfile, validate and reload Caddy.
- Do not commit generated `config.yaml`, `Caddyfile`, `client.env`, auth JSON,
  logs, or downloaded binaries.

## Troubleshooting

| Symptom | Check first |
|---|---|
| Domain cannot be reached | DNS, cloud firewall / security group, inbound 80/443, and whether the selected public entry is running. |
| TLS or certificate failure | Caddy ownership of 80/443 in the default path, or panel HTTPS settings in the BaoTa / aaPanel path. |
| API returns 401 / 403 | Caller uses the client API key from `client.env`, and the request sends it as `x-api-key`. |
| API returns 502 / bad gateway | CLIProxyAPI service status and whether the public entry proxies to `127.0.0.1:8317`. |
| BaoTa / aaPanel returns `416` or a firewall page | Disable WAF for the API site or allowlist `/v1/*`, `/v1/messages?beta=true`, JSON POST bodies, headers, and streaming responses. |
| CLIProxyAPI has no usable clients | Enabled `type=codex` JSON exists directly under `auth/`, is readable by the service user, and is not a settings/test/temp file. |
| Upstream requests fail | Server egress IP, proxy exit, account entitlement, `UpstreamProxyMode`, and normalized `proxy_url` in enabled auth JSON. |
| Thinking or reasoning fields behave unexpectedly | Confirm no manual `payload.filter` is configured unless you intentionally disabled those fields. |

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
```

The generated config does not include `payload.filter` by default. Reasoning,
thinking, and effort fields pass through so Claude Code `/effort` or client-side
settings can take effect naturally. If thinking output becomes too long, repeated
characters appear, or the TUI renders thinking deltas poorly, you can manually add
this block to `config.yaml`:

```yaml
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
