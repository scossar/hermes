import { StringDecoder } from "node:string_decoder";

export interface InputRelayOptions {
  maxQueuedBytes?: number;
}

export class InputRelay {
  private buffer = "";
  private readonly decoder = new StringDecoder("utf8");
  private ready = false;
  private queued: string[] = [];
  private queuedBytes = 0;
  private readonly maxQueuedBytes: number;

  constructor(
    private readonly send: (line: string) => void,
    options: InputRelayOptions = {},
  ) {
    this.maxQueuedBytes = options.maxQueuedBytes ?? 1024 * 1024;
  }

  push(chunk: string | Buffer): void {
    this.buffer += this.decoder.write(typeof chunk === "string" ? Buffer.from(chunk) : chunk);

    let index: number;
    while ((index = this.buffer.indexOf("\n")) !== -1) {
      const line = this.buffer.slice(0, index);
      this.buffer = this.buffer.slice(index + 1);

      const bytes = Buffer.byteLength(line);
      if (bytes > this.maxQueuedBytes) {
        throw new Error("Hermes bridge input message exceeded its limit");
      }
      if (line.trim().length === 0) continue;
      if (this.ready) {
        this.send(line);
        continue;
      }

      if (this.queuedBytes + bytes > this.maxQueuedBytes) {
        throw new Error("Hermes bridge startup queue exceeded its limit");
      }
      this.queued.push(line);
      this.queuedBytes += bytes;
    }

    if (Buffer.byteLength(this.buffer) > this.maxQueuedBytes) {
      throw new Error("Hermes bridge input buffer exceeded its limit");
    }
  }

  markReady(): void {
    if (this.ready) return;
    this.ready = true;

    for (const line of this.queued) this.send(line);
    this.queued = [];
    this.queuedBytes = 0;
  }
}
