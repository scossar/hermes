#!/usr/bin/env node
// Usage: node bridge.js <hermes-base-url>
// Relays newline-delimited JSON between stdin/stdout and the Hermes WebSocket.
import { InputRelay } from "./relay.js";
const base = (process.argv[2] ?? "http://127.0.0.1:9119").replace(/\/$/, "");
const bootstrapTimeoutMs = 10_000;
async function fetchSessionToken(baseUrl) {
    const response = await fetch(`${baseUrl}/`, {
        signal: AbortSignal.timeout(bootstrapTimeoutMs),
    });
    if (!response.ok) {
        throw new Error(`GET / returned HTTP ${response.status}`);
    }
    const html = await response.text();
    const token = html.match(/__HERMES_SESSION_TOKEN__\s*=\s*"([^"]+)"/)?.[1];
    if (!token)
        throw new Error("Hermes session token not found");
    return token;
}
function toWebSocketUrl(baseUrl, token) {
    const wsBase = baseUrl.replace(/^http:/, "ws:").replace(/^https:/, "wss:");
    return `${wsBase}/api/ws?token=${encodeURIComponent(token)}`;
}
async function main() {
    process.stderr.write(`connecting to Hermes at ${base}\n`);
    const token = await fetchSessionToken(base);
    const ws = new WebSocket(toWebSocketUrl(base, token));
    let intentionalShutdown = false;
    let gatewayReady = false;
    const fail = (message, closeCode = 1011) => {
        process.stderr.write(`${message}\n`);
        process.exitCode = 1;
        process.stdin.pause();
        if (ws.readyState === WebSocket.CONNECTING || ws.readyState === WebSocket.OPEN) {
            ws.close(closeCode, "bridge failure");
        }
    };
    const relay = new InputRelay((line) => {
        if (ws.readyState !== WebSocket.OPEN) {
            throw new Error("Hermes WebSocket is not open");
        }
        ws.send(line);
    });
    // Start reading immediately. Requests received while Hermes starts are queued
    // and flushed only after the gateway.ready event.
    process.stdin.on("data", (chunk) => {
        try {
            relay.push(chunk);
        }
        catch (error) {
            intentionalShutdown = true;
            fail(`bridge input failed: ${error.message}`);
        }
    });
    process.stdin.on("end", () => {
        intentionalShutdown = true;
        if (ws.readyState === WebSocket.CONNECTING || ws.readyState === WebSocket.OPEN) {
            ws.close(1000, "stdin closed");
        }
    });
    ws.addEventListener("message", (event) => {
        const raw = String(event.data);
        process.stdout.write(`${raw}\n`);
        if (gatewayReady)
            return;
        try {
            const frame = JSON.parse(raw);
            if (frame.method === "event" && frame.params?.type === "gateway.ready") {
                gatewayReady = true;
                relay.markReady();
                process.stderr.write("Hermes gateway ready\n");
            }
        }
        catch (error) {
            intentionalShutdown = true;
            fail(`invalid JSON from Hermes: ${error.message}`, 1002);
        }
    });
    ws.addEventListener("error", () => {
        process.stderr.write("Hermes WebSocket error\n");
    });
    ws.addEventListener("close", (event) => {
        if (!intentionalShutdown) {
            const phase = gatewayReady ? "after startup" : "before gateway.ready";
            fail(`Hermes WebSocket closed unexpectedly ${phase} (code ${event.code})`);
        }
    });
    const timeout = setTimeout(() => {
        if (gatewayReady)
            return;
        intentionalShutdown = true;
        fail("timed out waiting for Hermes gateway.ready", 1000);
    }, bootstrapTimeoutMs);
    timeout.unref();
}
main().catch((error) => {
    process.stderr.write(`bridge failed: ${error.message}\n`);
    process.exitCode = 1;
});
