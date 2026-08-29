#!/usr/bin/env node
// Usage: node bridge.js <hermes-base-url>
// Bootstraps a session against a loopback Hermes gateway, then relays
// newline-delimited JSON between stdin/stdout and the gateway's WebSocket.
const base = (process.argv[2] ?? "http://127.0.0.1:9119").replace(/\/$/, "");
async function fetchSessionToken(base) {
    const response = await fetch(`${base}/`);
    if (!response.ok) {
        throw new Error(`GET / returned HTTP ${response.status}`);
    }
    const html = await response.text();
    const token = html.match(/__HERMES_SESSION_TOKEN__\s*=\s*"([^"]+)"/)?.[1];
    if (!token) {
        throw new Error("Hermes session token not found");
    }
    return token;
}
function toWebSocketUrl(base, token) {
    const wsBase = base.replace(/^http:/, "ws:").replace(/^https:/, "wss:");
    return `${wsBase}/api/ws?token=${encodeURIComponent(token)}`;
}
async function main() {
    const token = await fetchSessionToken(base);
    const ws = new WebSocket(toWebSocketUrl(base, token));
    let ready = false;
    let queue = [];
    ws.addEventListener("open", () => {
        process.stderr.write(`connected to ${base}`);
    });
    ws.addEventListener("message", (event) => {
        process.stdout.write(String(event.data) + "\n");
    });
    ws.addEventListener("error", (event) => {
        const err = event;
        process.stderr.write(`websocket error: ${err.message}\n`);
    });
    ws.addEventListener("close", () => {
        process.stderr.write("websocket closed\n");
        process.exit(0);
    });
    // Wait for the gateway.ready *notification*, not just the socket's
    // open event. We still need to relay everything, so we
    // snoop on messages here rather than consuming them.
    await new Promise((resolve, reject) => {
        const onMessage = (event) => {
            const frame = JSON.parse(String(event.data).trim());
            if (frame.method === "event" && frame.params?.type === "gateway.ready") {
                ws.removeEventListener("message", onMessage);
                resolve();
            }
        };
        ws.addEventListener("message", onMessage);
        ws.addEventListener("error", reject, { once: true });
    });
    ready = true;
    for (const line of queue)
        ws.send(line);
    queue = [];
    let inputBuffer = "";
    process.stdin.on("data", (chunk) => {
        inputBuffer += chunk.toString();
        let idx;
        while ((idx = inputBuffer.indexOf("\n")) !== -1) {
            const line = inputBuffer.slice(0, idx);
            inputBuffer = inputBuffer.slice(idx + 1);
            if (line.trim().length > 0) {
                if (ready)
                    ws.send(line);
                else
                    queue.push(line);
            }
        }
    });
    process.stdin.on("end", () => ws.close());
}
main().catch((err) => {
    process.stderr.write(`bridge failed: ${err.message}`);
    process.exit(1);
});
export {};
