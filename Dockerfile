FROM alpine:3.21

ARG CPA_VERSION=8.1.7

RUN apk add --no-cache ca-certificates curl bash \
 && mkdir -p /opt/cpa \
 && curl -fsSL "https://github.com/router-for-me/CLIProxyAPI/releases/download/v${CPA_VERSION}/CLIProxyAPI_${CPA_VERSION}_linux_amd64.tar.gz" \
  | tar -xz -C /opt/cpa cli-proxy-api \
 && chmod 755 /opt/cpa/cli-proxy-api \
 && adduser -D -u 10001 cpa

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER cpa
EXPOSE 8317
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
