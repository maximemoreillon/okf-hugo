# syntax=docker/dockerfile:1
ARG HUGO_VERSION=0.162.1
ARG CADDY_VERSION=2

FROM caddy:${CADDY_VERSION}-alpine AS caddy

FROM debian:bookworm-slim
ARG HUGO_VERSION
ARG TARGETARCH
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates wget; \
    wget -qO /tmp/hugo.tar.gz \
      "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-${TARGETARCH}.tar.gz"; \
    tar -xzf /tmp/hugo.tar.gz -C /usr/local/bin hugo; \
    rm /tmp/hugo.tar.gz; \
    apt-get purge -y --auto-remove wget; \
    rm -rf /var/lib/apt/lists/*; \
    hugo version

COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy

# Baked, read-only site skeleton. The entrypoint copies this into a writable
# work dir at startup, then drops the runtime OKF bundle in as content.
WORKDIR /app
COPY hugo.toml ./
COPY assets/ ./assets/
COPY layouts/ ./layouts/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# Pre-create the writable dirs the entrypoint uses, owned by the runtime user.
# (When these are emptyDir mounts in K8s they're world-writable anyway.)
RUN chmod +x /usr/local/bin/entrypoint.sh \
 && mkdir -p /work /bundle \
 && chown -R 65532:65532 /work /bundle

ENV TEMPLATE_DIR=/app \
    SRC_DIR=/work \
    BUNDLE_DIR=/bundle \
    PORT=8080 \
    XDG_CONFIG_HOME=/tmp \
    XDG_DATA_HOME=/tmp

USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
