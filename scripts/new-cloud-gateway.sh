#!/usr/bin/env bash
set -euo pipefail

DEFAULT_CODEX_USER_AGENT='codex_cli_rs/0.114.0 (Mac OS 14.2.0; x86_64) vscode/1.111.0'

DOMAIN=''
OUTPUT_DIR='./generated'
PORT='8317'
AUTH_DIR=''
CODEX_USER_AGENT="$DEFAULT_CODEX_USER_AGENT"
UPSTREAM_PROXY_MODE='Direct'
UPSTREAM_PROXY_URL=''
API_KEYS=()

usage() {
  cat <<'EOF'
Usage:
  new-cloud-gateway.sh --domain api.example.com [options]

Options:
  --domain HOST             Public domain handled by Caddy.
  --output-dir DIR          Generated file directory. Default: ./generated
  --port PORT               Private CLIProxyAPI port. Default: 8317
  --auth-dir DIR            CLIProxyAPI auth directory. Default: OUTPUT_DIR/auth
  --api-key KEY             Client API key. Can be repeated.
  --codex-user-agent VALUE  Codex OAuth user-agent fallback.
  --upstream-proxy-mode MODE Direct, Http, or Socks5. Default: Direct
  --upstream-proxy-url URL   Upstream proxy used by CLIProxyAPI to reach Codex.
  -h, --help                Show this help.
EOF
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

yaml_single_content() {
  printf '%s' "$1" | sed "s/'/''/g"
}

yaml_single_value() {
  printf "'%s'" "$(yaml_single_content "$1")"
}

generate_api_key() {
  if command -v openssl >/dev/null 2>&1; then
    printf 'sk-cliproxy-%s\n' "$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=')"
    return
  fi

  fail 'openssl is required to generate a random API key; pass --api-key to avoid generation.'
}

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$(pwd)" "$1" ;;
  esac
}

normalize_proxy_mode() {
  case "${1,,}" in
    direct) printf 'Direct\n' ;;
    http) printf 'Http\n' ;;
    socks5) printf 'Socks5\n' ;;
    *) fail "invalid upstream proxy mode: $1" ;;
  esac
}

normalize_proxy_url() {
  local mode="$1"
  local url="$2"

  if [[ "$mode" == 'Direct' ]]; then
    printf '\n'
    return
  fi

  [[ -n "$url" ]] || fail "--upstream-proxy-url is required when --upstream-proxy-mode is $mode."

  if [[ "$mode" == 'Http' ]]; then
    case "$url" in
      http://*|https://*) printf '%s\n' "$url" ;;
      socks5://*) fail 'Http mode cannot use a socks5:// upstream proxy URL.' ;;
      *) printf 'http://%s\n' "$url" ;;
    esac
    return
  fi

  case "$url" in
    socks5://*) printf '%s\n' "$url" ;;
    http://*|https://*) fail 'Socks5 mode cannot use an HTTP upstream proxy URL.' ;;
    *) printf 'socks5://%s\n' "$url" ;;
  esac
}

sync_auth_metadata() {
  local auth_dir="$1"
  local proxy_url="$2"
  local py=''

  [[ -d "$auth_dir" ]] || {
    printf '0\n'
    return
  }

  if command -v python3 >/dev/null 2>&1; then
    py="$(command -v python3)"
  elif command -v python >/dev/null 2>&1; then
    py="$(command -v python)"
  else
    if find "$auth_dir" -maxdepth 1 -type f -name '*.json' | grep -q .; then
      fail 'python3 or python is required to sync Codex auth metadata.'
    fi
    printf '0\n'
    return
  fi

  "$py" - "$auth_dir" "$proxy_url" <<'PY'
import json
import re
import sys
from pathlib import Path

auth_dir = Path(sys.argv[1])
proxy_url = sys.argv[2]
updated = 0

for path in auth_dir.glob("*.json"):
    if re.search(r"settings|test|temp|^codextoclaude-", path.name):
        continue
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        continue
    if not isinstance(data, dict):
        continue
    if data.get("type") != "codex" or data.get("disabled") is True:
        continue
    if "websockets" not in data:
        data["websockets"] = True
    if proxy_url:
        data["proxy_url"] = proxy_url
    else:
        data.pop("proxy_url", None)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    updated += 1

print(updated)
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      [[ $# -ge 2 ]] || fail '--domain requires a value.'
      DOMAIN="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || fail '--output-dir requires a value.'
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || fail '--port requires a value.'
      PORT="$2"
      shift 2
      ;;
    --auth-dir)
      [[ $# -ge 2 ]] || fail '--auth-dir requires a value.'
      AUTH_DIR="$2"
      shift 2
      ;;
    --api-key)
      [[ $# -ge 2 ]] || fail '--api-key requires a value.'
      API_KEYS+=("$2")
      shift 2
      ;;
    --codex-user-agent)
      [[ $# -ge 2 ]] || fail '--codex-user-agent requires a value.'
      CODEX_USER_AGENT="$2"
      shift 2
      ;;
    --upstream-proxy-mode)
      [[ $# -ge 2 ]] || fail '--upstream-proxy-mode requires a value.'
      UPSTREAM_PROXY_MODE="$(normalize_proxy_mode "$2")"
      shift 2
      ;;
    --upstream-proxy-url)
      [[ $# -ge 2 ]] || fail '--upstream-proxy-url requires a value.'
      UPSTREAM_PROXY_URL="$2"
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

[[ -n "$DOMAIN" ]] || fail '--domain is required.'
[[ "$DOMAIN" != *'://'* ]] || fail 'domain must be a host name, not a URL.'
[[ "$DOMAIN" != */* ]] || fail 'domain must not contain a path.'
[[ "$PORT" =~ ^[0-9]+$ ]] || fail 'port must be numeric.'
(( PORT >= 1 && PORT <= 65535 )) || fail 'port must be between 1 and 65535.'

NORMALIZED_PROXY_URL="$(normalize_proxy_url "$UPSTREAM_PROXY_MODE" "$UPSTREAM_PROXY_URL")"
PROXY_URL_BLOCK=''
if [[ -n "$NORMALIZED_PROXY_URL" ]]; then
  PROXY_URL_BLOCK="proxy-url: \"$NORMALIZED_PROXY_URL\""
fi

if [[ ${#API_KEYS[@]} -eq 0 ]]; then
  API_KEYS+=("$(generate_api_key)")
fi

if [[ "${BASH_SOURCE[0]:-}" == */* ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  PROJECT_ROOT="$(pwd)"
fi

TEMPLATE_DIR="$PROJECT_ROOT/templates"
CONFIG_TEMPLATE_PATH="$TEMPLATE_DIR/cliproxy.config.template.yaml"
CADDY_TEMPLATE_PATH="$TEMPLATE_DIR/Caddyfile.template"

[[ -f "$CONFIG_TEMPLATE_PATH" ]] || fail "template not found: $CONFIG_TEMPLATE_PATH"
[[ -f "$CADDY_TEMPLATE_PATH" ]] || fail "template not found: $CADDY_TEMPLATE_PATH"

OUTPUT_DIR="$(absolute_path "$OUTPUT_DIR")"
if [[ -z "$AUTH_DIR" ]]; then
  AUTH_DIR="$OUTPUT_DIR/auth"
else
  AUTH_DIR="$(absolute_path "$AUTH_DIR")"
fi
LOGS_DIR="$OUTPUT_DIR/logs"

umask 077
mkdir -p "$OUTPUT_DIR" "$AUTH_DIR" "$LOGS_DIR"

api_keys_yaml=''
for key in "${API_KEYS[@]}"; do
  line="  - $(yaml_single_value "$key")"
  if [[ -z "$api_keys_yaml" ]]; then
    api_keys_yaml="$line"
  else
    api_keys_yaml="${api_keys_yaml}"$'\n'"$line"
  fi
done

config_template="$(cat "$CONFIG_TEMPLATE_PATH")"
config="${config_template//\{\{PORT\}\}/$PORT}"
config="${config//\{\{PROXY_URL_BLOCK\}\}/$PROXY_URL_BLOCK}"
config="${config//\{\{AUTH_DIR\}\}/$(yaml_single_content "$AUTH_DIR")}"
config="${config//\{\{API_KEYS_YAML\}\}/$api_keys_yaml}"
config="${config//\{\{CODEX_USER_AGENT\}\}/$(yaml_single_content "$CODEX_USER_AGENT")}"

caddy_template="$(cat "$CADDY_TEMPLATE_PATH")"
caddyfile="${caddy_template//\{\{DOMAIN\}\}/$DOMAIN}"
caddyfile="${caddyfile//\{\{PORT\}\}/$PORT}"

config_path="$OUTPUT_DIR/config.yaml"
caddy_path="$OUTPUT_DIR/Caddyfile"
client_env_path="$OUTPUT_DIR/client.env"

printf '%s\n' "$config" > "$config_path"
printf '%s\n' "$caddyfile" > "$caddy_path"
{
  printf 'ANTHROPIC_BASE_URL=https://%s\n' "$DOMAIN"
  printf 'ANTHROPIC_AUTH_TOKEN=%s\n' "${API_KEYS[0]}"
} > "$client_env_path"

synced_auth_count="$(sync_auth_metadata "$AUTH_DIR" "$NORMALIZED_PROXY_URL")"

printf 'Generated config.yaml: %s\n' "$config_path"
printf 'Generated Caddyfile: %s\n' "$caddy_path"
printf 'Generated client.env: %s\n' "$client_env_path"
printf 'Auth directory: %s\n' "$AUTH_DIR"
printf 'Logs directory: %s\n' "$LOGS_DIR"
printf 'Upstream proxy mode: %s\n' "$UPSTREAM_PROXY_MODE"
if [[ -n "$NORMALIZED_PROXY_URL" ]]; then
  printf 'Upstream proxy URL: %s\n' "$NORMALIZED_PROXY_URL"
fi
printf 'Synced Codex auth file(s): %s\n' "$synced_auth_count"
printf 'API keys were written to config.yaml and client.env.\n'
