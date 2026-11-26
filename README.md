# CLIProxyAPI v8.1.7: LFM3-Omni-2B free pool

Standalone Docker bundle. It renders `/tmp/config.yaml` at startup from env vars and pools every `$0` LFM3-Omni-2B backend behind one OpenAI-compatible endpoint. No keys are stored in the repo or the image.

## Env vars

| Var | Required | Purpose |
|---|---|---|
| `CPA_CLIENT_KEY` | yes | Min 24 chars (startup fails otherwise). Key clients send as `Authorization: Bearer ...` (`access.api-keys`) |
| `HF_SPACE_API_KEY` | no | Enables `hf-zerogpu-gguf` and `hf-zerogpu-bf16` |
| `LIQUID_API_KEY` | no | Used only when `ALLOW_BILLABLE_PROVIDERS=1` |
| `CF_GATEWAY_API_KEY` | no | Enables `cf-free-gateway` (sends `User-Agent: Ava-LFM3-Client/1.0`) |
| `ROUTING_STRATEGY` | no | `fill-first` (default), `round-robin`, `weighted-round-robin` |
| `ALLOW_BILLABLE_PROVIDERS` | no | `0` (default). `1` enables `liquid-ai-managed` (potentially billable) and pools it as fallback |
| `PORT` | no | Listen port (validated 1..65535), default `8317` (platforms like Render inject it) |

At least one enabled upstream is required. A provider is included only if its key is non-empty. At least one provider must be enabled or the container exits.

## Models

- `lfm3-omni-2b`: pooled across `hf-zerogpu-gguf` → `hf-zerogpu-bf16` (→ `liquid-ai-managed` only if `ALLOW_BILLABLE_PROVIDERS=1`) (fill-first, with failover); `cf-free-gateway` is direct-only via `lfm3-omni-cf`
- `lfm3-omni-hf-gguf`, `lfm3-omni-hf-gpu`, `lfm3-omni-liquid`, `lfm3-omni-cf`: direct, one backend each

Retry: `routing.retry.request-retry: 2`, `max-retry-interval: 15`.

## Security

- Management API is off: `management.secret-key` is empty (routes return 404) and the control panel is disabled.
- `/v1/*` returns 401 without a valid `CPA_CLIENT_KEY`. `GET /` is unauthenticated and returns 200, so it is used as the health check.
- Startup fails closed: `PORT` must be 1..65535, `ROUTING_STRATEGY` must be `fill-first|round-robin|weighted-round-robin`, secrets may not contain control characters, and the rendered config must keep `management` disabled. All values are written as escaped YAML single-quoted scalars.
- Config and auth dir are created with `umask 077` (0600 / 0700), written atomically, symlinks refused.
- Image: base pinned by digest, CLIProxyAPI tarball verified by SHA-256 at build, multi-stage (no curl in final image), root-owned 0555 binaries, runs as UID 10001. Render auto-deploy is off.
- Free-only by default: the potentially billable Liquid provider is never used unless `ALLOW_BILLABLE_PROVIDERS=1`. Upstream spend limits must be set in provider dashboards; Render's free tier is not a spending control.
- Secret rotation: rotate `CPA_CLIENT_KEY` (Render env → regenerate) and upstream keys at the provider, update in the dashboard, then redeploy manually. Rotate immediately on any suspected exposure.
- Acceptance test after deploy (the binary's schema is not verifiable offline): `/v1/models` without a key → 401; with key → 200; `/v0/management/*` → 404 externally.
- The local KV store is disabled and the auth dir is `/tmp/cpa-auth`; the container is stateless.

## Run locally

```sh
docker build -t cpa-lfm3 .
docker run --rm -p 8317:8317 \
  -e CPA_CLIENT_KEY=... -e HF_SPACE_API_KEY=... -e LIQUID_API_KEY=... cpa-lfm3
```

## Deploy on Render

Push this folder to a repo and create a Blueprint from `render.yaml` (free web service, Docker, health check `/`). Set `HF_SPACE_API_KEY`, `LIQUID_API_KEY` and optionally `CF_GATEWAY_API_KEY` in the dashboard. `CPA_CLIENT_KEY` is generated; read it from the service's Environment tab. Koyeb, Leapcell and HF Docker Spaces work the same way: set the same env vars and the platform's `PORT` is honored (on HF Spaces set `app_port` or `PORT=7860`).

Free tiers sleep when idle, so the first request after idle is slow.

## Ava integration

```
base URL: https://<your-service>.onrender.com/v1
api key:  <CPA_CLIENT_KEY>
model:    lfm3-omni-2b
```

```sh
curl https://<your-service>.onrender.com/v1/chat/completions \
  -H "Authorization: Bearer $CPA_CLIENT_KEY" -H "Content-Type: application/json" \
  -d '{"model":"lfm3-omni-2b","messages":[{"role":"user","content":"hi"}]}'
```

## Notes

- The image targets `linux/amd64`. The upstream binary is about 80 MB, so the image is well over 40 MB.
- The Docker image was not built here (smoke test used the macOS binary with the same entrypoint).
