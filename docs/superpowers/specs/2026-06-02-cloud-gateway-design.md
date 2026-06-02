# Cloud Gateway Design

## Goal

Build a standalone deployment helper for Solution B: keep CLIProxyAPI private on
localhost, expose it through Caddy over HTTPS for a small trusted user set, and
carry over the CLIProxyAPI hardening rules from CodexToClaude that are relevant
to cloud deployment.

## Context

The referenced thread chose Solution B over direct public CLIProxyAPI exposure
and over sub2api. The key requirement is preserving the Codex OAuth default
header:

```yaml
codex-header-defaults:
  user-agent: 'codex_cli_rs/0.114.0 (Mac OS 14.2.0; x86_64) vscode/1.111.0'
```

CLIProxyAPI must bind to `127.0.0.1`, remote management must stay disabled, and
the public edge should be Caddy. Generated files must not contain OAuth tokens or
real credential JSON.

The enhanced config also needs these CodexToClaude-derived defaults:

- `passthrough-headers: true` to preserve upstream `X-Codex-*` usage headers.
- Bounded retry settings: `request-retry: 1`, `max-retry-credentials: 1`, and
  `max-retry-interval: 5`.
- `quota-exceeded.antigravity-credits: false`.
- `payload.filter` for `reasoning`, `reasoning.effort`, and `thinking` on Codex
  models.
- Optional upstream proxy support. Default is `Direct`, which omits
  `proxy-url`; `Http` and `Socks5` write normalized `proxy-url` values.

## Architecture

The project is a deployment kit, not an application server. It contains static
templates, two platform-specific generators, service helpers, documentation, and
tests. The generators write a local `config.yaml`, a matching `Caddyfile`, and
private working directories for auth and logs.

## Components

- `templates/cliproxy.config.template.yaml`: canonical CLIProxyAPI private
  config with placeholders and safe defaults.
- `templates/Caddyfile.template`: canonical Caddy reverse proxy template.
- `scripts/New-CloudGateway.ps1`: Windows generator for config, Caddyfile,
  client environment hints, optional upstream proxy, and auth metadata sync.
- `scripts/new-cloud-gateway.sh`: Linux generator for config, Caddyfile, client
  environment hints, optional upstream proxy, and auth metadata sync.
- `scripts/Test-CloudGatewayDoctor.ps1`: local doctor that checks config
  hardening, auth JSON metadata, proxy consistency, Caddyfile, and sensitive
  file patterns.
- `scripts/test-cloud-gateway-doctor.sh`: Linux doctor with the same checks.
- `windows/Register-CLIProxyAPI-Task.ps1`: Windows scheduled task helper.
- `linux/cliproxy.service.template`: Linux systemd unit template.
- `tests/Test-CloudGateway.ps1`: regression checks for templates and generated
  output.
- `docs/deployment.md`: operational guide for Windows and Linux.

## Error Handling

Generators fail early when the domain is missing, output paths are invalid, the
proxy mode is invalid, the proxy URL is missing for `Http` or `Socks5`, or
template files cannot be found. If an API key is not provided, the generator
creates a random `sk-cliproxy-*` key. API keys are written to `client.env`, and
generators print paths rather than echoing secrets.

Auth metadata sync processes only enabled `type=codex` JSON files under the auth
directory. It adds missing `websockets: true`, preserves explicit
`websockets: false`, syncs `proxy_url` for upstream proxy modes, and removes
`proxy_url` in Direct mode. It must preserve unknown fields.

## Testing

Tests validate required files, lock key private defaults, run the PowerShell and
Bash generators into temporary directories, exercise upstream proxy modes, verify
auth JSON metadata sync, run doctor scripts, and ensure generator output does not
echo API keys.

## Spec Self-Review

- No placeholder requirements remain.
- Scope is limited to one deployment kit.
- Windows and Linux paths are handled by separate focused scripts.
- Real OAuth secrets are explicitly out of scope.
- Optional upstream proxy affects only CLIProxyAPI-to-Codex traffic, not public
  user-to-Caddy traffic.
