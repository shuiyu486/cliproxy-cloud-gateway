#!/usr/bin/env bash
set -euo pipefail

DEPLOYMENT_DIR='./cliproxy-gateway'
BINARY_PATH=''
DOMAIN='cliproxy.lan'
PORT='8317'
LAN_PORT='8080'
SERVER_HOST=''
UPSTREAM_PROXY_MODE='direct'
UPSTREAM_PROXY_URL=''
CADDY_PATH='caddy'
NO_REGENERATE=0
SKIP_START=0
SKIP_CADDY=0
SKIP_DOWNLOAD=0

usage() {
  cat <<'EOF'
Usage:
  start-cloud-gateway-lan.sh [options]

Options:
  --output-dir DIR           Deployment directory. Default: ./cliproxy-gateway
  --binary-path PATH         CLIProxyAPI binary path. Default: OUTPUT_DIR/cli-proxy-api/cli-proxy-api
  --domain HOST              Generated domain placeholder. Default: cliproxy.lan
  --port PORT                Private CLIProxyAPI port. Default: 8317
  --lan-port PORT            LAN Caddy HTTP port. Default: 8080
  --server-host HOST         LAN host/IP for Caddyfile.lan. Default: first non-loopback IPv4 or 127.0.0.1
  --upstream-proxy-mode MODE direct, http, or socks5. Default: direct
  --upstream-proxy-url URL   Upstream proxy used by CLIProxyAPI to reach Codex.
  --caddy-path PATH          Caddy binary/command. Default: caddy
  --no-regenerate            Do not call new-cloud-gateway.sh.
  --skip-start               Generate and diagnose only; do not start services or download binaries.
  --skip-caddy               Do not start Caddy.
  --skip-download            Fail instead of downloading missing binaries.
  -h, --help                 Show this help.
EOF
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$(pwd)" "$1" ;;
  esac
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required."
}

resolve_command_path() {
  local value="$1"
  if [[ -f "$value" ]]; then
    absolute_path "$value"
    return 0
  fi
  if command -v "$value" >/dev/null 2>&1; then
    command -v "$value"
    return 0
  fi
  return 1
}

latest_release_tag() {
  local repo="$1"
  local tag=''
  tag="$(curl -fsSL -A cliproxy-cloud-gateway "https://github.com/$repo/releases.atom" 2>/dev/null | sed -nE 's#.*<link rel="alternate" type="text/html" href="https://github.com/[^/]+/[^/]+/releases/tag/([^"]+)".*#\1#p' | head -n 1 || true)"
  if [[ -z "$tag" ]]; then
    tag="$(curl -fsSL -A cliproxy-cloud-gateway -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest" 2>/dev/null | sed -nE 's#.*/releases/tag/([^/]+)$#\1#p' || true)"
  fi
  [[ -n "$tag" ]] || fail "could not resolve latest release tag for $repo"
  printf '%s\n' "$tag"
}

latest_release_asset() {
  local repo="$1"
  local asset_regex="$2"
  shift 2
  local candidates=("$@")
  local tag name
  tag="$(latest_release_tag "$repo")"

  name="$(curl -fsSL -A cliproxy-cloud-gateway "https://github.com/$repo/releases/expanded_assets/$tag" 2>/dev/null |
    grep -Eo "/$repo/releases/download/[^\"]+" |
    sed -nE 's#.*/download/[^/]+/(.+)$#\1#p' |
    grep -Ei "$asset_regex" |
    head -n 1 || true)"

  if [[ -z "$name" ]]; then
    for candidate in "${candidates[@]}"; do
      if curl -fsSI -A cliproxy-cloud-gateway "https://github.com/$repo/releases/download/$tag/$candidate" >/dev/null 2>&1; then
        name="$candidate"
        break
      fi
    done
  fi

  [[ -n "$name" ]] || fail "no matching asset found for $repo latest release"
  printf '%s\t%s\t%s\n' "$tag" "$name" "https://github.com/$repo/releases/download/$tag/$name"
}

install_release_asset_if_missing() {
  local repo="$1"
  local asset_regex="$2"
  local target_path="$3"
  local target_name="$4"
  shift 4
  local candidates=("$@")

  if [[ -f "$target_path" ]]; then
    printf 'Dependency exists, skip download: %s\n' "$target_path"
    return
  fi

  need_command curl
  local target_dir temp_dir asset tag name url download_path extract_dir binary
  target_dir="$(dirname "$target_path")"
  mkdir -p "$target_dir"

  IFS=$'\t' read -r tag name url < <(latest_release_asset "$repo" "$asset_regex" "${candidates[@]}")
  printf 'Downloading %s %s: %s\n' "$repo" "$tag" "$name"

  temp_dir="$target_dir/download-$$-$RANDOM"
  mkdir -p "$temp_dir"
  trap 'rm -rf "$temp_dir"' RETURN
  download_path="$temp_dir/$name"
  curl -fL -A cliproxy-cloud-gateway "$url" -o "$download_path"

  case "$name" in
    *.zip)
      need_command unzip
      extract_dir="$temp_dir/extract"
      mkdir -p "$extract_dir"
      unzip -q "$download_path" -d "$extract_dir"
      binary="$(find "$extract_dir" -type f -name "$target_name" | head -n 1)"
      ;;
    *.tar.gz|*.tgz)
      need_command tar
      extract_dir="$temp_dir/extract"
      mkdir -p "$extract_dir"
      tar -xzf "$download_path" -C "$extract_dir"
      binary="$(find "$extract_dir" -type f -name "$target_name" | head -n 1)"
      ;;
    *)
      binary="$download_path"
      ;;
  esac

  [[ -n "$binary" && -f "$binary" ]] || fail "downloaded asset does not contain $target_name"
  cp "$binary" "$target_path"
  chmod 700 "$target_path"
  rm -rf "$temp_dir"
  trap - RETURN
  printf 'Installed dependency: %s\n' "$target_path"
}

ensure_cliproxy_binary() {
  install_release_asset_if_missing \
    'router-for-me/CLIProxyAPI' \
    '(linux).*(amd64|x64|x86_64).*\.(zip|tar\.gz|tgz)$|cli-proxy-api.*(linux).*(amd64|x64|x86_64)$|CLIProxyAPI.*(linux).*(amd64|x64|x86_64)$' \
    "$1" \
    'cli-proxy-api' \
    'cli-proxy-api-linux-amd64.zip' \
    'CLIProxyAPI-linux-amd64.zip' \
    'CLIProxyAPI_linux_amd64.zip' \
    'cli-proxy-api-linux-amd64.tar.gz' \
    'CLIProxyAPI-linux-amd64.tar.gz'
}

ensure_caddy_binary() {
  local path_or_command="$1"
  local deployment_dir="$2"
  local resolved=''
  if resolved="$(resolve_command_path "$path_or_command" 2>/dev/null)"; then
    printf 'Dependency exists, skip download: %s\n' "$resolved" >&2
    printf '%s\n' "$resolved"
    return
  fi

  local target_path="$path_or_command"
  if [[ "$path_or_command" == 'caddy' ]]; then
    target_path="$deployment_dir/caddy/caddy"
  fi
  target_path="$(absolute_path "$target_path")"

  install_release_asset_if_missing \
    'caddyserver/caddy' \
    'linux.*amd64.*\.(tar\.gz|tgz|zip)$' \
    "$target_path" \
    'caddy' \
    'caddy_linux_amd64.tar.gz' \
    'caddy_linux_amd64.zip' >&2
  printf '%s\n' "$target_path"
}

get_lan_host() {
  if [[ -n "$SERVER_HOST" ]]; then
    printf '%s\n' "$SERVER_HOST"
    return
  fi
  local ip=''
  if command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -Ev '^(127\.|169\.254\.|$)' | head -n 1 || true)"
  fi
  printf '%s\n' "${ip:-127.0.0.1}"
}

write_lan_caddyfile() {
  local path="$1"
  local host="$2"
  cat > "$path" <<EOF
http://$host:$LAN_PORT {
    encode zstd gzip

    reverse_proxy 127.0.0.1:$PORT {
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
    }
}
EOF
}

existing_api_keys() {
  local config_path="$1"
  [[ -f "$config_path" ]] || return
  awk '
    /^api-keys:[[:space:]]*$/ { in_keys=1; next }
    in_keys && /^[^[:space:]]/ { in_keys=0 }
    in_keys && /^[[:space:]]*-[[:space:]]*'"'"'/ {
      line=$0
      sub(/^[[:space:]]*-[[:space:]]*'"'"'/, "", line)
      sub(/'"'"'[[:space:]]*$/, "", line)
      gsub(/'"'"''"'"'/, "'"'"'", line)
      print line
    }
  ' "$config_path"
}

auth_summary() {
  local auth_dir="$1"
  local py=''
  if command -v python3 >/dev/null 2>&1; then py='python3'; elif command -v python >/dev/null 2>&1; then py='python'; fi
  if [[ -z "$py" ]]; then
    printf 'Python is unavailable; auth summary skipped.\n'
    return
  fi
  "$py" - "$auth_dir" <<'PY'
import json
import re
import sys
from pathlib import Path

auth_dir = Path(sys.argv[1])
items = []
if auth_dir.is_dir():
    for path in auth_dir.glob("*.json"):
        item = {
            "File": path.name,
            "Type": "",
            "Disabled": "",
            "Websockets": "",
            "HasAccessToken": False,
            "HasRefreshToken": False,
            "Status": "",
        }
        if re.search(r"settings|test|temp|^codextoclaude-", path.name):
            item["Status"] = "ignored-by-generator-name"
            items.append(item)
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            item["Type"] = str(data.get("type", ""))
            item["Disabled"] = str(data.get("disabled", ""))
            item["Websockets"] = str(data.get("websockets", "missing"))
            item["HasAccessToken"] = "access_token" in data
            item["HasRefreshToken"] = "refresh_token" in data
            item["Status"] = "enabled-codex" if data.get("type") == "codex" and data.get("disabled") is not True else "not-enabled-codex"
        except Exception:
            item["Status"] = "invalid-json"
        items.append(item)

enabled = sum(1 for item in items if item["Status"] == "enabled-codex")
print(f"Enabled Codex auth JSON file(s): {enabled}")
if not items:
    print("No root-level *.json files found in auth directory.")
else:
    print("File\tType\tDisabled\tWebsockets\tHasAccessToken\tHasRefreshToken\tStatus")
    for item in items:
        print("\t".join(str(item[key]) for key in ["File", "Type", "Disabled", "Websockets", "HasAccessToken", "HasRefreshToken", "Status"]))
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir|--deployment-dir) DEPLOYMENT_DIR="$2"; shift 2 ;;
    --binary-path) BINARY_PATH="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --lan-port) LAN_PORT="$2"; shift 2 ;;
    --server-host) SERVER_HOST="$2"; shift 2 ;;
    --upstream-proxy-mode) UPSTREAM_PROXY_MODE="$2"; shift 2 ;;
    --upstream-proxy-url) UPSTREAM_PROXY_URL="$2"; shift 2 ;;
    --caddy-path) CADDY_PATH="$2"; shift 2 ;;
    --no-regenerate) NO_REGENERATE=1; shift ;;
    --skip-start) SKIP_START=1; shift ;;
    --skip-caddy) SKIP_CADDY=1; shift ;;
    --skip-download) SKIP_DOWNLOAD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ "$PORT" =~ ^[0-9]+$ ]] || fail 'port must be numeric.'
[[ "$LAN_PORT" =~ ^[0-9]+$ ]] || fail 'lan port must be numeric.'

if [[ "${BASH_SOURCE[0]:-}" == */* ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  SCRIPT_DIR="$(pwd)"
  PROJECT_ROOT="$(pwd)"
fi
GENERATOR_PATH="$SCRIPT_DIR/new-cloud-gateway.sh"
[[ -f "$GENERATOR_PATH" ]] || fail "generator not found: $GENERATOR_PATH"

DEPLOYMENT_DIR="$(absolute_path "$DEPLOYMENT_DIR")"
CONFIG_PATH="$DEPLOYMENT_DIR/config.yaml"
AUTH_DIR="$DEPLOYMENT_DIR/auth"
LAN_CADDY_PATH="$DEPLOYMENT_DIR/Caddyfile.lan"
if [[ -z "$BINARY_PATH" ]]; then
  BINARY_PATH="$DEPLOYMENT_DIR/cli-proxy-api/cli-proxy-api"
fi
BINARY_PATH="$(absolute_path "$BINARY_PATH")"
mkdir -p "$DEPLOYMENT_DIR" "$AUTH_DIR"

if [[ "$NO_REGENERATE" -eq 0 ]]; then
  gen_args=(--domain "$DOMAIN" --output-dir "$DEPLOYMENT_DIR" --port "$PORT" --upstream-proxy-mode "$UPSTREAM_PROXY_MODE")
  if [[ -n "$UPSTREAM_PROXY_URL" ]]; then gen_args+=(--upstream-proxy-url "$UPSTREAM_PROXY_URL"); fi
  mapfile -t keys < <(existing_api_keys "$CONFIG_PATH" || true)
  if [[ "${#keys[@]}" -gt 0 ]]; then
    printf 'Reusing existing API key(s): %s\n' "${#keys[@]}"
    for key in "${keys[@]}"; do gen_args+=(--api-key "$key"); done
  else
    printf 'No existing API key found; generator will create a new key.\n'
  fi
  bash "$GENERATOR_PATH" "${gen_args[@]}"
fi

LAN_HOST="$(get_lan_host)"
write_lan_caddyfile "$LAN_CADDY_PATH" "$LAN_HOST"

printf '\nDeployment directory: %s\n' "$DEPLOYMENT_DIR"
printf 'CLIProxyAPI config: %s\n' "$CONFIG_PATH"
printf 'Auth directory: %s\n' "$AUTH_DIR"
printf 'LAN Caddyfile: %s\n' "$LAN_CADDY_PATH"
printf 'LAN base URL: http://%s:%s\n' "$LAN_HOST" "$LAN_PORT"
auth_summary "$AUTH_DIR"

if [[ "$SKIP_START" -eq 1 ]]; then
  printf 'skip-start is set; services were not started.\n'
  exit 0
fi

if [[ ! -f "$BINARY_PATH" ]]; then
  if [[ "$SKIP_DOWNLOAD" -eq 1 ]]; then
    fail "CLIProxyAPI binary not found: $BINARY_PATH"
  fi
  ensure_cliproxy_binary "$BINARY_PATH"
fi

"$BINARY_PATH" --config "$CONFIG_PATH" > "$DEPLOYMENT_DIR/cli-proxy-api.stdout.log" 2> "$DEPLOYMENT_DIR/cli-proxy-api.stderr.log" &
printf 'Started CLIProxyAPI: pid=%s\n' "$!"

if [[ "$SKIP_CADDY" -eq 0 ]]; then
  CADDY_RESOLVED=''
  if CADDY_RESOLVED="$(resolve_command_path "$CADDY_PATH" 2>/dev/null)"; then
    :
  elif [[ "$SKIP_DOWNLOAD" -eq 0 ]]; then
    CADDY_RESOLVED="$(ensure_caddy_binary "$CADDY_PATH" "$DEPLOYMENT_DIR")"
  fi

  if [[ -z "$CADDY_RESOLVED" ]]; then
    printf 'Warning: Caddy not found: %s\n' "$CADDY_PATH" >&2
    printf 'Run manually after installing Caddy: caddy run --config "%s"\n' "$LAN_CADDY_PATH" >&2
  else
    "$CADDY_RESOLVED" validate --config "$LAN_CADDY_PATH"
    "$CADDY_RESOLVED" run --config "$LAN_CADDY_PATH" > "$DEPLOYMENT_DIR/caddy.stdout.log" 2> "$DEPLOYMENT_DIR/caddy.stderr.log" &
    printf 'Started Caddy: pid=%s\n' "$!"
  fi
fi

printf '\nOn your Mac, use:\n'
printf '  export ANTHROPIC_BASE_URL="http://%s:%s"\n' "$LAN_HOST" "$LAN_PORT"
printf '  export ANTHROPIC_AUTH_TOKEN="<copy from %s/client.env>"\n' "$DEPLOYMENT_DIR"
