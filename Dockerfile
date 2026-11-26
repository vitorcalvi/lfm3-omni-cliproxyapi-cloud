FROM debian:bookworm-slim@sha256:e67eeead736ff7bbe258ef088bff683635c561b1fcfefad0806c1df4ab49ce0e AS fetch

ARG CPA_VERSION=8.1.7
ARG CPA_SHA256=c2ffd3845c15a100a6ac5e2a2c192aca81d617033652bf2499e40783029de149

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/cpa.tar.gz \
    "https://github.com/router-for-me/CLIProxyAPI/releases/download/v${CPA_VERSION}/CLIProxyAPI_${CPA_VERSION}_linux_amd64.tar.gz" \
 && echo "${CPA_SHA256}  /tmp/cpa.tar.gz" | sha256sum -c - \
 && mkdir -p /out \
 && tar -xzf /tmp/cpa.tar.gz -C /out cli-proxy-api

FROM debian:bookworm-slim@sha256:e67eeead736ff7bbe258ef088bff683635c561b1fcfefad0806c1df4ab49ce0e

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -r -u 10001 -s /usr/sbin/nologin cpa

# Root-owned, read-only executables; only /tmp is writable at runtime.
COPY --from=fetch --chown=root:root --chmod=0555 /out/cli-proxy-api /opt/cpa/cli-proxy-api
COPY --chown=root:root --chmod=0555 entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0555 /opt/cpa

USER cpa
EXPOSE 8317
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
