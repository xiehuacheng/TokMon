import Database from "better-sqlite3";
import { dataPath } from "./runtime-paths.js";

const DB_PATH = dataPath("agentmon.db");

let db: Database.Database;

export function closeDb() {
  if (db) { db.close(); db = undefined!; }
}

export function getDb(): Database.Database {
  if (!db) {
    db = new Database(DB_PATH);
    db.pragma("journal_mode = WAL");
    initSchema();
  }
  return db;
}

function initSchema() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      source TEXT NOT NULL,
      project_path TEXT,
      first_prompt TEXT,
      last_prompt TEXT,
      summary TEXT,
      model TEXT,
      git_branch TEXT,
      message_count INTEGER DEFAULT 0,
      version TEXT,
      kind TEXT,
      entrypoint TEXT,
      started_at TEXT NOT NULL,
      last_active_at TEXT NOT NULL,
      is_active INTEGER DEFAULT 0,
      tags TEXT DEFAULT '[]',
      archived INTEGER DEFAULT 0,
      file_path TEXT
    );
    CREATE TABLE IF NOT EXISTS skills (
      id TEXT PRIMARY KEY,
      source TEXT NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      path TEXT NOT NULL,
      is_symlink INTEGER DEFAULT 0,
      symlink_target TEXT,
      scope TEXT DEFAULT 'user',
      skill_md TEXT,
      enabled INTEGER DEFAULT 1,
      scanned_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS mcp_servers (
      id TEXT PRIMARY KEY,
      source TEXT NOT NULL,
      name TEXT NOT NULL,
      url TEXT,
      command TEXT,
      args TEXT,
      env TEXT,
      enabled INTEGER DEFAULT 1,
      config_raw TEXT,
      scanned_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS plugins (
      id TEXT PRIMARY KEY,
      source TEXT NOT NULL,
      name TEXT NOT NULL,
      version TEXT,
      enabled INTEGER DEFAULT 1,
      scanned_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS scan_state (
      file_path TEXT PRIMARY KEY,
      last_offset INTEGER NOT NULL DEFAULT 0,
      last_mtime TEXT,
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS usage_records (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      source          TEXT NOT NULL,
      session_id      TEXT NOT NULL,
      model           TEXT NOT NULL DEFAULT 'unknown',
      input_tokens    INTEGER NOT NULL DEFAULT 0,
      output_tokens   INTEGER NOT NULL DEFAULT 0,
      cache_creation  INTEGER NOT NULL DEFAULT 0,
      cache_read      INTEGER NOT NULL DEFAULT 0,
      reasoning_tokens INTEGER NOT NULL DEFAULT 0,
      created_at      TEXT NOT NULL,
      UNIQUE(source, session_id, created_at, input_tokens, output_tokens)
    );

    CREATE TABLE IF NOT EXISTS tokmon_scan_state (
      file_path   TEXT PRIMARY KEY,
      last_offset INTEGER NOT NULL DEFAULT 0,
      updated_at  TEXT DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_sessions_source ON sessions(source);
    CREATE INDEX IF NOT EXISTS idx_sessions_started ON sessions(started_at);
    CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_path);
    CREATE INDEX IF NOT EXISTS idx_sessions_archived ON sessions(archived);
    CREATE INDEX IF NOT EXISTS idx_skills_source ON skills(source);
    CREATE INDEX IF NOT EXISTS idx_mcp_source ON mcp_servers(source);
    CREATE INDEX IF NOT EXISTS idx_usage_source ON usage_records(source);
    CREATE INDEX IF NOT EXISTS idx_usage_created ON usage_records(created_at);
    CREATE INDEX IF NOT EXISTS idx_usage_session ON usage_records(session_id);
    CREATE INDEX IF NOT EXISTS idx_usage_model ON usage_records(model);
  `);

  try {
    db.exec("ALTER TABLE sessions ADD COLUMN last_prompt TEXT");
  } catch {}
  try {
    db.exec("ALTER TABLE skills ADD COLUMN scope TEXT DEFAULT 'user'");
  } catch {}
}

export function getScanState(filePath: string): { offset: number; mtime: string | null } {
  const row = getDb().prepare("SELECT last_offset, last_mtime FROM scan_state WHERE file_path = ?").get(filePath) as { last_offset: number; last_mtime: string | null } | undefined;
  return { offset: row?.last_offset ?? 0, mtime: row?.last_mtime ?? null };
}

export function setScanState(filePath: string, offset: number, mtime?: string) {
  getDb().prepare(`
    INSERT INTO scan_state (file_path, last_offset, last_mtime) VALUES (?, ?, ?)
    ON CONFLICT(file_path) DO UPDATE SET last_offset = excluded.last_offset, last_mtime = excluded.last_mtime, updated_at = datetime('now')
  `).run(filePath, offset, mtime ?? null);
}

export function rebuildRuntimeDatabase() {
  const d = getDb();
  d.transaction(() => {
    d.prepare("DELETE FROM sessions").run();
    d.prepare("DELETE FROM skills").run();
    d.prepare("DELETE FROM mcp_servers").run();
    d.prepare("DELETE FROM plugins").run();
    d.prepare("DELETE FROM scan_state").run();
    d.prepare("DELETE FROM usage_records").run();
    d.prepare("DELETE FROM tokmon_scan_state").run();
  })();
}

export interface SessionRecord {
  id: string;
  source: string;
  projectPath: string | null;
  firstPrompt: string | null;
  lastPrompt: string | null;
  summary: string | null;
  model: string | null;
  gitBranch: string | null;
  messageCount: number;
  version: string | null;
  kind: string | null;
  entrypoint: string | null;
  startedAt: string;
  lastActiveAt: string;
  isActive: number;
  filePath: string | null;
}

export function upsertSession(record: SessionRecord) {
  getDb().prepare(`
    INSERT INTO sessions (
      id, source, project_path, first_prompt, last_prompt, summary, model, git_branch,
      message_count, version, kind, entrypoint, started_at, last_active_at,
      is_active, file_path
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      source = excluded.source,
      project_path = excluded.project_path,
      first_prompt = excluded.first_prompt,
      last_prompt = excluded.last_prompt,
      summary = excluded.summary,
      model = excluded.model,
      git_branch = excluded.git_branch,
      message_count = excluded.message_count,
      version = excluded.version,
      kind = excluded.kind,
      entrypoint = excluded.entrypoint,
      started_at = excluded.started_at,
      last_active_at = excluded.last_active_at,
      is_active = excluded.is_active,
      file_path = excluded.file_path
  `).run(
    record.id,
    record.source,
    record.projectPath,
    record.firstPrompt,
    record.lastPrompt,
    record.summary,
    record.model,
    record.gitBranch,
    record.messageCount,
    record.version,
    record.kind,
    record.entrypoint,
    record.startedAt,
    record.lastActiveAt,
    record.isActive,
    record.filePath,
  );
}

export interface SkillRecord {
  id: string;
  source: string;
  name: string;
  description: string | null;
  path: string;
  isSymlink: number;
  symlinkTarget: string | null;
  scope?: string;
  skillMd: string | null;
  enabled: number;
  scannedAt: string;
}

export function upsertSkill(record: SkillRecord) {
  getDb().prepare(`
    INSERT INTO skills (id, source, name, description, path, is_symlink, symlink_target, scope, skill_md, enabled, scanned_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      source = excluded.source,
      name = excluded.name,
      description = excluded.description,
      path = excluded.path,
      is_symlink = excluded.is_symlink,
      symlink_target = excluded.symlink_target,
      scope = excluded.scope,
      skill_md = excluded.skill_md,
      enabled = excluded.enabled,
      scanned_at = excluded.scanned_at
  `).run(
    record.id,
    record.source,
    record.name,
    record.description,
    record.path,
    record.isSymlink,
    record.symlinkTarget,
    record.scope || "user",
    record.skillMd,
    record.enabled,
    record.scannedAt,
  );
}

export interface McpRecord {
  id: string;
  source: string;
  name: string;
  url: string | null;
  command: string | null;
  args: string | null;
  env: string | null;
  enabled: number;
  configRaw: string | null;
  scannedAt: string;
}

export function upsertMcp(record: McpRecord) {
  getDb().prepare(`
    INSERT INTO mcp_servers (id, source, name, url, command, args, env, enabled, config_raw, scanned_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      source = excluded.source,
      name = excluded.name,
      url = excluded.url,
      command = excluded.command,
      args = excluded.args,
      env = excluded.env,
      enabled = excluded.enabled,
      config_raw = excluded.config_raw,
      scanned_at = excluded.scanned_at
  `).run(
    record.id,
    record.source,
    record.name,
    record.url,
    record.command,
    record.args,
    record.env,
    record.enabled,
    record.configRaw,
    record.scannedAt,
  );
}

export interface PluginRecord {
  id: string;
  source: string;
  name: string;
  version: string | null;
  enabled: number;
  scannedAt: string;
}

export function upsertPlugin(record: PluginRecord) {
  getDb().prepare(`
    INSERT INTO plugins (id, source, name, version, enabled, scanned_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      source = excluded.source,
      name = excluded.name,
      version = excluded.version,
      enabled = excluded.enabled,
      scanned_at = excluded.scanned_at
  `).run(record.id, record.source, record.name, record.version, record.enabled, record.scannedAt);
}

export function deleteMissingByIds(table: "sessions" | "skills" | "mcp_servers" | "plugins", source: string, ids: string[]) {
  const d = getDb();
  if (ids.length === 0) {
    d.prepare(`DELETE FROM ${table} WHERE source = ?`).run(source);
    return;
  }
  const placeholders = ids.map(() => "?").join(", ");
  d.prepare(`DELETE FROM ${table} WHERE source = ? AND id NOT IN (${placeholders})`).run(source, ...ids);
}

export interface UsageRecord {
  source: string;
  sessionId: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  cacheCreation: number;
  cacheRead: number;
  reasoningTokens: number;
  createdAt: string;
}

export function insertUsage(record: UsageRecord) {
  const result = getDb().prepare(`
    INSERT OR IGNORE INTO usage_records
      (source, session_id, model, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    record.source,
    record.sessionId,
    record.model,
    record.inputTokens,
    record.outputTokens,
    record.cacheCreation,
    record.cacheRead,
    record.reasoningTokens,
    record.createdAt,
  );
  return result.changes > 0;
}

export function getTokmonScanOffset(filePath: string): number {
  const row = getDb().prepare("SELECT last_offset FROM tokmon_scan_state WHERE file_path = ?").get(filePath) as { last_offset: number } | undefined;
  return row?.last_offset ?? 0;
}

export function setTokmonScanOffset(filePath: string, offset: number) {
  getDb().prepare(`
    INSERT INTO tokmon_scan_state (file_path, last_offset) VALUES (?, ?)
    ON CONFLICT(file_path) DO UPDATE SET last_offset = excluded.last_offset, updated_at = datetime('now')
  `).run(filePath, offset);
}

export function dedupeCodexUsageRecords(): number {
  const result = getDb().prepare(`
    DELETE FROM usage_records
    WHERE source = 'codex'
      AND id NOT IN (
        SELECT MIN(id)
        FROM usage_records
        WHERE source = 'codex'
        GROUP BY session_id, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens
      )
  `).run();
  return result.changes;
}

export function removeZeroClaudeUsageRecords(): number {
  const result = getDb().prepare(`
    DELETE FROM usage_records
    WHERE source = 'claude-code'
      AND input_tokens = 0
      AND output_tokens = 0
      AND cache_creation = 0
      AND cache_read = 0
      AND reasoning_tokens = 0
  `).run();
  return result.changes;
}
