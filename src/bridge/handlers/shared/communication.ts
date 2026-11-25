import crypto from "node:crypto";
import { runtime, type RelapseClientInfo } from "../../../relapse/runtime.js";
import { upsertScriptSources, clearScriptSourceIndex } from "./script-source-store.js";
import type { RobloxResponse, DispatchResult, ResponseResolver } from "../../types.js";
import { getActiveClientId, resolveTargetClient } from "./registry.js";

const resolvers = new Map<string, { clientId: string; resolve: ResponseResolver }>();

runtime.on("client", (client: { clientId: string } | null, previous: { clientId: string } | null) => {
  if (previous && previous.clientId !== client?.clientId) {
    clearScriptSourceIndex(previous.clientId);
    for (const [id, pending] of resolvers) {
      if (pending.clientId !== previous.clientId) continue;
      resolvers.delete(id);
      pending.resolve({ id, error: "Relapse MCP channel disconnected while the request was running." });
    }
  }
});
runtime.on("message", (message: Record<string, unknown>, client: RelapseClientInfo) => {
  if (message.type === "script-sources") {
    try {
      upsertScriptSources({ clientId: client.clientId, placeId: client.placeId, jobId: client.jobId }, {
        scripts: Array.isArray(message.scripts) ? message.scripts as [] : [],
        removedScriptIds: message.removedScriptIds,
        hasFinishedMapping: message.hasFinishedMapping === true,
        sourcesToMap: Number(message.sourcesToMap ?? 0),
        processedSources: Number(message.processedSources ?? 0),
        skippedSources: Number(message.skippedSources ?? 0),
        mappingSessionId: message.mappingSessionId,
        mappingSessionStartedAt: message.mappingSessionStartedAt,
        mappingRevision: message.mappingRevision,
        beginMappingSession: message.beginMappingSession,
      });
    } catch (error) {
      console.error("[Relapse] Failed to index script sources:", error);
    }
    return;
  }
  if (typeof message.id !== "string") return;
  const pending = resolvers.get(message.id);
  if (!pending || pending.clientId !== client.clientId) return;
  resolvers.delete(message.id);
  pending.resolve(message as RobloxResponse);
});

export function SendArbitraryDataToClient(
  type: string, data: Record<string, unknown>, id?: string, clientId = getActiveClientId()
): Promise<DispatchResult> {
  const target = resolveTargetClient(clientId);
  if (!target) return Promise.resolve(clientId ? "INVALID_CLIENT" : null);
  const requestId = id ?? crypto.randomUUID();
  return runtime.send(type, data, requestId, target.clientId).then(() => requestId).catch((error) => {
    console.error("[Relapse] Could not send command:", error);
    return null;
  });
}

export async function SendAndWaitForResponse(
  type: string, data: Record<string, unknown>, timeoutMs = 15_000,
  clientId = getActiveClientId()
): Promise<{ callId: DispatchResult; response?: RobloxResponse }> {
  const target = resolveTargetClient(clientId);
  if (!target) return { callId: clientId ? "INVALID_CLIENT" : null };
  const id = crypto.randomUUID();
  // Register before writing: a fast peer can reply before Channel.send resolves.
  const response = new Promise<RobloxResponse>((resolve) => {
    const timeout = setTimeout(() => {
      resolvers.delete(id);
      resolve({ id, error: `Timed out waiting for response after ${timeoutMs}ms.` });
    }, timeoutMs);
    resolvers.set(id, { clientId: target.clientId, resolve: (response) => { clearTimeout(timeout); resolve(response); } });
  });
  try {
    await runtime.send(type, data, id, target.clientId);
  } catch (error) {
    console.error("[Relapse] Could not send command:", error);
    const pending = resolvers.get(id);
    resolvers.delete(id);
    pending?.resolve({ id, error: "Relapse MCP channel disconnected while sending the request." });
    return { callId: null };
  }
  return { callId: id, response: await response };
}
