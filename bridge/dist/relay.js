export class InputRelay {
    send;
    buffer = "";
    ready = false;
    queued = [];
    queuedBytes = 0;
    maxQueuedBytes;
    constructor(send, options = {}) {
        this.send = send;
        this.maxQueuedBytes = options.maxQueuedBytes ?? 1024 * 1024;
    }
    push(chunk) {
        this.buffer += chunk.toString();
        let index;
        while ((index = this.buffer.indexOf("\n")) !== -1) {
            const line = this.buffer.slice(0, index);
            this.buffer = this.buffer.slice(index + 1);
            if (line.trim().length === 0)
                continue;
            if (this.ready) {
                this.send(line);
                continue;
            }
            const bytes = Buffer.byteLength(line);
            if (this.queuedBytes + bytes > this.maxQueuedBytes) {
                throw new Error("Hermes bridge startup queue exceeded its limit");
            }
            this.queued.push(line);
            this.queuedBytes += bytes;
        }
    }
    markReady() {
        if (this.ready)
            return;
        this.ready = true;
        for (const line of this.queued)
            this.send(line);
        this.queued = [];
        this.queuedBytes = 0;
    }
}
