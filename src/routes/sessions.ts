import { Hono } from "hono";
import { getDb, setTokmonScanOffset } from "../db.js";
import { expandPath, safeJsonParse, safeReadText } from "../scanner/utils.js";
import { getConfig } from "../scanner/index.js";
import { basename, dirname, join } from "path";
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, statSync, unlinkSync, writeFileSync } from "fs";

export const sessionsRoutes = new Hono();

sessionsRoutes.get("/", (c) => {
  const db = getDb();
  const source = c.req.query("source");
  const project = c.req.query("project");
  const model = c.req.query("model");
  const q = c.req.query("q");
  const archived = c.req.query("archived");
  const page = parseInt(c.req.query("page") || "1", 10);
  const limit = parseInt(c.req.query("limit") || "50", 10);
  const offset = (page - 1) * limit;

  let where = "WHERE 1=1";
  const params: unknown[] = [];

  if (source) { where += " AND source = ?"; params.push(source); }
  if (project) { where += " AND project_path LIKE ?"; params.push(`%${project}%`); }
  if (model) { where += " AND model LIKE ?"; params.push(`%${model}%`); }
  if (q) {
    where += " AND (project_path LIKE ? OR model LIKE ? OR first_prompt LIKE ? OR last_prompt LIKE ? OR summary LIKE ?)";
    params.push(`%${q}%`, `%${q}%`, `%${q}%`, `%${q}%`, `%${q}%`);
  }
  if (archived === "1") { where += " AND archived = 1"; }
  else { where += " AND archived = 0"; }

  const total = (db.prepare(`SELECT COUNT(*) as c FROM sessions ${where}`).get(...params) as { c: number }).c;
  const rows = db.prepare(`SELECT * FROM sessions ${where} ORDER BY last_active_at DESC LIMIT ? OFFSET ?`).all(...params, limit, offset);

  return c.json({ total, page, limit, rows });
});

sessionsRoutes.get("/directories", (c) => {
  const rawPath = c.req.query("path") || "~";
  const showHidden = c.req.query("showHidden") === "1";
  const currentPath = expandPath(rawPath);

  try {
    const st = statSync(currentPath);
    const dirPath = st.isDirectory() ? currentPath : dirname(currentPath);
    const entries = readdirSync(dirPath, { withFileTypes: true })
      .filter(entry => entry.isDirectory() && (showHidden || !entry.name.startsWith(".")))
      .map(entry => entry.name)
      .sort((a, b) => a.localeCompare(b))
      .map(name => ({ name, path: join(dirPath, name) }));

    return c.json({
      path: dirPath,
      parent: dirname(dirPath),
      entries,
    });
  } catch (err) {
    return c.json({
      error: err instanceof Error ? err.message : "Failed to read directory",
      path: currentPath,
    }, 400);
  }
});

sessionsRoutes.post("/migrate-project", async (c) => {
  const db = getDb();
  const body = await c.req.json<{ ids?: string[]; projectPath?: string }>();
  const ids = Array.from(new Set((body.ids || []).filter(id => typeof id === "string" && id.trim()).map(id => id.trim())));
  const targetProjectPath = body.projectPath ? expandPath(body.projectPath.trim()) : "";

  if (!ids.length) return c.json({ error: "No sessions selected" }, 400);
  if (!targetProjectPath) return c.json({ error: "Target project path is required" }, 400);

  const placeholders = ids.map(() => "?").join(", ");
  const rows = db.prepare(`
    SELECT id, source, project_path, file_path, is_active
    FROM sessions
    WHERE id IN (${placeholders})
  `).all(...ids) as SessionMigrationRow[];

  const foundIds = new Set(rows.map(row => row.id));
  const missingIds = ids.filter(id => !foundIds.has(id));
  if (missingIds.length) return c.json({ error: "Some sessions were not found", missingIds }, 404);

  const liveRows = rows.filter(row => row.is_active);
  if (liveRows.length) {
    return c.json({
      error: "Live sessions cannot be migrated",
      liveIds: liveRows.map(row => row.id),
    }, 409);
  }

  const fileErrors = rows.filter(row => !row.file_path || !existsSync(row.file_path));
  if (fileErrors.length) {
    return c.json({
      error: "Some session files are missing",
      missingFileIds: fileErrors.map(row => row.id),
    }, 409);
  }

  const plan = rows.map(row => {
    const sourcePath = row.file_path!;
    const nextPath = row.source === "claude-code"
      ? join(getClaudeProjectsRoot(), claudeProjectDirName(targetProjectPath), basename(sourcePath))
      : sourcePath;
    return { row, sourcePath, nextPath };
  });

  const collisions = plan.filter(item => item.nextPath !== item.sourcePath && existsSync(item.nextPath));
  if (collisions.length) {
    return c.json({
      error: "Destination session file already exists",
      collisions: collisions.map(item => ({ id: item.row.id, filePath: item.nextPath })),
    }, 409);
  }

  const migrated: Array<{ id: string; source: string; filePath: string }> = [];
  const errors: Array<{ id: string; error: string }> = [];

  for (const item of plan) {
    try {
      const rewrittenLength = rewriteSessionProject(item.sourcePath, item.row.source, targetProjectPath);
      if (item.nextPath !== item.sourcePath) {
        mkdirSync(join(getClaudeProjectsRoot(), claudeProjectDirName(targetProjectPath)), { recursive: true });
        renameSync(item.sourcePath, item.nextPath);
        db.prepare("DELETE FROM tokmon_scan_state WHERE file_path = ?").run(item.sourcePath);
      }
      setTokmonScanOffset(item.nextPath, rewrittenLength);
      db.prepare("UPDATE sessions SET project_path = ?, file_path = ? WHERE id = ?").run(targetProjectPath, item.nextPath, item.row.id);
      migrated.push({ id: item.row.id, source: item.row.source, filePath: item.nextPath });
    } catch (err) {
      errors.push({ id: item.row.id, error: err instanceof Error ? err.message : String(err) });
    }
  }

  return c.json({
    ok: errors.length === 0,
    projectPath: targetProjectPath,
    migratedCount: migrated.length,
    migrated,
    errors,
  }, errors.length ? 207 : 200);
});

sessionsRoutes.get("/:id", (c) => {
  const db = getDb();
  const row = db.prepare("SELECT * FROM sessions WHERE id = ?").get(c.req.param("id")) as Record<string, unknown> | undefined;
  if (!row) return c.json({ error: "not found" }, 404);

  const page = Math.max(1, parseInt(c.req.query("page") || "1", 10));
  const limit = Math.max(1, parseInt(c.req.query("limit") || "50", 10));

  let allMessages: unknown[] = [];
  if (typeof row.file_path === "string" && existsSync(row.file_path)) {
    const text = safeReadText(row.file_path);
    if (text) {
      for (const line of text.split("\n")) {
        if (!line.trim()) continue;
        const obj = safeJsonParse(line);
        if (!obj) continue;
        if (row.source === "claude-code") {
          if (obj.type === "user" || obj.type === "assistant") {
            allMessages.push({
              type: obj.type,
              text: extractText(obj),
              timestamp: obj.timestamp,
              model: obj.type === "assistant" ? obj.message?.model : undefined,
            });
          }
        } else {
          if (obj.type === "event_msg" && obj.payload?.type === "user_message") {
            allMessages.push({ type: "user", text: obj.payload.message, timestamp: obj.timestamp });
          }
          if (obj.type === "response_item" && obj.payload?.role === "assistant") {
            allMessages.push({
              type: "assistant",
              text: extractCodexContent(obj.payload.content),
              timestamp: obj.timestamp,
            });
          }
        }
      }
    }
  }

  const totalMessages = allMessages.length;
  const offset = (page - 1) * limit;
  const messages = allMessages.slice(offset, offset + limit);

  return c.json({
    ...row,
    messages,
    totalMessages,
    page,
    limit,
    hasMore: offset + limit < totalMessages,
  });
});

sessionsRoutes.patch("/:id", async (c) => {
  const db = getDb();
  const id = c.req.param("id");
  const body = await c.req.json<{ tags?: string[]; archived?: number }>();
  const row = db.prepare("SELECT id FROM sessions WHERE id = ?").get(id);
  if (!row) return c.json({ error: "not found" }, 404);

  if (body.tags !== undefined) {
    db.prepare("UPDATE sessions SET tags = ? WHERE id = ?").run(JSON.stringify(body.tags), id);
  }
  if (body.archived !== undefined) {
    db.prepare("UPDATE sessions SET archived = ? WHERE id = ?").run(body.archived, id);
  }
  return c.json({ ok: true });
});

sessionsRoutes.delete("/:id", (c) => {
  const db = getDb();
  const id = c.req.param("id");
  const row = db.prepare("SELECT file_path FROM sessions WHERE id = ?").get(id) as { file_path: string | null } | undefined;
  if (!row) return c.json({ error: "not found" }, 404);

  if (row.file_path && existsSync(row.file_path)) {
    unlinkSync(row.file_path);
  }
  db.prepare("DELETE FROM sessions WHERE id = ?").run(id);
  return c.json({ ok: true });
});

interface SessionMigrationRow {
  id: string;
  source: string;
  project_path: string | null;
  file_path: string | null;
  is_active: number;
}

function getClaudeProjectsRoot() {
  return join(expandPath(getConfig().sources["claude-code"].home), "projects");
}

function claudeProjectDirName(projectPath: string) {
  return projectPath.replace(/\//g, "-");
}

function rewriteSessionProject(filePath: string, source: string, projectPath: string) {
  const content = readFileSync(filePath, "utf-8");
  const rewritten = content.split("\n").map(line => {
    if (!line.trim()) return line;
    try {
      const obj = JSON.parse(line);
      if (source === "claude-code") rewriteClaudeProject(obj, projectPath);
      if (source === "codex") rewriteCodexProject(obj, projectPath);
      return JSON.stringify(obj);
    } catch {
      return line;
    }
  }).join("\n");
  writeFileSync(filePath, rewritten, "utf-8");
  return rewritten.length;
}

function rewriteClaudeProject(obj: unknown, projectPath: string) {
  if (!obj || typeof obj !== "object") return;
  const record = obj as Record<string, unknown>;
  if (typeof record.cwd === "string") record.cwd = projectPath;
}

function rewriteCodexProject(obj: unknown, projectPath: string) {
  if (!obj || typeof obj !== "object") return;
  const record = obj as Record<string, unknown>;
  if (typeof record.cwd === "string") record.cwd = projectPath;
  if (record.type !== "session_meta" && record.type !== "turn_context") return;

  if (record.payload && typeof record.payload === "object") {
    const payload = record.payload as Record<string, unknown>;
    if (typeof payload.cwd === "string") payload.cwd = projectPath;
    return;
  }

  if (typeof record.payload === "string") {
    const parsed = safeJsonParse(record.payload);
    if (parsed && typeof parsed === "object") {
      const payload = parsed as Record<string, unknown>;
      if (typeof payload.cwd === "string") {
        payload.cwd = projectPath;
        record.payload = JSON.stringify(payload);
      }
    }
  }
}

function extractText(obj: Record<string, unknown>): string | null {
  const msg = obj.message as Record<string, unknown> | undefined;
  if (!msg) return null;
  const content = msg.content;
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    for (const part of content) {
      if (typeof part === "string") return part;
      if (part && typeof part === "object" && "text" in part && typeof part.text === "string") return part.text;
    }
  }
  return null;
}

function extractCodexContent(content: unknown): string | null {
  if (!Array.isArray(content)) return null;
  for (const part of content) {
    if (part && typeof part === "object" && "text" in part && typeof part.text === "string") return part.text;
  }
  return null;
}
