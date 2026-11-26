#!/bin/bash
# Renders the CLIProxyAPI v8 config from env vars at startup, then execs the server.
set -euo pipefail

PORT="${PORT:-8317}"
ROUTING_STRATEGY="${ROUTING_STRATEGY:-fill-first}"
CONFIG_OUT="${CONFIG_OUT:-/tmp/config.yaml}"
CPA_BIN="${CPA_BIN:-/opt/cpa/cli-proxy-api}"
AUTH_DIR="${AUTH_DIR:-/tmp/cpa-auth}"
mkdir -p "$AUTH_DIR"

if [ -z "${CPA_CLIENT_KEY:-}" ]; then
  echo "CPA_CLIENT_KEY is required (client key for access.api-keys)" >&2
  exit 1
fi

provider() { # name base-url upstream-model direct-alias key extra-yaml pooled(1|0)
  local pool=""
  if [ "${7:-1}" = "1" ]; then
    pool=$'        - name: "'"$3"$'"\n          alias: "lfm3-omni-2b"\n'
  fi
  cat <<EOF
    - name: "$1"
      base-url: "$2"
$6      keys:
        - api-key: "$5"
      models:
${pool}        - name: "$3"
          alias: "$4"
EOF
}

{
  cat <<EOF
config-version: 8
server:
  host: ""
  port: ${PORT}
  kv-store:
    disabled: true
oauth:
  auth-dir: "${AUTH_DIR}"
management:
  allow-remote: false
  secret-key: ""
  disable-control-panel: true
access:
  api-keys:
    - "${CPA_CLIENT_KEY}"
routing:
  strategy: "${ROUTING_STRATEGY}"
  retry:
    request-retry: 3
    max-retry-interval: 15
api-keys:
  openai-compatibility:
EOF
  n=0
  if [ -n "${HF_SPACE_API_KEY:-}" ]; then
    provider hf-zerogpu-gguf "https://vitorcalvi-lfm3-omni-2b-gguf.hf.space/v1" "LFM3-Omni-2B-Q4_K_M" lfm3-omni-hf-gguf "$HF_SPACE_API_KEY" ""
    provider hf-zerogpu-bf16 "https://vitorcalvi-lfm3-omni-2b-gpu.hf.space/v1" "LiquidAI/LFM3-Omni-2B" lfm3-omni-hf-gpu "$HF_SPACE_API_KEY" ""
    n=$((n+2))
  fi
  if [ -n "${LIQUID_API_KEY:-}" ]; then
    provider liquid-ai-managed "https://api.liquid.ai/openai/v1" "lfm3-omni-2b" lfm3-omni-liquid "$LIQUID_API_KEY" ""
    n=$((n+1))
  fi
  if [ -n "${CF_GATEWAY_API_KEY:-}" ]; then
    provider cf-free-gateway "https://lfm3-omni-free-gateway.vitorcalvi.workers.dev/v1" "LiquidAI/LFM3-Omni-2B" lfm3-omni-cf "$CF_GATEWAY_API_KEY" $'      headers:\n        User-Agent: "Ava-LFM3-Client/1.0"\n' 0
    n=$((n+1))
  fi
  if [ "$n" -eq 0 ]; then
    echo "No upstream keys set (HF_SPACE_API_KEY / LIQUID_API_KEY / CF_GATEWAY_API_KEY)" >&2
    exit 1
  fi
} > "$CONFIG_OUT"
chmod 600 "$CONFIG_OUT"

echo "cpa: rendered $CONFIG_OUT with $n upstream provider(s) on port $PORT, strategy $ROUTING_STRATEGY" >&2
cd "$(dirname "$CONFIG_OUT")"
exec "$CPA_BIN" -config "$CONFIG_OUT"
