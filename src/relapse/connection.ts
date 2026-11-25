import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { EventEmitter } from "node:events";
import { Client, type Channel, type JsonValue } from "relapsesdk";

export interface RelapseClientInfo {
  clientId: string;
  socketPath: string;
  profile?: string;
  username: string;
  userId: number;
  placeId: number;
  jobId: string;
  placeName: string;
  session: number;
}

const CONNECTOR_PATH = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../connector.luau");
const BOOT_TIMEOUT_MS = 12_000;

export class RelapseConnection extends EventEmitter {
  private main: Client | null = null;
  private bridge: Channel | null = null;
  private timer: NodeJS.Timeout | null = null;
  private bootstrapTimer: NodeJS.Timeout | null = null;
  private bootstrapAbort: AbortController | null = null;
  private running = false;
  private connecting = false;
  private generation = 0;
  private booting = false;
  private session = 0;
  private ready = false;
  private client: RelapseClientInfo | null = null;
  private readonly connectorSource = fs.readFileSync(CONNECTOR_PATH, "utf8");
  // Processes running the same connector share its index and decompiler gate.
  // A changed connector gets a new channel so different versions cannot mix.
  readonly channelName = `relapse.mcp.${crypto.createHash("sha256").update(this.connectorSource).digest("hex").slice(0, 24)}`;

  constructor(readonly socketPath: string) {
    super();
  }

  get activeClient(): RelapseClientInfo | null { return this.client; }

  start(): void {
    if (this.running) return;
    this.running = true;
    void this.connectMain();
  }

  stop(): void {
    this.running = false;
    this.generation++;
    if (this.timer) clearTimeout(this.timer);
    if (this.bootstrapTimer) clearTimeout(this.bootstrapTimer);
    this.timer = this.bootstrapTimer = null;
    this.bootstrapAbort?.abort();
    this.bootstrapAbort = null;
    this.session = 0;
    this.ready = this.booting = false;
    const bridge = this.bridge;
    const main = this.main;
    this.bridge = null;
    this.main = null;
    bridge?.close();
    main?.close();
    this.setClient(null);
  }

  async send(type: string, data: Record<string, unknown>, id: string): Promise<void> {
    if (!this.bridge?.connected || !this.client) throw new Error("Relapse MCP channel is unavailable");
    // MCP arguments can include omitted optional fields. The SDK accepts JSON
    // values only, so remove undefined fields before handing it the payload.
    const payload = JSON.parse(JSON.stringify({ ...data, id, type })) as JsonValue;
    await this.bridge.send(payload);
  }

  private setClient(value: RelapseClientInfo | null): void {
    const previous = this.client;
    this.client = value;
    if (previous?.clientId !== value?.clientId) this.emit("client", value, previous);
  }

  private scheduleReconnect(): void {
    if (!this.running || this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = null;
      void this.connectMain();
    }, 1000);
  }

  private async connectMain(): Promise<void> {
    if (!this.running || this.main || this.connecting) return;
    this.connecting = true;
    const generation = this.generation;
    try {
      const client = await Client.connect({ socketPath: this.socketPath });
      if (!this.running || this.main || !client.connected || generation !== this.generation) {
        client.close();
        if (this.running && !this.main) this.scheduleReconnect();
        return;
      }
      this.main = client;
      client.mainChannel.on("status", (status) => {
        if (this.running && this.main === client &&
            (status.session !== this.session || status.ready !== this.ready)) {
          this.newSession(status.session, status.ready);
        }
      });
      client.mainChannel.on("close", () => {
        if (this.main !== client) return;
        this.main = null;
        this.newSession(0, false);
        this.scheduleReconnect();
      });
      this.newSession(client.mainChannel.session, client.mainChannel.ready);
    } catch {
      this.scheduleReconnect();
    } finally {
      this.connecting = false;
    }
  }

  private newSession(session: number, ready: boolean): void {
    this.generation++;
    this.bootstrapAbort?.abort();
    this.bootstrapAbort = null;
    if (this.bootstrapTimer) clearTimeout(this.bootstrapTimer);
    this.bootstrapTimer = null;
    this.session = session;
    this.ready = ready;
    this.booting = false;
    this.emit("session", session, ready);
    this.setClient(null);
    const bridge = this.bridge;
    this.bridge = null;
    bridge?.close();
    if (ready) void this.bootstrap(this.generation);
  }

  private async bootstrap(generation: number): Promise<void> {
    if (!this.running || this.booting || !this.main?.connected || !this.ready || generation !== this.generation) return;
    this.booting = true;
    const abort = new AbortController();
    this.bootstrapAbort = abort;
    try {
      const source = `local __relapse_mcp_channel = ${JSON.stringify(this.channelName)}\n` +
        this.connectorSource;
      await this.main.mainChannel.execute(source, {
        name: "relapse-mcp.luau", timeoutMs: BOOT_TIMEOUT_MS, signal: abort.signal,
      });
      const deadline = Date.now() + BOOT_TIMEOUT_MS;
      while (this.running && generation === this.generation && Date.now() < deadline) {
        try {
          const channel = await this.main.openChannel(this.channelName, { signal: abort.signal });
          if (generation !== this.generation || !this.running) { channel.close(); return; }
          this.bridge = channel;
          channel.on("message", (message) => {
            if (this.bridge === channel) this.onBridgeMessage(message, generation);
          });
          channel.on("close", () => {
            if (this.bridge !== channel) return;
            this.bridge = null;
            this.setClient(null);
            if (!this.booting && this.running && generation === this.generation) {
              this.retryBootstrap(generation, 500);
            }
          });
          return;
        } catch {
          if (abort.signal.aborted) return;
        }
        await new Promise((resolve) => setTimeout(resolve, 150));
      }
      throw new Error("Luau channel did not publish");
    } catch (error) {
      if (this.running && generation === this.generation) {
        console.error(`[Relapse ${this.socketPath}] ${error instanceof Error ? error.message : error}`);
        this.retryBootstrap(generation, 1000);
      }
    } finally {
      if (this.bootstrapAbort === abort) this.bootstrapAbort = null;
      if (generation === this.generation) this.booting = false;
    }
  }

  private retryBootstrap(generation: number, delay: number): void {
    if (this.bootstrapTimer) clearTimeout(this.bootstrapTimer);
    this.bootstrapTimer = setTimeout(() => {
      this.bootstrapTimer = null;
      void this.bootstrap(generation);
    }, delay);
  }

  private onBridgeMessage(value: unknown, generation: number): void {
    if (!this.running || generation !== this.generation ||
        !value || typeof value !== "object" || Array.isArray(value)) return;
    const message = value as Record<string, unknown>;
    if (message.type === "hello") {
      const value = message.client;
      if (!value || typeof value !== "object" || Array.isArray(value)) return;
      const info = value as Record<string, unknown>;
      this.setClient({
        clientId: `${crypto.createHash("sha256").update(this.socketPath).digest("hex").slice(0, 16)}:${this.session}:${String(info.jobId ?? "")}`,
        socketPath: this.socketPath,
        profile: this.main?.profile ?? undefined,
        username: String(info.username ?? "Unknown"),
        userId: Number(info.userId ?? 0),
        placeId: Number(info.placeId ?? 0),
        jobId: String(info.jobId ?? ""),
        placeName: String(info.placeName ?? "Unknown"),
        session: this.session,
      });
      return;
    }
    if (this.client) this.emit("message", message, this.client);
  }
}
