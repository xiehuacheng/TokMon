import { Hono } from "hono";
import { existsSync, readFileSync, writeFileSync } from "fs";
import { getDb } from "../db.js";
import { expandPath, getTokMonConfig, saveTokMonConfig, scanTokMonAll } from "../tokmon/scanner.js";
import { dataPath } from "../runtime-paths.js";

export const tokmonRoutes = new Hono();

type TokMonDashboardState = {
  source: string;
  from: string;
  to: string;
  interval: "hour" | "day";
  liveMode: boolean;
  rangeMode: "exact" | "round";
  rangeLabel: string | null;
  rangeHours: number | null;
  rangeDays: number | null;
  refreshRate: number;
  activeSeries: string;
  estimatedCost: number;
  costRates: {
    input: number;
    output: number;
    cache_create: number;
    cache_read: number;
  };
  updatedAt: string;
};

const defaultDashboardState: TokMonDashboardState = {
  source: "",
  from: "",
  to: "",
  interval: "day",
  liveMode: true,
  rangeMode: "exact",
  rangeLabel: "7D",
  rangeHours: null,
  rangeDays: 7,
  refreshRate: 3000,
  activeSeries: "total",
  estimatedCost: 0,
  costRates: {
    input: 0,
    output: 0,
    cache_create: 0,
    cache_read: 0,
  },
  updatedAt: new Date().toISOString(),
};

const dashboardStatePath = dataPath("tokmon-dashboard-state.json");
let dashboardState: TokMonDashboardState = loadDashboardState();

function loadDashboardState(): TokMonDashboardState {
  if (!existsSync(dashboardStatePath)) return defaultDashboardState;

  try {
    const state = JSON.parse(readFileSync(dashboardStatePath, "utf-8")) as Partial<TokMonDashboardState>;
    return {
      ...defaultDashboardState,
      ...state,
      interval: state.interval === "hour" ? "hour" : "day",
      liveMode: Boolean(state.liveMode),
      rangeMode: state.rangeMode === "round" ? "round" : "exact",
      rangeHours: optionalNumber(state.rangeHours),
      rangeDays: optionalNumber(state.rangeDays),
      refreshRate: Number.isFinite(Number(state.refreshRate)) ? Number(state.refreshRate) : defaultDashboardState.refreshRate,
      costRates: {
        ...defaultDashboardState.costRates,
        ...(state.costRates || {}),
      },
      updatedAt: state.updatedAt || defaultDashboardState.updatedAt,
    };
  } catch {
    return defaultDashboardState;
  }
}

function saveDashboardState() {
  writeFileSync(dashboardStatePath, JSON.stringify(currentDashboardState(), null, 2) + "\n");
}

function fmtDate(d: Date) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function fmtDateTime(d: Date, seconds: number) {
  return `${fmtDate(d)} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

function currentDashboardState(): TokMonDashboardState {
  if (!dashboardState.liveMode || (!dashboardState.rangeHours && !dashboardState.rangeDays)) {
    return dashboardState;
  }

  const to = new Date();
  const from = new Date(to);

  if (dashboardState.rangeHours) {
    if (dashboardState.rangeMode === "round") {
      from.setHours(to.getHours() - dashboardState.rangeHours + 1, 0, 0, 0);
    } else {
      from.setHours(from.getHours() - dashboardState.rangeHours);
    }
  } else if (dashboardState.rangeDays) {
    if (dashboardState.rangeMode === "round") {
      from.setDate(to.getDate() - dashboardState.rangeDays + 1);
      from.setHours(0, 0, 0, 0);
    } else {
      from.setDate(to.getDate() - dashboardState.rangeDays);
    }
  }

  return {
    ...dashboardState,
    from: fmtDateTime(from, 0),
    to: fmtDateTime(to, 59),
  };
}

function optionalNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const numberValue = Number(value);
  return Number.isFinite(numberValue) ? numberValue : null;
}

tokmonRoutes.get("/dashboard-state", (c) => {
  return c.json(currentDashboardState());
});

tokmonRoutes.post("/dashboard-state", async (c) => {
  const body = await c.req.json().catch(() => null);
  if (!body) return c.json({ error: "Invalid dashboard state" }, 400);

  const interval = body.interval === "hour" ? "hour" : "day";
  const rangeMode = body.rangeMode === "round" ? "round" : "exact";
  const source = ["", "claude-code", "codex"].includes(String(body.source || ""))
    ? String(body.source || "")
    : "";

  dashboardState = {
    source,
    from: String(body.from || dashboardState.from),
    to: String(body.to || dashboardState.to),
    interval,
    liveMode: Boolean(body.liveMode),
    rangeMode,
    rangeLabel: body.rangeLabel ? String(body.rangeLabel) : null,
    rangeHours: optionalNumber(body.rangeHours),
    rangeDays: optionalNumber(body.rangeDays),
    refreshRate: Number.isFinite(Number(body.refreshRate)) ? Number(body.refreshRate) : 3000,
    activeSeries: String(body.activeSeries || "total"),
    estimatedCost: Number.isFinite(Number(body.estimatedCost)) ? Number(body.estimatedCost) : 0,
    costRates: {
      input: optionalNumber(body.costRates?.input) ?? 0,
      output: optionalNumber(body.costRates?.output) ?? 0,
      cache_create: optionalNumber(body.costRates?.cache_create) ?? 0,
      cache_read: optionalNumber(body.costRates?.cache_read) ?? 0,
    },
    updatedAt: new Date().toISOString(),
  };
  saveDashboardState();

  return c.json(currentDashboardState());
});

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

  let where = "WHERE datetime(u.created_at, 'localtime') BETWEEN datetime(?) AND datetime(?)";
  const params: any[] = [from, to];
  if (source) { where += " AND u.source = ?"; params.push(source); }
  if (model) { where += " AND u.model = ?"; params.push(model); }

  const total = (db.prepare(`SELECT COUNT(*) as c FROM usage_records u ${where}`).get(...params) as any).c;
  const rows = db.prepare(`
    SELECT u.source,
           u.session_id,
           COALESCE(s_exact.id, s_file.id, u.session_id) as linked_session_id,
           u.model,
           u.input_tokens,
           u.output_tokens,
           u.cache_creation,
           u.cache_read,
           u.reasoning_tokens,
           datetime(u.created_at, 'localtime') as created_at
    FROM usage_records u
    LEFT JOIN sessions s_exact
      ON s_exact.source = u.source
      AND s_exact.id = u.session_id
    LEFT JOIN sessions s_file
      ON s_file.source = u.source
      AND s_exact.id IS NULL
      AND substr(s_file.file_path, -length(u.session_id || '.jsonl')) = u.session_id || '.jsonl'
    ${where}
    ORDER BY u.created_at DESC
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
