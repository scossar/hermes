import assert from "node:assert/strict";
import test from "node:test";
import { InputRelay } from "./relay.js";
test("queues complete input lines until the gateway is ready", () => {
    const sent = [];
    const relay = new InputRelay((line) => sent.push(line));
    relay.push('{"id":1}\n{"id":');
    relay.push('2}\n');
    assert.deepEqual(sent, []);
    relay.markReady();
    assert.deepEqual(sent, ['{"id":1}', '{"id":2}']);
});
test("sends complete lines immediately after readiness", () => {
    const sent = [];
    const relay = new InputRelay((line) => sent.push(line));
    relay.markReady();
    relay.push("first\nsecond\n");
    assert.deepEqual(sent, ["first", "second"]);
});
test("ignores blank input lines", () => {
    const sent = [];
    const relay = new InputRelay((line) => sent.push(line));
    relay.push("\n  \nrequest\n");
    relay.markReady();
    assert.deepEqual(sent, ["request"]);
});
test("rejects an excessive startup queue", () => {
    const relay = new InputRelay(() => { }, { maxQueuedBytes: 5 });
    assert.throws(() => relay.push("123456\n"), /startup queue exceeded/i);
});
