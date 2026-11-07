# syntax=docker/dockerfile:1
# Pi workload: the sbx shell base (DHI Debian, Docker engine, uv) plus Node,
# pi, pnpm and agent-browser, installed at build so sandbox creation is fast.
# No browser ships here: agent-browser attaches to the Mac's Chrome through
# cdp-relay.mjs (started by pi-kit.yaml).
FROM docker.io/sbx/shell:latest
ARG TARGETARCH
ARG NODE_VERSION=24.11.0
USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends xz-utils \
 && rm -rf /var/lib/apt/lists/*

RUN case "$TARGETARCH" in \
      amd64) arch=x64 ;; \
      arm64) arch=arm64 ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac \
 && mkdir -p /tmp/node \
 && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${arch}.tar.xz" \
      | tar -xJ --strip-components=1 -C /tmp/node \
 && cp -a /tmp/node/bin /tmp/node/lib /usr/local/ \
 && rm -rf /tmp/node

# Globals land in the base's NPM_CONFIG_PREFIX (/usr/local/share/npm-global),
# handed to the agent so pi can install its `packages` at runtime.
RUN npm install -g pnpm agent-browser \
 && npm install -g --ignore-scripts @earendil-works/pi-coding-agent \
 && chown -R 1000:1000 "$NPM_CONFIG_PREFIX"

COPY cdp-relay.mjs /usr/local/lib/cdp-relay.mjs
COPY --chown=1000:1000 files/home/ /home/agent/

USER 1000
ENV AGENT_BROWSER_CDP=9222
# The base entrypoint (`bash -c 'exec "$@"'`) stays, so BASH_ENV is sourced first.
CMD ["pi"]
