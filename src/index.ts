import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { serveStatic } from "@hono/node-server/serve-static";
import { closeDb, getDb } from "./db.js";
import { dedupeCodexUsageRecords, removeZeroClaudeUsageRecords } from "./db.js";
import { loadConfig, scanAll } from "./scanner/index.js";
import { sessionsRoutes } from "./routes/sessions.js";
import { skillsRoutes } from "./routes/skills.js";
import { mcpRoutes } from "./routes/mcp.js";
import { settingsRoutes } from "./routes/settings.js";
import { tokmonRoutes } from "./routes/tokmon.js";
import { backfillClaudeCodeUsage, loadTokMonConfig, scanTokMonAll } from "./tokmon/scanner.js";

const config = loadConfig();
loadTokMonConfig();
getDb();

const initialCount = scanAll();
console.log(`Initial scan: ${initialCount} records imported`);
const duplicateCount = dedupeCodexUsageRecords();
if (duplicateCount > 0) console.log(`Removed ${duplicateCount} duplicate Codex usage records`);
const zeroClaudeCount = removeZeroClaudeUsageRecords();
if (zeroClaudeCount > 0) console.log(`Removed ${zeroClaudeCount} zero-token Claude usage records`);
const claudeBackfillCount = backfillClaudeCodeUsage();
if (claudeBackfillCount > 0) console.log(`Backfilled ${claudeBackfillCount} Claude usage records`);
const initialUsageCount = scanTokMonAll();
console.log(`Initial TokMon scan: ${initialUsageCount} usage records imported`);

const scanTimer = setInterval(() => {
  try { scanAll(); } catch (e) { console.error("Scan error:", e); }
}, 5_000);

const tokmonScanTimer = setInterval(() => {
  try {
    const count = scanTokMonAll();
    if (count > 0) console.log(`TokMon scan: ${count} new usage records`);
  } catch (e) {
    console.error("TokMon scan error:", e);
  }
}, 3_000);

const app = new Hono();
app.route("/api/tokmon", tokmonRoutes);
app.route("/api/sessions", sessionsRoutes);
app.route("/api/skills", skillsRoutes);
app.route("/api/mcp", mcpRoutes);
app.route("/api/settings", settingsRoutes);
app.use("/*", serveStatic({ root: "./public" }));

const port = config.port;
console.log(`AgentMon running on http://localhost:${port}`);

const server = serve({ fetch: app.fetch, port });

const shutdown = () => {
  clearInterval(scanTimer);
  clearInterval(tokmonScanTimer);
  (server as any).closeAllConnections?.();
  closeDb();
  process.kill(process.pid, "SIGKILL");
};

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
