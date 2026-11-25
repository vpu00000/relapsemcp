import path from "node:path";
import { EventEmitter } from "node:events";
import { watchClients } from "relapsesdk";
import { RelapseConnection, type RelapseClientInfo } from "./connection.js";

export type { RelapseClientInfo } from "./connection.js";

export class RelapseRuntime extends EventEmitter {
  private readonly connections = new Map<string, RelapseConnection>();
  private discovery: AbortController | null = null;

  constructor(
    readonly socketPath = process.env.RELAPSE_SOCKET_PATH || undefined,
    readonly socketDirectory = process.env.RELAPSE_SOCKET_DIR || "/tmp",
  ) {
    super();
  }

  get activeClients(): RelapseClientInfo[] {
    return [...this.connections.values()].flatMap((connection) =>
      connection.activeClient ? [connection.activeClient] : []
    );
  }

  start(): void {
    if (this.discovery) return;
    this.discovery = new AbortController();
    if (this.socketPath) {
      // A pinned socket remains a target even when the executor has not started.
      this.reconcile([path.resolve(this.socketPath)]);
    } else {
      void this.watchDiscovery(this.discovery);
    }
  }

  stop(): void {
    this.discovery?.abort();
    this.discovery = null;
    for (const connection of this.connections.values()) connection.stop();
    this.connections.clear();
  }

  async send(type: string, data: Record<string, unknown>, id: string, clientId: string): Promise<void> {
    const connection = [...this.connections.values()].find((entry) => entry.activeClient?.clientId === clientId);
    if (!connection) throw new Error("Relapse MCP client is unavailable");
    await connection.send(type, data, id);
  }

  private async watchDiscovery(discovery: AbortController): Promise<void> {
    while (!discovery.signal.aborted) {
      try {
        for await (const clients of watchClients({
          directory: this.socketDirectory, intervalMs: 1000, signal: discovery.signal,
        })) {
          if (this.discovery !== discovery) return;
          this.reconcile(clients.map((client) => client.socketPath));
        }
        return;
      } catch (error) {
        if (discovery.signal.aborted) return;
        console.error("[Relapse] Client discovery failed:", error);
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
    }
  }

  private reconcile(socketPaths: string[]): void {
    const paths = new Set(socketPaths);
    for (const [socketPath, connection] of this.connections) {
      if (paths.has(socketPath)) continue;
      connection.stop();
      this.connections.delete(socketPath);
    }
    for (const socketPath of paths) {
      if (this.connections.has(socketPath)) continue;
      const connection = new RelapseConnection(socketPath);
      this.connections.set(socketPath, connection);
      connection.on("client", (client, previous) => this.emit("client", client, previous));
      connection.on("message", (message, client) => this.emit("message", message, client));
      connection.start();
    }
  }
}

export const runtime = new RelapseRuntime();
