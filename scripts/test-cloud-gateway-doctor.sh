#!/usr/bin/env bash
set -euo pipefail

DEPLOYMENT_DIR='./generated'
CONFIG_PATH=''
CADDY_PATH=''
AUTH_DIR=''
PASSED=0
FAILED=0

usage() {
  cat <<'EOF'
Usage:
  test-cloud-gateway-doctor.sh [--deployment-dir DIR] [--config PATH] [--caddyfile PATH] [--auth-dir DIR]
EOF
}

assert_check() {
  local condition="$1"
  local message="$2"
  if eval "$condition"; then
    PASSED=$((PASSED + 1))
    printf '[PASS] %s\n' "$message"
  else
    FAILED=$((FAILED + 1))
    printf '[FAIL] %s\n' "$message"
  fi
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deployment-dir)
      [[ $# -ge 2 ]] || fail '--deployment-dir requires a value.'
      DEPLOYMENT_DIR="$2"
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || fail '--config requires a value.'
      CONFIG_PATH="$2"
      shift 2
      ;;
    --caddyfile)
      [[ $# -ge 2 ]] || fail '--caddyfile requires a value.'
      CADDY_PATH="$2"
      shift 2
      ;;
    --auth-dir)
      [[ $# -ge 2 ]] || fail '--auth-dir requires a value.'
      AUTH_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$CONFIG_PATH" ]] || CONFIG_PATH="$DEPLOYMENT_DIR/config.yaml"
[[ -n "$CADDY_PATH" ]] || CADDY_PATH="$DEPLOYMENT_DIR/Caddyfile"
[[ -n "$AUTH_DIR" ]] || AUTH_DIR="$DEPLOYMENT_DIR/auth"
CLIENT_ENV_PATH="$DEPLOYMENT_DIR/client.env"

assert_check "[[ -f '$CONFIG_PATH' ]]" 'config.yaml exists'
assert_check "[[ -f '$CADDY_PATH' ]]" 'Caddyfile exists'
assert_check "[[ -f '$CLIENT_ENV_PATH' ]]" 'client.env exists'

if [[ -f "$CONFIG_PATH" ]]; then
  assert_check "grep -Eq '^host: \"127\\.0\\.0\\.1\"$' '$CONFIG_PATH'" 'CLIProxyAPI binds to localhost'
  assert_check "grep -Eq '^  enable: false$' '$CONFIG_PATH'" 'CLIProxyAPI direct TLS is disabled'
  assert_check "grep -Eq '^  allow-remote: false$' '$CONFIG_PATH'" 'remote management is disabled'
  assert_check "grep -Eq '^  disable-control-panel: true$' '$CONFIG_PATH'" 'control panel is disabled'
  assert_check "grep -Eq '^passthrough-headers: true$' '$CONFIG_PATH'" 'upstream response headers are forwarded'
  assert_check "grep -Eq '^request-retry: 1$' '$CONFIG_PATH'" 'request retry is bounded'
  assert_check "grep -Eq '^max-retry-credentials: 1$' '$CONFIG_PATH'" 'credential retry is bounded'
  assert_check "grep -Eq '^max-retry-interval: 5$' '$CONFIG_PATH'" 'retry interval is bounded'
  assert_check "grep -Eq '^  antigravity-credits: false$' '$CONFIG_PATH'" 'Antigravity credit fallback is disabled'
  if grep -q '\"reasoning\"' "$CONFIG_PATH" || grep -q '\"reasoning.effort\"' "$CONFIG_PATH" || grep -q '\"thinking\"' "$CONFIG_PATH"; then
    printf '[INFO] Codex payload filter is configured; reasoning/thinking fields are disabled.\n'
  else
    printf '[INFO] Codex reasoning/thinking passthrough is enabled.\n'
  fi
  assert_check "grep -q 'codex-header-defaults:' '$CONFIG_PATH'" 'Codex header defaults are present'
fi

if [[ -f "$CADDY_PATH" ]]; then
  assert_check "grep -Eq 'reverse_proxy 127\\.0\\.0\\.1:' '$CADDY_PATH'" 'Caddy proxies to localhost'
fi

printf '\nPassed: %s  Failed: %s\n' "$PASSED" "$FAILED"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
