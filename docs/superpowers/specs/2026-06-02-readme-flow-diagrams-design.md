# README Flow Diagram Design

## Goal

Make the README "how it works" section easier to understand for first-time users and maintainers.

The current diagram shows the basic chain:

```text
client -> Caddy HTTPS -> CLIProxyAPI -> Codex / ChatGPT upstream
```

That is accurate but too compressed. It does not make the deployment boundary, localhost-only listener, optional upstream proxy, generated files, or caller-side `client.env` role clear enough.

## Scope

Update documentation only:

- `README.md`
- `README.en-US.md`
- `tests/Test-CloudGateway.ps1`

No deployment generator, Caddy template, CLIProxyAPI template, doctor script, or runtime behavior changes are required.

## Diagram Structure

Use two complementary Mermaid diagrams.

### 1. Main Runtime Flow

Place this near the top of the README, replacing the current single-line diagram.

The diagram should show these zones:

- Caller device
- Public internet entry
- Cloud server private localhost boundary
- Optional upstream proxy
- Codex / ChatGPT upstream

The diagram must communicate:

- The caller only connects to `https://your-domain`.
- Caddy is the only public HTTPS entry point.
- Caddy forwards to CLIProxyAPI through `127.0.0.1:8317`.
- CLIProxyAPI is not directly exposed to the internet.
- CLIProxyAPI reads `config.yaml` and `auth/*.json`.
- Optional upstream proxy affects only the `CLIProxyAPI -> upstream` outbound leg.
- Codex / ChatGPT upstream is reached by CLIProxyAPI, not directly by the caller.

### 2. Generated Files And Who Uses Them

Place this near the "Generated Files" section.

The diagram should show:

- Generator command produces `config.yaml`, `Caddyfile`, `client.env`, `auth/`, and `logs/`.
- `config.yaml` is consumed by CLIProxyAPI.
- `Caddyfile` is consumed by Caddy.
- `auth/*.json` is read by CLIProxyAPI for Codex OAuth credentials.
- `logs/` is written by CLIProxyAPI.
- `client.env` is copied by the caller as a reference for `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN`.

This diagram must reinforce that `client.env` is not a runtime dependency of Caddy or CLIProxyAPI.

## Text Changes

Update the surrounding Chinese and English prose so the diagrams are not left to carry all meaning alone.

Chinese README should keep Chinese as the default language and use terms like:

- `调用方`
- `公网入口`
- `云服务器本机`
- `可选上游代理`
- `上游`

English README should mirror the same meaning with:

- `Caller`
- `Public entry`
- `Cloud server localhost`
- `Optional upstream proxy`
- `Upstream`

## Testing

Extend `tests/Test-CloudGateway.ps1` so README checks assert the new documentation shape:

- Chinese README contains a Mermaid diagram with `subgraph` zones.
- Chinese README mentions `公网入口`, `云服务器本机`, and `可选上游代理`.
- Chinese README includes a generated-files flow diagram.
- English README contains the equivalent zone labels.
- English README includes a generated-files flow diagram.
- Existing checks for plain-text flow, Caddy HTTPS, CLIProxyAPI, upstream proxy, doctor, and security defaults continue to pass.

## Non-Goals

- Do not create images or binary assets.
- Do not introduce a docs build system.
- Do not replace Mermaid with SVG.
- Do not change generated deployment behavior.
- Do not add new CLI options.

## Acceptance Criteria

- The README top section clearly explains the runtime request path.
- The generated files section clearly explains which component uses each generated file.
- `client.env` is visibly documented as caller-side reference material, not a service dependency.
- Chinese and English READMEs stay aligned.
- `.\tests\Test-CloudGateway.ps1` passes.
