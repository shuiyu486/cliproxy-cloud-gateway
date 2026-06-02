# Cloud Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and harden a standalone CLIProxyAPI + Caddy cloud gateway deployment kit for Windows and Linux.

**Architecture:** The kit is template-driven. Platform generators render safe CLIProxyAPI and Caddy configuration, optionally normalize upstream proxy settings, synchronize Codex auth metadata, and emit client environment hints without printing secrets. Doctor scripts validate the generated deployment.

**Tech Stack:** PowerShell 5.1+, Bash 4+, YAML/Caddyfile templates, PowerShell regression tests.

---

### Task 1: Enhanced Regression Tests

**Files:**
- Modify: `tests/Test-CloudGateway.ps1`

- [ ] **Step 1: Write the failing tests**

Update the PowerShell test script to assert `passthrough-headers`, bounded
retry, quota fallback, payload filtering, client env generation without API key
echoing, optional upstream proxy rendering, auth JSON metadata sync, and doctor
script success.

- [ ] **Step 2: Run the test to verify it fails**

Run: `.\tests\Test-CloudGateway.ps1`

Expected: FAIL because the enhanced defaults and doctor scripts do not exist yet.

### Task 2: Templates, Generators, And Auth Sync

**Files:**
- Modify: `templates/cliproxy.config.template.yaml`
- Modify: `scripts/New-CloudGateway.ps1`
- Modify: `scripts/new-cloud-gateway.sh`

- [ ] **Step 1: Implement hardened templates**

The CLIProxyAPI template must include localhost binding, disabled remote
management, Caddy-only public exposure, API keys, Codex user agent,
`passthrough-headers: true`, bounded retry, quota fallback, payload filtering,
and an optional `{{PROXY_URL_BLOCK}}`.

- [ ] **Step 2: Implement generator options**

Render templates with domain, output directory, port, auth directory, log
directory, API keys, default Codex user agent, `Direct|Http|Socks5` upstream
proxy mode, normalized proxy URL, `client.env`, and auth metadata sync.

- [ ] **Step 3: Run tests**

Run: `.\tests\Test-CloudGateway.ps1`

Expected: PASS for template checks and PowerShell generation.

### Task 3: Doctor Scripts And Documentation

**Files:**
- Create: `scripts/Test-CloudGatewayDoctor.ps1`
- Create: `scripts/test-cloud-gateway-doctor.sh`
- Modify: `README.md`
- Modify: `docs/deployment.md`
- Modify: `.gitignore`

- [ ] **Step 1: Add doctor scripts**

Doctor scripts check config hardening, proxy/auth consistency, Caddyfile routing,
and sensitive file patterns without printing raw token fields.

- [ ] **Step 2: Add docs**

Document upstream proxy purpose, defaults, auth metadata synchronization, doctor
commands, client environment variables, and security defaults.

- [ ] **Step 3: Run final verification**

Run: `.\tests\Test-CloudGateway.ps1`

Expected: all tests pass and no generated secrets are tracked.

## Self-Review

- The plan maps each design component to an implementation task.
- No unbounded platform packaging or sub2api platform features are included.
- The test-first step precedes production files.
- The plan includes the user-approved upstream proxy option as a default-off
  feature.
