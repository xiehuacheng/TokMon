import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { serveStatic } from "@hono/node-server/serve-static";
import { closeDb, getDb, rebuildRuntimeDatabase } from "./db.js";
import { dedupeCodexUsageRecords, removeZeroClaudeUsageRecords } from "./db.js";
import { loadConfig, scanAll } from "./scanner/index.js";
import { sessionsRoutes } from "./routes/sessions.js";
import { skillsRoutes } from "./routes/skills.js";
import { mcpRoutes } from "./routes/mcp.js";
import { settingsRoutes } from "./routes/settings.js";
import { tokmonRoutes } from "./routes/tokmon.js";
import { backfillClaudeCodeUsage, loadTokMonConfig, scanTokMonAll } from "./tokmon/scanner.js";
import { ActivityLeases } from "./activity-leases.js";

const config = loadConfig();
loadTokMonConfig();
getDb();

interface ScanStatus {
  running: boolean;
  phase: string;
  current: number;
  total: number;
  processed: number;
  startedAt: string | null;
  finishedAt: string | null;
  error: string | null;
}

const scanStatus: ScanStatus = {
  running: false,
  phase: "Waiting to scan",
  current: 0,
  total: 0,
  processed: 0,
  startedAt: null,
  finishedAt: null,
  error: null,
};

let scanTimer: ReturnType<typeof setInterval> | undefined;
let tokmonScanTimer: ReturnType<typeof setInterval> | undefined;
let activityTimer: ReturnType<typeof setInterval> | undefined;
let periodicScanRunning = false;
let periodicTokmonScanRunning = false;
let initialScanStarted = false;
const activityLeases = new ActivityLeases();

const app = new Hono();
app.get("/api/scan-status", (c) => c.json(scanStatus));
app.get("/api/activity", (c) => c.json(activityLeases.snapshot()));
app.post("/api/activity", async (c) => {
  const body = await c.req.json().catch(() => null);
  const name = String(body?.name || "").trim();
  if (!name) return c.json({ error: "Activity name is required" }, 400);
  const ttlMs = Number.isFinite(Number(body?.ttlMs)) ? Number(body.ttlMs) : 10_000;
  activityLeases.renew(name, ttlMs);
  startPeriodicScans();
  return c.json(activityLeases.snapshot());
});
app.delete("/api/activity/:name", (c) => {
  activityLeases.release(c.req.param("name"));
  reconcilePeriodicScans();
  return c.json(activityLeases.snapshot());
});
app.post("/api/scan", (c) => {
  try {
    const count = scanAll();
    return c.json({ ok: true, count });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return c.json({ error: message }, 500);
  }
});
app.post("/api/rebuild-database", (c) => {
  if (scanStatus.running) return c.json({ error: "Scan is already running" }, 409);
  setTimeout(() => { void runInitialScan({ rebuild: true }); }, 50);
  return c.json({ ok: true });
});
app.route("/api/tokmon", tokmonRoutes);
app.route("/api/sessions", sessionsRoutes);
app.route("/api/skills", skillsRoutes);
app.route("/api/mcp", mcpRoutes);
app.route("/api/settings", settingsRoutes);
app.use("/*", serveStatic({ root: "./public" }));

const port = config.port;
console.log(`AgentMon running on http://localhost:${port}`);

const server = serve({ fetch: app.fetch, port });

const wait = (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms));

async function runInitialScan(options: { rebuild?: boolean } = {}) {
  const steps: Array<{ phase: string; run: () => number; done: (count: number) => string }> = [
    ...(options.rebuild ? [{
      phase: "Clearing local index database",
      run: () => { rebuildRuntimeDatabase(); return 0; },
      done: () => "Local index database cleared",
    }] : []),
    {
      phase: "Scanning sessions, skills, MCP, and settings",
      run: scanAll,
      done: count => `Initial scan: ${count} records imported`,
    },
    {
      phase: "Deduplicating Codex usage records",
      run: dedupeCodexUsageRecords,
      done: count => `Removed ${count} duplicate Codex usage records`,
    },
    {
      phase: "Cleaning zero-token Claude usage records",
      run: removeZeroClaudeUsageRecords,
      done: count => `Removed ${count} zero-token Claude usage records`,
    },
    {
      phase: "Backfilling Claude usage records",
      run: backfillClaudeCodeUsage,
      done: count => `Backfilled ${count} Claude usage records`,
    },
    {
      phase: "Scanning token usage logs",
      run: scanTokMonAll,
      done: count => `Initial TokMon scan: ${count} usage records imported`,
    },
  ];

  Object.assign(scanStatus, {
    running: true,
    phase: options.rebuild ? "Starting database rebuild" : "Starting initial scan",
    current: 0,
    total: steps.length,
    processed: 0,
    startedAt: new Date().toISOString(),
    finishedAt: null,
    error: null,
  });

  try {
    for (let i = 0; i < steps.length; i++) {
      const step = steps[i];
      Object.assign(scanStatus, { phase: step.phase, current: i + 1 });
      await wait(40);
      const count = step.run();
      scanStatus.processed += count;
      const message = step.done(count);
      scanStatus.phase = message;
      console.log(message);
      await wait(40);
    }
    Object.assign(scanStatus, {
      running: false,
      phase: "Scan complete",
      finishedAt: new Date().toISOString(),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    Object.assign(scanStatus, {
      running: false,
      phase: "Scan failed",
      finishedAt: new Date().toISOString(),
      error: message,
    });
    console.error("Initial scan error:", err);
  }
}

function startPeriodicScans() {
  if (!activityLeases.hasActiveLeases()) return;

  startInitialScanOnce();

  if (!activityTimer) {
    activityTimer = setInterval(reconcilePeriodicScans, 2_000);
  }
  if (!scanTimer) {
    scanTimer = setInterval(() => {
      if (!activityLeases.hasActiveLeases()) {
        reconcilePeriodicScans();
        return;
      }
      if (periodicScanRunning) return;
      periodicScanRunning = true;
      try { scanAll(); } catch (e) { console.error("Scan error:", e); }
      finally { periodicScanRunning = false; }
    }, 10_000);
  }
  if (!tokmonScanTimer) {
    tokmonScanTimer = setInterval(() => {
      if (!activityLeases.hasActiveLeases()) {
        reconcilePeriodicScans();
        return;
      }
      if (periodicTokmonScanRunning) return;
      periodicTokmonScanRunning = true;
      try {
        const count = scanTokMonAll();
        if (count > 0) console.log(`TokMon scan: ${count} new usage records`);
      } catch (e) {
        console.error("TokMon scan error:", e);
      } finally {
        periodicTokmonScanRunning = false;
      }
    }, 5_000);
  }
}

function startInitialScanOnce() {
  if (initialScanStarted || scanStatus.running || scanStatus.finishedAt) return;
  initialScanStarted = true;
  setTimeout(() => { void runInitialScan(); }, 50);
}

function reconcilePeriodicScans() {
  if (activityLeases.hasActiveLeases()) {
    startPeriodicScans();
    return;
  }

  if (scanTimer) {
    clearInterval(scanTimer);
    scanTimer = undefined;
  }
  if (tokmonScanTimer) {
    clearInterval(tokmonScanTimer);
    tokmonScanTimer = undefined;
  }
  if (activityTimer) {
    clearInterval(activityTimer);
    activityTimer = undefined;
  }
}

function runTokmonScanOnce() {
  if (periodicTokmonScanRunning) return;
  periodicTokmonScanRunning = true;
  try {
    const count = scanTokMonAll();
    if (count > 0) console.log(`TokMon scan: ${count} new usage records`);
  } catch (e) {
    console.error("TokMon scan error:", e);
  } finally {
    periodicTokmonScanRunning = false;
  }
}

const shutdown = () => {
  if (scanTimer) clearInterval(scanTimer);
  if (tokmonScanTimer) clearInterval(tokmonScanTimer);
  if (activityTimer) clearInterval(activityTimer);
  (server as any).closeAllConnections?.();
  closeDb();
  process.kill(process.pid, "SIGKILL");
};

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
