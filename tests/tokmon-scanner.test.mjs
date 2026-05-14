import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, appendFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

const dataDir = mkdtempSync(join(tmpdir(), "agentmon-tokmon-data-"));
process.env.AGENTMON_DATA_DIR = dataDir;

after(async () => {
  const { closeDb } = await import("../src/db.ts");
  closeDb();
  rmSync(dataDir, { recursive: true, force: true });
});

test("calculateAppendRange skips unchanged files and resets truncated files", async () => {
  const { calculateAppendRange } = await import("../src/tokmon/scanner.ts");

  assert.equal(calculateAppendRange(128, 128), null);
  assert.deepEqual(calculateAppendRange(128, 32), { offset: 32, length: 96, nextOffset: 128 });
  assert.deepEqual(calculateAppendRange(64, 128), { offset: 0, length: 64, nextOffset: 64 });
});

test("scanTokMonAll keeps Codex session metadata when only usage lines are appended", async () => {
  const tempDir = mkdtempSync(join(tmpdir(), "agentmon-tokmon-"));
  process.env.AGENTMON_DATA_DIR = tempDir;

  try {
    const sessionsDir = join(tempDir, "codex-sessions");
    mkdirSync(sessionsDir, { recursive: true });
    const logPath = join(sessionsDir, "session.jsonl");
    writeFileSync(logPath, [
      JSON.stringify({
        type: "session_meta",
        payload: { id: "session-123", model: "gpt-test" },
      }),
      JSON.stringify({
        type: "event_msg",
        timestamp: "2026-05-14T01:00:00.000Z",
        payload: {
          type: "token_count",
          info: {
            last_token_usage: {
              input_tokens: 20,
              output_tokens: 5,
              cached_input_tokens: 3,
              reasoning_output_tokens: 2,
            },
          },
        },
      }),
      "",
    ].join("\n"));

    const { closeDb, getDb } = await import("../src/db.ts");
    const { saveTokMonConfig, scanTokMonAll } = await import("../src/tokmon/scanner.ts");
    saveTokMonConfig({
      sources: {
        "claude-code": { path: join(tempDir, "missing-claude") },
        codex: { path: sessionsDir },
      },
    });

    assert.equal(scanTokMonAll(), 1);

    appendFileSync(logPath, JSON.stringify({
      type: "event_msg",
      timestamp: "2026-05-14T01:01:00.000Z",
      payload: {
        type: "token_count",
        info: {
          last_token_usage: {
            input_tokens: 30,
            output_tokens: 10,
            cached_input_tokens: 4,
            reasoning_output_tokens: 1,
          },
        },
      },
    }) + "\n");

    assert.equal(scanTokMonAll(), 1);

    const rows = getDb().prepare(`
      SELECT session_id, model, input_tokens, output_tokens
      FROM usage_records
      ORDER BY created_at
    `).all();

    assert.deepEqual(rows, [
      { session_id: "session-123", model: "gpt-test", input_tokens: 17, output_tokens: 5 },
      { session_id: "session-123", model: "gpt-test", input_tokens: 26, output_tokens: 10 },
    ]);
    closeDb();
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});
