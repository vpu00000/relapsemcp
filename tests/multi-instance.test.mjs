import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { once } from "node:events";
import { setTimeout as delay } from "node:timers/promises";
import { test } from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { RelapseRuntime } from "../dist/relapse/runtime.js";

function frame(value) {
  const body = Buffer.from(JSON.stringify(value));
  const header = Buffer.alloc(4);
  header.writeUInt32BE(body.length);
  return Buffer.concat([header, body]);
}

async function until(predicate, timeout = 5000) {
  const deadline = Date.now() + timeout;
  while (!(await predicate())) {
    if (Date.now() >= deadline) throw new Error("Timed out waiting for multi-instance state");
    await delay(10);
  }
}

function directory(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "relapse-multi-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}

async function executor(t, dir, filename, label) {
  const sockets = new Set(), main = new Set(), bridge = new Set();
  const state = {
    socketPath: path.join(dir, filename), session: 1, boots: 0, commands: [],
    holdBootstrap: false, holdReplies: false, main, bridge, channels: new Set(),
  };
  let channelName;
  const server = net.createServer((socket) => {
    sockets.add(socket);
    socket.on("error", () => {});
    let buffer = Buffer.alloc(0), channel;
    socket.on("data", (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      while (buffer.length >= 4) {
        const size = buffer.readUInt32BE(0);
        if (buffer.length < size + 4) return;
        const message = JSON.parse(buffer.subarray(4, size + 4));
        buffer = buffer.subarray(size + 4);
        if (!channel) {
          channel = message.channel;
          if (channel !== "@main" && channel !== channelName) {
            socket.end(frame({ ok: false, error: "unknown channel" }));
            return;
          }
          const opened = { ok: true, version: 1, max_message_bytes: 8 * 1024 * 1024 };
          if (channel === "@main") {
            main.add(socket);
            socket.write(Buffer.concat([frame(opened), frame({
              type: "hello", pid: 1234, profile: label, ready: true, session: state.session,
            })]));
          } else {
            bridge.add(socket);
            // Identical game/account metadata must still identify separate executors.
            socket.write(Buffer.concat([frame(opened), frame({ type: "hello", client: {
              username: "SameUser", userId: 1, placeId: 42, jobId: "shared-job", placeName: "Same Game",
            } }), frame({ type: "script-sources", scripts: [{
              debugId: "same-debug-id", path: "game.Shared", source: `return '${label}:${state.session}'`,
            }], hasFinishedMapping: true, sourcesToMap: 1, processedSources: 1, skippedSources: 0,
            mappingSessionId: `mapping-${state.session}`, mappingSessionStartedAt: state.session * 1000,
            mappingRevision: 1, beginMappingSession: true })]));
          }
        } else if (channel === "@main" && message.op === "execute") {
          state.boots++;
          channelName = message.source.match(/local __relapse_mcp_channel = "([^"]+)"/)[1];
          state.channels.add(channelName);
          if (!state.holdBootstrap) socket.write(frame({ type: "exec_result", script_id: message.script_id, phase: "submitted" }));
        } else if (channel !== "@main") {
          state.commands.push({ message, socket });
          if (message.type === "get-game-info" && !state.holdReplies) {
            socket.write(frame({ id: message.id, output: `${label}:${state.session}` }));
          }
        }
      }
    });
    socket.on("close", () => { sockets.delete(socket); main.delete(socket); bridge.delete(socket); });
  });
  state.close = async () => {
    for (const socket of sockets) socket.destroy();
    if (server.listening) await new Promise((resolve) => server.close(resolve));
  };
  state.start = async () => { server.listen(state.socketPath); await once(server, "listening"); };
  state.teleport = () => {
    state.session++;
    for (const socket of main) socket.write(frame({ type: "status", ready: true, session: state.session }));
  };
  state.reply = (command, output) => command.socket.write(frame({ id: command.message.id, output }));
  t.after(state.close);
  await state.start();
  return state;
}

async function agent(t, dir, socketPath = "") {
  const transport = new StdioClientTransport({
    command: process.execPath, args: [path.resolve("dist/index.js")], cwd: dir,
    env: { ...process.env, RELAPSE_SOCKET_PATH: socketPath, RELAPSE_SOCKET_DIR: dir },
  });
  const client = new Client({ name: "multi-instance-test", version: "1" });
  await client.connect(transport);
  t.after(async () => { await client.close(); await transport.close(); });
  return client;
}

function call(client, name, args = {}) { return client.callTool({ name, arguments: args }); }
function text(result) { return result.content[0].text; }
async function clients(client) {
  return text(await call(client, "list-clients")).split("\n").filter((line) => line.includes(" | "))
    .map((line) => ({ id: line.split(" | ")[0].replace(/^\*?\s*/, ""), line }));
}
async function listed(client, count) {
  let result;
  await until(async () => { result = await clients(client); return result.length === count; });
  return result;
}
async function nextCommand(target, pending) {
  const count = target.commands.length;
  const promise = pending();
  await until(() => target.commands.length > count);
  return { promise, command: target.commands.at(-1) };
}

// Use a real shared prefix so ambiguous selection is exercised over stdio too.
function matchingPrefixName(dir) {
  const prefix = (filename) => crypto.createHash("sha256").update(path.join(dir, filename)).digest("hex")[0];
  for (let i = 0; ; i++) {
    const name = `relapse-Beta${i}.sock`;
    if (prefix(name) === prefix("relapse-Alpha.sock")) return name;
  }
}

test("discovered Relapse profiles isolate concurrent agents, replies, caches, and session changes", { timeout: 20_000 }, async (t) => {
  const dir = directory(t);
  const a = await executor(t, dir, "relapse-Alpha.sock", "Alpha");
  const b = await executor(t, dir, matchingPrefixName(dir), "Beta");
  fs.writeFileSync(path.join(dir, "relapse-file.sock"), "not a socket");
  fs.symlinkSync(a.socketPath, path.join(dir, "relapse-link.sock"));
  fs.mkdirSync(path.join(dir, "relapse-directory.sock"));
  const one = await agent(t, dir), two = await agent(t, dir);
  const ids = await listed(one, 2);
  const idA = ids.find((client) => client.line.includes("profile=Alpha ")).id;
  const idB = ids.find((client) => client.id !== idA).id;
  assert.notEqual(idA, idB);
  assert.deepEqual((await listed(two, 2)).map((client) => client.id), ids.map((client) => client.id));
  assert.equal(a.bridge.size, 2);
  assert.equal(b.bridge.size, 2);
  assert.deepEqual([...a.channels], [...b.channels]);
  assert.equal(a.channels.size, 1);
  assert.ok(ids.every((client) => client.line.includes("socket=")));

  // Unselected calls go to exactly one executor.
  const before = a.commands.length + b.commands.length;
  await call(one, "execute", { code: "one target only" });
  await until(() => a.commands.length + b.commands.length > before);
  assert.equal(a.commands.length + b.commands.length, before + 1);

  for (const clientId of [idA[0], "missing", " "]) {
    assert.equal((await call(one, "execute", { clientId, code: "must not run" })).isError, true);
    assert.equal((await call(one, "set-active-client", { clientId })).isError, true);
  }
  assert.equal(a.commands.length + b.commands.length, before + 1);
  await call(one, "set-active-client", { clientId: idA });
  await call(two, "set-active-client", { clientId: idB });
  assert.match(text(await call(one, "get-game-info")), /Alpha:1/);
  assert.match(text(await call(two, "get-game-info")), /Beta:1/);

  a.holdReplies = b.holdReplies = true;
  const pendingA = await nextCommand(a, () => call(one, "get-game-info"));
  const pendingB = await nextCommand(b, () => call(two, "get-game-info"));
  await call(one, "set-active-client", { clientId: idB });
  // A response with B's request ID arriving through A must not satisfy B's waiter.
  pendingA.command.socket.write(frame({ id: pendingB.command.message.id, output: "WRONG SOCKET" }));
  a.reply(pendingA.command, "only Alpha");
  const responseA = await pendingA.promise;
  b.reply(pendingB.command, "only Beta");
  const responseB = await pendingB.promise;
  assert.ok(text(responseA).includes(`[client=${idA} `));
  assert.ok(text(responseB).includes(`[client=${idB} `));
  assert.match(text(responseA), /only Alpha/);
  assert.match(text(responseB), /only Beta/);
  assert.doesNotMatch(text(responseB), /WRONG SOCKET/);

  const overrideA = await nextCommand(a, () => call(one, "get-game-info", { clientId: idA.slice(0, 16) }));
  const overrideB = await nextCommand(b, () => call(one, "get-game-info", { clientId: idB }));
  b.reply(overrideB.command, "override Beta");
  a.reply(overrideA.command, "override Alpha");
  assert.match(text(await overrideA.promise), /override Alpha/);
  assert.match(text(await overrideB.promise), /override Beta/);
  assert.equal(overrideA.command.message.clientId, undefined);
  a.holdReplies = b.holdReplies = false;
  assert.match(text(await call(one, "get-game-info")), /Beta:1/, "Per-call overrides leave the session default alone");

  for (const [clientId, label] of [[idA, "Alpha"], [idB, "Beta"]]) {
    const source = await call(one, "get-script-content", { clientId, scriptPath: "game.Shared" });
    assert.ok(text(source).includes(`[client=${clientId} `));
    assert.ok(text(source).includes(`return '${label}:1'`));
    const grep = await call(one, "script-grep", { clientId, query: "return" });
    assert.ok(text(grep).includes(`return '${label}:1'`));
    assert.doesNotMatch(text(grep), new RegExp(label === "Alpha" ? "Beta:1" : "Alpha:1"));
  }

  await call(one, "set-active-client", { clientId: idA });
  const interruptedA = await nextCommand(a, () => call(one, "get-data-by-code", { code: "return 1" }));
  const survivingB = await nextCommand(b, () => call(two, "get-data-by-code", { code: "return 2" }));
  a.teleport();
  assert.equal((await interruptedA.promise).isError, true);
  b.reply(survivingB.command, "Beta survived teleport");
  assert.match(text(await survivingB.promise), /Beta survived teleport/);
  let newA;
  await until(async () => {
    newA = (await clients(one)).find((client) => client.line.includes("profile=Alpha ") && client.id !== idA);
    return newA;
  });
  const beforeStale = a.commands.length + b.commands.length;
  assert.equal((await call(one, "execute", { code: "must not fall back" })).isError, true);
  assert.equal((await call(one, "get-game-info", { clientId: idA })).isError, true);
  assert.equal(a.commands.length + b.commands.length, beforeStale);
  const newSource = await call(one, "get-script-content", { clientId: newA.id, scriptPath: "game.Shared" });
  assert.match(text(newSource), /Alpha:2/);
  assert.doesNotMatch(text(newSource), /Alpha:1/);
  assert.match(text(await call(two, "get-script-content", { scriptPath: "game.Shared" })), /Beta:1/);

  // A bridge-only reconnect keeps the session identity; B's requests and index survive.
  const reconnectA = await nextCommand(a, () => call(one, "get-data-by-code", { clientId: newA.id, code: "return 1" }));
  const pendingOnB = await nextCommand(b, () => call(two, "get-data-by-code", { code: "return 2" }));
  for (const socket of a.bridge) socket.destroy();
  assert.equal((await reconnectA.promise).isError, true);
  b.reply(pendingOnB.command, "Beta survived disconnect");
  assert.match(text(await pendingOnB.promise), /Beta survived disconnect/);
  await until(() => a.bridge.size === 2);
  await listed(one, 2);
  assert.match(text(await call(one, "get-game-info", { clientId: newA.id })), /Alpha:2/);

  await a.close();
  await listed(one, 1);
  assert.match(text(await call(two, "get-script-content", { scriptPath: "game.Shared" })), /Beta:1/);
  await a.start();
  await listed(one, 2);
  assert.match(text(await call(one, "get-game-info", { clientId: newA.id })), /Alpha:2/);

  await one.close();
  await until(() => a.bridge.size === 1 && b.bridge.size === 1);
  assert.match(text(await call(two, "get-game-info")), /Beta:1/);
});

test("late profile sockets are discovered; an explicit path remains pinned", { timeout: 10_000 }, async (t) => {
  const dir = directory(t);
  const discovering = await agent(t, dir);
  assert.deepEqual(await clients(discovering), []);
  const socketPath = path.join(dir, "relapse-Default.sock");
  const pinned = await agent(t, dir, socketPath);
  const unnamed = await executor(t, dir, "relapse.sock", "Unnamed");
  await executor(t, dir, "relapse-Second.sock", "Second");
  await executor(t, dir, "relapse-Default.sock", "Default");
  const all = await listed(discovering, 3);
  const single = await listed(pinned, 1);
  assert.match(single[0].line, /profile=Default /);
  assert.ok(all.some((client) => client.id === single[0].id));
  assert.ok(all.some((client) => client.line.includes("socket=" + unnamed.socketPath)));
  assert.match(text(await call(pinned, "get-game-info")), /Default:1/);
});

test("stopping during bootstrap cancels pending work and allows a clean restart", { timeout: 5000 }, async (t) => {
  const dir = directory(t);
  const mock = await executor(t, dir, "relapse-Default.sock", "Default");
  mock.holdBootstrap = true;
  const runtime = new RelapseRuntime(mock.socketPath);
  t.after(() => runtime.stop());
  runtime.start();
  await until(() => mock.boots === 1);
  runtime.stop();
  await until(() => mock.main.size === 0);
  assert.deepEqual(runtime.activeClients, []);
  mock.holdBootstrap = false;
  runtime.start();
  await until(() => runtime.activeClients.length === 1);
  assert.equal(mock.boots, 2);
  runtime.stop();
  await until(() => mock.main.size === 0 && mock.bridge.size === 0);
});
