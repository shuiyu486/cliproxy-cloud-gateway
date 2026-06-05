#!/usr/bin/env bash
set -euo pipefail

DOMAIN=''
INSTALL_DIR='/opt/cliproxy-gateway'
BINARY_PATH=''
CADDY_PATH='caddy'
CADDYFILE_PATH='/etc/caddy/Caddyfile'
SERVICE_USER=''
SERVICE_NAME='cliproxy'
PORT='8317'
UPSTREAM_PROXY_MODE='direct'
UPSTREAM_PROXY_URL=''
API_KEYS=()
SKIP_DOWNLOAD=0
SKIP_SYSTEMD=0
SKIP_CADDY_RELOAD=0
SKIP_DOCTOR=0

usage() {
  cat <<'EOF'
Usage:
  install-cloud-gateway.sh --domain api.example.com [options]

Options:
  --domain HOST              Public domain handled by Caddy. Required.
  --install-dir DIR          Deployment directory. Default: /opt/cliproxy-gateway
  --binary-path PATH         CLIProxyAPI binary path. Default: INSTALL_DIR/cli-proxy-api/cli-proxy-api
  --caddy-path PATH          Caddy binary/command. Default: caddy
  --caddyfile-path PATH      Installed Caddyfile path. Default: /etc/caddy/Caddyfile
  --service-user USER        systemd service user. Default: current user, or root under sudo.
  --service-name NAME        systemd service name. Default: cliproxy
  --port PORT                Private CLIProxyAPI port. Default: 8317
  --api-key KEY              Client API key. Can be repeated.
  --upstream-proxy-mode MODE direct, http, or socks5. Default: direct
  --upstream-proxy-url URL   Upstream proxy used by CLIProxyAPI to reach Codex.
  --skip-download            Do not download missing CLIProxyAPI/Caddy binaries.
  --skip-systemd             Do not install or restart the CLIProxyAPI systemd service.
  --skip-caddy-reload        Do not install/reload the Caddyfile.
  --skip-doctor              Do not run the generated deployment doctor.
  -h, --help                 Show this help.
EOF
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required."
}

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$(pwd)" "$1" ;;
  esac
}

run_privileged() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    need_command sudo
    sudo "$@"
  fi
}

write_privileged_file() {
  local path="$1"
  local content="$2"
  if [[ "$(id -u)" -eq 0 ]]; then
    printf '%s\n' "$content" > "$path"
  else
    need_command sudo
    printf '%s\n' "$content" | sudo tee "$path" >/dev/null
  fi
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
  local install_dir="$2"
  local resolved=''
  if resolved="$(resolve_command_path "$path_or_command" 2>/dev/null)"; then
    printf 'Dependency exists, skip download: %s\n' "$resolved" >&2
    printf '%s\n' "$resolved"
    return
  fi

  local target_path="$path_or_command"
  if [[ "$path_or_command" == 'caddy' ]]; then
    target_path="$install_dir/caddy/caddy"
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

render_service() {
  local template_path="$1"
  local service_user="$2"
  local install_dir="$3"
  local binary_path="$4"
  local config_path="$5"
  local content
  content="$(cat "$template_path")"
  content="${content//\{\{SERVICE_USER\}\}/$service_user}"
  content="${content//\{\{INSTALL_DIR\}\}/$install_dir}"
  content="${content//\{\{BINARY_PATH\}\}/$binary_path}"
  content="${content//\{\{CONFIG_PATH\}\}/$config_path}"
  printf '%s\n' "$content"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --install-dir|--output-dir) INSTALL_DIR="$2"; shift 2 ;;
    --binary-path) BINARY_PATH="$2"; shift 2 ;;
    --caddy-path) CADDY_PATH="$2"; shift 2 ;;
    --caddyfile-path) CADDYFILE_PATH="$2"; shift 2 ;;
    --service-user) SERVICE_USER="$2"; shift 2 ;;
    --service-name) SERVICE_NAME="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --api-key) API_KEYS+=("$2"); shift 2 ;;
    --upstream-proxy-mode) UPSTREAM_PROXY_MODE="$2"; shift 2 ;;
    --upstream-proxy-url) UPSTREAM_PROXY_URL="$2"; shift 2 ;;
    --skip-download) SKIP_DOWNLOAD=1; shift ;;
    --skip-systemd) SKIP_SYSTEMD=1; shift ;;
    --skip-caddy-reload) SKIP_CADDY_RELOAD=1; shift ;;
    --skip-doctor) SKIP_DOCTOR=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$DOMAIN" ]] || fail '--domain is required.'
[[ "$PORT" =~ ^[0-9]+$ ]] || fail 'port must be numeric.'

if [[ "${BASH_SOURCE[0]:-}" == */* ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  SCRIPT_DIR="$(pwd)"
  PROJECT_ROOT="$(pwd)"
fi

GENERATOR_PATH="$SCRIPT_DIR/new-cloud-gateway.sh"
DOCTOR_PATH="$SCRIPT_DIR/test-cloud-gateway-doctor.sh"
SERVICE_TEMPLATE_PATH="$PROJECT_ROOT/linux/cliproxy.service.template"
[[ -f "$GENERATOR_PATH" ]] || fail "generator not found: $GENERATOR_PATH"
[[ -f "$SERVICE_TEMPLATE_PATH" ]] || fail "service template not found: $SERVICE_TEMPLATE_PATH"

INSTALL_DIR="$(absolute_path "$INSTALL_DIR")"
if [[ -z "$BINARY_PATH" ]]; then
  BINARY_PATH="$INSTALL_DIR/cli-proxy-api/cli-proxy-api"
fi
BINARY_PATH="$(absolute_path "$BINARY_PATH")"
CONFIG_PATH="$INSTALL_DIR/config.yaml"
CADDY_SOURCE_PATH="$INSTALL_DIR/Caddyfile"

if [[ -z "$SERVICE_USER" ]]; then
  SERVICE_USER="${SUDO_USER:-$(id -un)}"
fi

mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/auth" "$INSTALL_DIR/logs"

gen_args=(--domain "$DOMAIN" --output-dir "$INSTALL_DIR" --port "$PORT" --upstream-proxy-mode "$UPSTREAM_PROXY_MODE")
if [[ -n "$UPSTREAM_PROXY_URL" ]]; then gen_args+=(--upstream-proxy-url "$UPSTREAM_PROXY_URL"); fi
for key in "${API_KEYS[@]}"; do gen_args+=(--api-key "$key"); done
bash "$GENERATOR_PATH" "${gen_args[@]}"

if [[ "$SKIP_DOWNLOAD" -eq 0 ]]; then
  ensure_cliproxy_binary "$BINARY_PATH"
  CADDY_RESOLVED="$(ensure_caddy_binary "$CADDY_PATH" "$INSTALL_DIR")"
else
  printf 'skip-download is set; dependencies were not downloaded.\n'
  CADDY_RESOLVED="$(resolve_command_path "$CADDY_PATH" 2>/dev/null || true)"
fi

if [[ "$SKIP_SYSTEMD" -eq 0 ]]; then
  [[ -f "$BINARY_PATH" ]] || fail "CLIProxyAPI binary not found for systemd install: $BINARY_PATH"
  SERVICE_CONTENT="$(render_service "$SERVICE_TEMPLATE_PATH" "$SERVICE_USER" "$INSTALL_DIR" "$BINARY_PATH" "$CONFIG_PATH")"
  SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME.service"
  write_privileged_file "$SERVICE_PATH" "$SERVICE_CONTENT"
  run_privileged systemctl daemon-reload
  run_privileged systemctl enable --now "$SERVICE_NAME"
  printf 'Installed and started systemd service: %s\n' "$SERVICE_NAME"
else
  printf 'skip-systemd is set; CLIProxyAPI service was not installed.\n'
fi

if [[ "$SKIP_CADDY_RELOAD" -eq 0 ]]; then
  [[ -n "${CADDY_RESOLVED:-}" ]] || fail "Caddy not found: $CADDY_PATH"
  run_privileged mkdir -p "$(dirname "$CADDYFILE_PATH")"
  run_privileged cp "$CADDY_SOURCE_PATH" "$CADDYFILE_PATH"
  "$CADDY_RESOLVED" validate --config "$CADDYFILE_PATH"
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files caddy.service >/dev/null 2>&1; then
    run_privileged systemctl reload caddy
    printf 'Installed and reloaded Caddyfile: %s\n' "$CADDYFILE_PATH"
  else
    printf 'Caddyfile installed: %s\n' "$CADDYFILE_PATH"
    printf 'Caddy systemd service was not detected; start Caddy with: %s run --config %s\n' "$CADDY_RESOLVED" "$CADDYFILE_PATH"
  fi
else
  printf 'skip-caddy-reload is set; Caddyfile was not installed or reloaded.\n'
fi

if [[ "$SKIP_DOCTOR" -eq 0 && -f "$DOCTOR_PATH" ]]; then
  bash "$DOCTOR_PATH" --deployment-dir "$INSTALL_DIR"
else
  printf 'doctor check skipped.\n'
fi

printf '\nCloud gateway deployment files are ready.\n'
printf 'Deployment directory: %s\n' "$INSTALL_DIR"
printf 'CLIProxyAPI config: %s\n' "$CONFIG_PATH"
printf 'Generated Caddyfile: %s\n' "$CADDY_SOURCE_PATH"
printf 'Auth directory: %s/auth\n' "$INSTALL_DIR"
printf 'Client base URL: https://%s\n' "$DOMAIN"
printf 'Client API key is written to client.env; it was not printed.\n'
printf 'Put enabled type=codex OAuth JSON files under %s/auth, or run CLIProxyAPI device login on the server.\n' "$INSTALL_DIR"
