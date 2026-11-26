FROM debian:bookworm-slim

ARG CPA_VERSION=8.1.7

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /opt/cpa \
 && curl -fsSL "https://github.com/router-for-me/CLIProxyAPI/releases/download/v${CPA_VERSION}/CLIProxyAPI_${CPA_VERSION}_linux_amd64.tar.gz" \
  | tar -xz -C /opt/cpa cli-proxy-api \
 && chmod 755 /opt/cpa/cli-proxy-api \
 && useradd -r -u 10001 -s /usr/sbin/nologin cpa \
 && chown -R cpa:cpa /opt/cpa

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER cpa
EXPOSE 8317
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
