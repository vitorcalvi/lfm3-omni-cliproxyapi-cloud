# CLIProxyAPI v8.1.7: LFM3-Omni-2B free pool

Standalone Docker bundle. It renders `/tmp/config.yaml` at startup from env vars and pools every `$0` LFM3-Omni-2B backend behind one OpenAI-compatible endpoint. No keys are stored in the repo or the image.

## Env vars

| Var | Required | Purpose |
|---|---|---|
| `CPA_CLIENT_KEY` | yes | Key clients send as `Authorization: Bearer ...` (`access.api-keys`) |
| `HF_SPACE_API_KEY` | no | Enables `hf-zerogpu-gguf` and `hf-zerogpu-bf16` |
| `LIQUID_API_KEY` | no | Enables `liquid-ai-managed` |
| `CF_GATEWAY_API_KEY` | no | Enables `cf-free-gateway` (sends `User-Agent: Ava-LFM3-Client/1.0`) |
| `ROUTING_STRATEGY` | no | `round-robin` (default), `weighted-round-robin`, `fill-first` |
| `PORT` | no | Listen port, default `8317` (platforms like Render inject it) |

At least one upstream key is required. A provider is included only if its key is non-empty. At least one provider must be enabled or the container exits.

## Models

- `lfm3-omni-2b`: pooled across all enabled providers, with failover
- `lfm3-omni-hf-gguf`, `lfm3-omni-hf-gpu`, `lfm3-omni-liquid`, `lfm3-omni-cf`: direct, one backend each

Retry: `routing.retry.request-retry: 3`, `max-retry-interval: 15`.

## Security

- Management API is off: `management.secret-key` is empty (routes return 404) and the control panel is disabled.
- `/v1/*` returns 401 without a valid `CPA_CLIENT_KEY`. `GET /` is unauthenticated and returns 200, so it is used as the health check.
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
