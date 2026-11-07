// Copied into pi-kit/cdp-relay.mjs (each kit's build context is its own dir).
// Keep the two in sync.
// CDP relay: makes the Mac's Chrome (DevTools on host 127.0.0.1:9222) look
// local to agent-browser at sandbox 127.0.0.1:9222.
//
// The sandbox reaches the host only through the egress proxy, and that proxy
// refuses CONNECT tunnels but forwards absolute-URI HTTP requests, WebSocket
// upgrades included. So each connection's request line is rewritten from
// `GET /path` to `GET http://host.docker.internal:9222/path` and sent to the
// proxy; after that, bytes are piped untouched (CDP frames after an upgrade).
// Non-upgrade requests get `Connection: close`, so a kept-alive client never
// sends a second request that would skip the rewrite.
import net from "node:net";

const PORT = 9222;
const TARGET = `http://host.docker.internal:${PORT}`;
const proxy = new URL(process.env.HTTP_PROXY ?? "http://gateway.docker.internal:3128");

net
  .createServer((client) => {
    let head = Buffer.alloc(0);

    const onData = (chunk) => {
      head = Buffer.concat([head, chunk]);
      const end = head.indexOf("\r\n\r\n");
      if (end === -1) return;
      client.off("data", onData);

      const [requestLine, ...headers] = head.subarray(0, end).toString("latin1").split("\r\n");
      const [method, path, version] = requestLine.split(" ");
      const upgrade = headers.some((h) => /^upgrade:\s*websocket/i.test(h));
      const kept = upgrade ? headers : headers.filter((h) => !/^(proxy-)?connection:/i.test(h));
      if (!upgrade) kept.push("Connection: close");

      const upstream = net.connect(Number(proxy.port || 80), proxy.hostname, () => {
        upstream.write([`${method} ${TARGET}${path} ${version}`, ...kept, "", ""].join("\r\n"));
        upstream.write(head.subarray(end + 4));
        client.pipe(upstream).pipe(client);
      });
      upstream.on("error", () => client.destroy());
      client.on("error", () => upstream.destroy());
    };

    client.on("data", onData);
  })
  .listen(PORT, "127.0.0.1");
