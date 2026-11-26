#!/bin/bash
# Renders the CLIProxyAPI v8 config from env vars at startup, then execs the server.
set -euo pipefail
umask 077

die() { echo "cpa: $*" >&2; exit 1; }

# Reject control characters (incl. newlines) so no value can break out of its YAML scalar.
safe_value() { # label value
  [[ "$2" =~ [[:cntrl:]] ]] && die "$1 contains control characters"
  return 0
}

# YAML single-quoted scalar: only ' needs escaping (doubled); no escapes are interpreted.
yq() { # value
  local q="'" v="$1"
  v="${v//$q/$q$q}"
  printf "'%s'" "$v"
}

PORT="${PORT:-8317}"
ROUTING_STRATEGY="${ROUTING_STRATEGY:-fill-first}"
CONFIG_OUT="${CONFIG_OUT:-/tmp/config.yaml}"
CPA_BIN="${CPA_BIN:-/opt/cpa/cli-proxy-api}"
AUTH_DIR="${AUTH_DIR:-/tmp/cpa-auth}"
ALLOW_BILLABLE_PROVIDERS="${ALLOW_BILLABLE_PROVIDERS:-0}"

[[ "$PORT" =~ ^[0-9]{1,5}$ ]] && [ "$((10#$PORT))" -ge 1 ] && [ "$((10#$PORT))" -le 65535 ] \
  || die "PORT must be an integer in 1..65535"
PORT=$((10#$PORT))
case "$ROUTING_STRATEGY" in
  fill-first|round-robin|weighted-round-robin) ;;
  *) die "ROUTING_STRATEGY must be fill-first|round-robin|weighted-round-robin" ;;
esac
case "$ALLOW_BILLABLE_PROVIDERS" in 0|1) ;; *) die "ALLOW_BILLABLE_PROVIDERS must be 0 or 1" ;; esac

for p in "$CONFIG_OUT" "$AUTH_DIR"; do
  [[ "$p" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "unsafe path: $p"
  [ -L "$p" ] && die "refusing symlink: $p"
done

CPA_CLIENT_KEY="${CPA_CLIENT_KEY:-}"
[ -n "$CPA_CLIENT_KEY" ] || die "CPA_CLIENT_KEY is required"
[ "${#CPA_CLIENT_KEY}" -ge 24 ] || die "CPA_CLIENT_KEY must be at least 24 characters"
safe_value CPA_CLIENT_KEY "$CPA_CLIENT_KEY"
for k in HF_SPACE_API_KEY LIQUID_API_KEY CF_GATEWAY_API_KEY; do
  safe_value "$k" "${!k:-}"
done

mkdir -p -m 700 "$AUTH_DIR"
chmod 700 "$AUTH_DIR"
[ -O "$AUTH_DIR" ] || die "AUTH_DIR not owned by current user"

provider() { # name base-url upstream-model direct-alias key pooled(1|0) [user-agent]
  echo "    - name: $(yq "$1")"
  echo "      base-url: $(yq "$2")"
  if [ -n "${7:-}" ]; then
    echo "      headers:"
    echo "        User-Agent: $(yq "$7")"
  fi
  echo "      keys:"
  echo "        - api-key: $(yq "$5")"
  echo "      models:"
  if [ "$6" = "1" ]; then
    echo "        - name: $(yq "$3")"
    echo "          alias: 'lfm3-omni-2b'"
  fi
  echo "        - name: $(yq "$3")"
  echo "          alias: $(yq "$4")"
}

TMP_CFG="$(mktemp "${CONFIG_OUT}.XXXXXX")"
trap 'rm -f "$TMP_CFG"' EXIT
n=0
{
  cat <<EOF
config-version: 8
server:
  host: ''
  port: $PORT
  kv-store:
    disabled: true
oauth:
  auth-dir: $(yq "$AUTH_DIR")
management:
  allow-remote: false
  secret-key: ''
  disable-control-panel: true
access:
  api-keys:
    - $(yq "$CPA_CLIENT_KEY")
routing:
  strategy: $(yq "$ROUTING_STRATEGY")
  retry:
    request-retry: 2
    max-retry-interval: 15
api-keys:
  openai-compatibility:
EOF
  if [ -n "${HF_SPACE_API_KEY:-}" ]; then
    provider hf-zerogpu-gguf "https://vitorcalvi-lfm3-omni-2b-gguf.hf.space/v1" "LFM3-Omni-2B-Q4_K_M" lfm3-omni-hf-gguf "$HF_SPACE_API_KEY" 1
    provider hf-zerogpu-bf16 "https://vitorcalvi-lfm3-omni-2b-gpu.hf.space/v1" "LiquidAI/LFM3-Omni-2B" lfm3-omni-hf-gpu "$HF_SPACE_API_KEY" 1
    n=$((n+2))
  fi
  # Potentially billable: never pooled/fallback unless explicitly authorized.
  if [ -n "${LIQUID_API_KEY:-}" ] && [ "$ALLOW_BILLABLE_PROVIDERS" = "1" ]; then
    provider liquid-ai-managed "https://api.liquid.ai/openai/v1" "lfm3-omni-2b" lfm3-omni-liquid "$LIQUID_API_KEY" 1
    n=$((n+1))
  fi
  if [ -n "${CF_GATEWAY_API_KEY:-}" ]; then
    provider cf-free-gateway "https://lfm3-omni-free-gateway.vitorcalvi.workers.dev/v1" "LiquidAI/LFM3-Omni-2B" lfm3-omni-cf "$CF_GATEWAY_API_KEY" 0 "Ava-LFM3-Client/1.0"
    n=$((n+1))
  fi
} > "$TMP_CFG"
[ "$n" -gt 0 ] || die "no enabled upstream (HF_SPACE_API_KEY / CF_GATEWAY_API_KEY, or LIQUID_API_KEY with ALLOW_BILLABLE_PROVIDERS=1)"

# Fail closed if management is not exactly as intended in the rendered file.
for line in "  allow-remote: false" "  secret-key: ''" "  disable-control-panel: true"; do
  grep -qxF -- "$line" "$TMP_CFG" || die "rendered config missing required management setting"
done
[ "$(grep -c '^management:' "$TMP_CFG")" -eq 1 ] || die "rendered config has unexpected management sections"

chmod 600 "$TMP_CFG"
mv -f "$TMP_CFG" "$CONFIG_OUT"
trap - EXIT

echo "cpa: rendered $CONFIG_OUT with $n upstream provider(s) on port $PORT, strategy $ROUTING_STRATEGY" >&2
cd "$(dirname "$CONFIG_OUT")"
exec "$CPA_BIN" -config "$CONFIG_OUT"
