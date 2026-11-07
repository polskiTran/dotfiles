# syntax=docker/dockerfile:1
# Overlay for claude-kit: Node, pnpm and agent-browser (the claude base ships
# none of them) and the home dotfiles under files/home. Ends at scratch so only
# /out lands on the base. No browser ships here: agent-browser attaches to the
# Mac's Chrome through cdp-relay.mjs (started by claude-kit.yaml).
FROM debian:trixie-slim AS build
ARG TARGETARCH
ARG NODE_VERSION=24.11.0
# Installed at its real path (/usr/local), then copied to /out: agent-browser's
# postinstall writes an absolute bin symlink, which must not carry a /out prefix.
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates xz-utils

RUN case "$TARGETARCH" in \
      amd64) arch=x64 ;; \
      arm64) arch=arm64 ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac \
 && mkdir -p /tmp/node /out/usr/local \
 && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${arch}.tar.xz" \
      | tar -xJ --strip-components=1 -C /tmp/node \
 && cp -a /tmp/node/bin /tmp/node/lib /usr/local/ \
 && npm install -g pnpm agent-browser \
 && cp -a /usr/local/bin /usr/local/lib /out/usr/local/

# /home stays root-owned, /home/agent uid 1000 (spec §10 overlay ownership).
COPY cdp-relay.mjs /out/usr/local/lib/cdp-relay.mjs
COPY files/home/ /out/home/agent/
RUN chown -R 1000:1000 /out/home/agent \
 && chmod 0755 /out/home/agent/.claude/statusline.sh

FROM scratch
COPY --from=build /out /
# Host Chrome's DevTools port, as served on the sandbox loopback by cdp-relay.
ENV AGENT_BROWSER_CDP=9222
