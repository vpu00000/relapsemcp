import assert from "node:assert/strict";
import { test } from "node:test";
import {
  upsertScriptSources,
  getScriptSourceIndex,
  clearScriptSourceIndex,
} from "../dist/bridge/handlers/shared/script-source-store.js";

test("incremental removals release sources and stale frames cannot restore them", () => {
  const identity = { clientId: "source-store-test", placeId: 42, jobId: "test" };
  const source = { debugId: "one", path: "game.One", source: "return 1" };
  const frame = (revision, fields = {}) => ({
    mappingSessionId: "mapping-1", mappingSessionStartedAt: 1000,
    mappingRevision: revision, ...fields,
  });
  try {
    upsertScriptSources(identity, frame(1, {
      beginMappingSession: true, scripts: [source], sourcesToMap: 1,
      processedSources: 1, skippedSources: 0, hasFinishedMapping: true,
    }));
    assert.equal(getScriptSourceIndex(identity).scripts.length, 1);
    upsertScriptSources(identity, frame(3, {
      removedScriptIds: ["one"], sourcesToMap: 0, processedSources: 0,
    }));
    assert.equal(getScriptSourceIndex(identity).scripts.length, 0);
    upsertScriptSources(identity, frame(2, { scripts: [source] }));
    assert.equal(getScriptSourceIndex(identity).scripts.length, 0);
    assert.equal(getScriptSourceIndex(identity).sourceIndexComplete, true);

    upsertScriptSources(identity, frame(4, {
      scripts: [source], sourcesToMap: 1, processedSources: 1,
    }));
    assert.equal(getScriptSourceIndex(identity).scripts.length, 1);
    upsertScriptSources(identity, {
      mappingSessionId: "mapping-2", mappingSessionStartedAt: 2000,
      mappingRevision: 1, beginMappingSession: true, scripts: [],
    });
    assert.equal(getScriptSourceIndex(identity).scripts.length, 0);
    upsertScriptSources(identity, frame(100, { scripts: [source] }));
    assert.equal(getScriptSourceIndex(identity).scripts.length, 0);
  } finally {
    clearScriptSourceIndex(identity.clientId);
  }
});
