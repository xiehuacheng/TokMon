import { Hono } from "hono";
import { getDb } from "../db.js";
import { expandPath, getTokMonConfig, saveTokMonConfig, scanTokMonAll } from "../tokmon/scanner.js";

export const tokmonRoutes = new Hono();

tokmonRoutes.get("/scan", (c) => {
  const count = scanTokMonAll();
  return c.json({ inserted: count });
});

tokmonRoutes.get("/config", (c) => {
  const config = getTokMonConfig();
  return c.json({
    port: config.port,
    sources: {
      "claude-code": {
        path: config.sources["claude-code"]?.path || "",
        resolvedPath: expandPath(config.sources["claude-code"]?.path || "~/.claude/projects"),
      },
      codex: {
        path: config.sources.codex?.path || "",
        resolvedPath: expandPath(config.sources.codex?.path || "~/.codex/sessions"),
      },
    },
  });
});

tokmonRoutes.post("/config", async (c) => {
  const body = await c.req.json().catch(() => null);
  const claudePath = String(body?.sources?.["claude-code"]?.path || "").trim();
  const codexPath = String(body?.sources?.codex?.path || "").trim();

  if (!claudePath || !codexPath) {
    return c.json({ error: "Both Claude Code and Codex paths are required." }, 400);
  }

  const current = getTokMonConfig();
  const config = saveTokMonConfig({
    port: current.port,
    sources: {
      "claude-code": { path: claudePath },
      codex: { path: codexPath },
    },
  });
  const inserted = scanTokMonAll();

  return c.json({
    saved: true,
    inserted,
    port: config.port,
    sources: {
      "claude-code": {
        path: config.sources["claude-code"].path,
        resolvedPath: expandPath(config.sources["claude-code"].path),
      },
      codex: {
        path: config.sources.codex.path,
        resolvedPath: expandPath(config.sources.codex.path),
      },
    },
  });
});

tokmonRoutes.get("/summary", (c) => {
  const from = c.req.query("from") || "2000-01-01";
  const to = c.req.query("to") || "2099-12-31";
  const source = c.req.query("source");
  const model = c.req.query("model");
  const db = getDb();

  let where = "WHERE datetime(created_at, 'localtime') BETWEEN datetime(?) AND datetime(?)";
  const params: any[] = [from, to];
  if (source) { where += " AND source = ?"; params.push(source); }
  if (model) { where += " AND model = ?"; params.push(model); }

  const total = db.prepare(`
    SELECT COUNT(*) as total_requests,
           COALESCE(SUM(input_tokens), 0) as total_input,
           COALESCE(SUM(output_tokens), 0) as total_output,
           COALESCE(SUM(cache_creation), 0) as total_cache_creation,
           COALESCE(SUM(cache_read), 0) as total_cache_read,
           COALESCE(SUM(reasoning_tokens), 0) as total_reasoning
    FROM usage_records ${where}
  `).get(...params);

  const bySource = db.prepare(`
    SELECT source, COUNT(*) as requests,
           SUM(input_tokens) as input_tokens, SUM(output_tokens) as output_tokens,
           SUM(cache_creation) as cache_creation, SUM(cache_read) as cache_read
    FROM usage_records ${where}
    GROUP BY source
  `).all(...params);

  const byModel = db.prepare(`
    SELECT model, source, COUNT(*) as requests,
           SUM(input_tokens) as input_tokens, SUM(output_tokens) as output_tokens,
           SUM(cache_creation) as cache_creation, SUM(cache_read) as cache_read
    FROM usage_records ${where}
    GROUP BY model, source ORDER BY requests DESC
  `).all(...params);

  return c.json({ total, bySource, byModel });
});

tokmonRoutes.get("/trend", (c) => {
  const interval = c.req.query("interval") || "hour";
  const from = c.req.query("from") || "2000-01-01";
  const to = c.req.query("to") || "2099-12-31";
  const source = c.req.query("source");
  const model = c.req.query("model");
  const db = getDb();

  const fmt = interval === "day" ? "%Y-%m-%d" : "%Y-%m-%d %H:00";
  let extraFilter = "";
  const params: any[] = [from, to];
  if (source) { extraFilter += " AND source = ?"; params.push(source); }
  if (model) { extraFilter += " AND model = ?"; params.push(model); }

  const rows = db.prepare(`
    SELECT strftime('${fmt}', created_at, 'localtime') as bucket,
           SUM(input_tokens) as input_tokens,
           SUM(output_tokens) as output_tokens,
           SUM(cache_creation) as cache_creation,
           SUM(cache_read) as cache_read,
           COUNT(*) as requests
    FROM usage_records
    WHERE datetime(created_at, 'localtime') BETWEEN datetime(?) AND datetime(?) ${extraFilter}
    GROUP BY bucket ORDER BY bucket
  `).all(...params);

  return c.json(rows);
});

tokmonRoutes.get("/heatmap", (c) => {
  const source = c.req.query("source");
  const model = c.req.query("model");
  const db = getDb();
  let extraFilter = "";
  const params: any[] = ["-365 days"];
  if (source) { extraFilter += " AND source = ?"; params.push(source); }
  if (model) { extraFilter += " AND model = ?"; params.push(model); }

  const rows = db.prepare(`
    SELECT strftime('%Y-%m-%d', created_at, 'localtime') as day,
           COUNT(*) as requests,
           SUM(input_tokens) as input_tokens,
           SUM(output_tokens) as output_tokens,
           SUM(cache_creation) as cache_creation,
           SUM(cache_read) as cache_read
    FROM usage_records
    WHERE created_at >= datetime('now', ?) ${extraFilter}
    GROUP BY day
  `).all(...params);

  return c.json(rows);
});

tokmonRoutes.get("/models", (c) => {
  const rows = getDb().prepare(`
    SELECT model, MAX(created_at) as last_used
    FROM usage_records
    WHERE model != '' AND model != 'unknown' AND model != '<synthetic>'
    GROUP BY model
    ORDER BY last_used DESC
  `).all();
  return c.json(rows);
});

tokmonRoutes.get("/records", (c) => {
  const page = parseInt(c.req.query("page") || "0");
  const limit = parseInt(c.req.query("limit") || "20");
  const from = c.req.query("from") || "2000-01-01";
  const to = c.req.query("to") || "2099-12-31";
  const source = c.req.query("source");
  const model = c.req.query("model");
  const db = getDb();

  let where = "WHERE datetime(created_at, 'localtime') BETWEEN datetime(?) AND datetime(?)";
  const params: any[] = [from, to];
  if (source) { where += " AND source = ?"; params.push(source); }
  if (model) { where += " AND model = ?"; params.push(model); }

  const total = (db.prepare(`SELECT COUNT(*) as c FROM usage_records ${where}`).get(...params) as any).c;
  const rows = db.prepare(`
    SELECT source, session_id, model, input_tokens, output_tokens,
           cache_creation, cache_read, reasoning_tokens,
           datetime(created_at, 'localtime') as created_at
    FROM usage_records ${where}
    ORDER BY created_at DESC
    LIMIT ? OFFSET ?
  `).all(...params, limit, page * limit);

  return c.json({ total, page, limit, rows });
});

tokmonRoutes.get("/sessions", (c) => {
  const rows = getDb().prepare(`
    SELECT session_id, source, model,
           COUNT(*) as requests,
           SUM(input_tokens) as input_tokens,
           SUM(output_tokens) as output_tokens,
           MIN(created_at) as first_at,
           MAX(created_at) as last_at
    FROM usage_records
    GROUP BY session_id, source
    ORDER BY last_at DESC
    LIMIT 50
  `).all();
  return c.json(rows);
});
