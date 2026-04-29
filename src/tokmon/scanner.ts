import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from "fs";
import { basename, join, resolve } from "path";
import { homedir } from "os";
import { getTokmonScanOffset, insertUsage, setTokmonScanOffset } from "../db.js";

export function expandPath(path: string): string {
  return resolve(path.replace(/^~/, homedir()));
}

export interface TokMonSourceConfig {
  path: string;
}

export interface TokMonConfig {
  port: number;
  sources: Record<string, TokMonSourceConfig>;
}

let config: TokMonConfig;

function defaultConfig(): TokMonConfig {
  return {
    port: 3388,
    sources: {
      "claude-code": { path: "~/.claude/projects" },
      codex: { path: "~/.codex/sessions" },
    },
  };
}

function configPath(): string {
  return resolve(process.cwd(), "tokmon.config.json");
}

function normalizeConfig(input: Partial<TokMonConfig>): TokMonConfig {
  const defaults = defaultConfig();
  const current = config || defaults;
  const sources = input.sources || current.sources || defaults.sources;

  return {
    port: Number.isInteger(input.port) ? input.port! : current.port,
    sources: {
      "claude-code": {
        path: sources["claude-code"]?.path || defaults.sources["claude-code"].path,
      },
      codex: {
        path: sources.codex?.path || defaults.sources.codex.path,
      },
    },
  };
}

export function loadTokMonConfig(): TokMonConfig {
  const path = configPath();
  if (existsSync(path)) {
    config = normalizeConfig(JSON.parse(readFileSync(path, "utf-8")));
  } else {
    config = defaultConfig();
  }
  return config;
}

export function getTokMonConfig(): TokMonConfig {
  if (!config) return loadTokMonConfig();
  return config;
}

export function saveTokMonConfig(nextConfig: Partial<TokMonConfig>): TokMonConfig {
  config = normalizeConfig(nextConfig);
  writeFileSync(configPath(), JSON.stringify(config, null, 2) + "\n");
  return config;
}

export function scanTokMonAll() {
  const activeConfig = getTokMonConfig();
  let count = 0;
  const sources = activeConfig.sources;
  if (sources["claude-code"]) {
    count += scanClaudeCode(expandPath(sources["claude-code"].path));
  }
  if (sources.codex) {
    count += scanCodex(expandPath(sources.codex.path));
  }
  return count;
}

export function backfillClaudeCodeUsage(): number {
  const source = getTokMonConfig().sources["claude-code"];
  if (!source) return 0;
  return scanClaudeCodeFiles(expandPath(source.path), backfillClaudeFile);
}

function scanClaudeCode(dir: string): number {
  return scanClaudeCodeFiles(dir, scanClaudeFile);
}

function scanClaudeCodeFiles(
  dir: string,
  scanner: (filePath: string, fallbackSessionId: string) => number,
): number {
  let count = 0;
  try {
    walkDir(dir, (filePath) => {
      if (!filePath.endsWith(".jsonl")) return;
      count += scanner(filePath, basename(filePath, ".jsonl"));
    });
  } catch {}
  return count;
}

function scanClaudeFile(filePath: string, fallbackSessionId: string): number {
  let count = 0;
  const offset = getTokmonScanOffset(filePath);
  const content = readFileSync(filePath, "utf-8");
  if (content.length <= offset) return 0;

  const seenIds = new Set<string>();
  const oldContent = content.slice(0, offset);
  for (const line of oldContent.split("\n")) {
    if (!line.trim()) continue;
    try {
      const record = parseClaudeUsageRecord(JSON.parse(line), fallbackSessionId);
      if (record?.messageId) seenIds.add(record.messageId);
    } catch {}
  }

  const newContent = content.slice(offset);
  for (const line of newContent.split("\n")) {
    if (!line.trim()) continue;
    try {
      const record = parseClaudeUsageRecord(JSON.parse(line), fallbackSessionId);
      if (!record) continue;
      if (record.messageId && seenIds.has(record.messageId)) continue;
      if (record.messageId) seenIds.add(record.messageId);
      if (insertUsage(record.usage)) count++;
    } catch {}
  }

  setTokmonScanOffset(filePath, content.length);
  return count;
}

function backfillClaudeFile(filePath: string, fallbackSessionId: string): number {
  let count = 0;
  const content = readFileSync(filePath, "utf-8");
  const seenIds = new Set<string>();

  for (const line of content.split("\n")) {
    if (!line.trim()) continue;
    try {
      const record = parseClaudeUsageRecord(JSON.parse(line), fallbackSessionId);
      if (!record) continue;
      if (record.messageId && seenIds.has(record.messageId)) continue;
      if (record.messageId) seenIds.add(record.messageId);
      if (insertUsage(record.usage)) count++;
    } catch {}
  }

  setTokmonScanOffset(filePath, content.length);
  return count;
}

function parseClaudeUsageRecord(obj: any, fallbackSessionId: string): any | null {
  if (obj.type !== "assistant") return null;
  let msg = obj.message;
  if (typeof msg === "string") {
    try { msg = JSON.parse(msg); } catch { return null; }
  }
  if (!msg?.usage) return null;
  const u = msg.usage;
  const usage = {
    source: "claude-code",
    sessionId: obj.sessionId || fallbackSessionId,
    model: msg.model || "unknown",
    inputTokens: u.input_tokens || u.prompt_tokens || 0,
    outputTokens: u.output_tokens || u.completion_tokens || 0,
    cacheCreation: u.cache_creation_input_tokens || 0,
    cacheRead: u.cache_read_input_tokens || 0,
    reasoningTokens: 0,
    createdAt: obj.timestamp || new Date().toISOString(),
  };
  if (!hasClaudeTokenUsage(usage)) return null;
  return { messageId: msg.id || "", usage };
}

function hasClaudeTokenUsage(usage: any): boolean {
  return Boolean(usage.inputTokens || usage.outputTokens || usage.cacheCreation || usage.cacheRead || usage.reasoningTokens);
}

function scanCodex(dir: string): number {
  let count = 0;
  try {
    walkDir(dir, (filePath) => {
      if (!filePath.endsWith(".jsonl")) return;
      const sessionId = filePath.split("/").pop()!.replace(".jsonl", "");
      count += scanCodexFile(filePath, sessionId);
    });
  } catch {}
  return count;
}

function walkDir(dir: string, cb: (path: string) => void) {
  try {
    for (const entry of readdirSync(dir)) {
      const full = join(dir, entry);
      const st = statSync(full);
      if (st.isDirectory()) walkDir(full, cb);
      else cb(full);
    }
  } catch {}
}

function scanCodexFile(filePath: string, sessionId: string): number {
  let count = 0;
  const content = readFileSync(filePath, "utf-8");
  const offset = getTokmonScanOffset(filePath);
  if (content.length <= offset) return 0;

  const seenUsage = new Set<string>();

  let lastModel = "unknown";
  for (const line of content.split("\n")) {
    if (!line.trim()) continue;
    try {
      const obj = JSON.parse(line);
      if (obj.type === "session_meta" || obj.type === "turn_context") {
        const payload = parsePayload(obj.payload);
        if (payload?.model) lastModel = payload.model;
      }
    } catch {}
  }

  const oldContent = content.slice(0, offset);
  for (const line of oldContent.split("\n")) {
    if (!line.trim()) continue;
    try {
      const usage = getCodexLastTokenUsage(JSON.parse(line));
      if (usage && hasCodexTokenUsage(usage)) seenUsage.add(codexUsageKey(usage));
    } catch {}
  }

  const newContent = content.slice(offset);
  for (const line of newContent.split("\n")) {
    if (!line.trim()) continue;
    try {
      const obj = JSON.parse(line);
      const u = getCodexLastTokenUsage(obj);
      if (!u || !hasCodexTokenUsage(u)) continue;
      const usageKey = codexUsageKey(u);
      if (seenUsage.has(usageKey)) continue;
      seenUsage.add(usageKey);
      if (insertUsage({
        source: "codex",
        sessionId,
        model: lastModel,
        inputTokens: Math.max((u.input_tokens || 0) - (u.cached_input_tokens || 0), 0),
        outputTokens: u.output_tokens || 0,
        cacheCreation: 0,
        cacheRead: u.cached_input_tokens || 0,
        reasoningTokens: u.reasoning_output_tokens || 0,
        createdAt: obj.timestamp || new Date().toISOString(),
      })) count++;
    } catch {}
  }

  setTokmonScanOffset(filePath, content.length);
  return count;
}

function parsePayload(payload: any): any {
  if (typeof payload !== "string") return payload;
  try {
    return JSON.parse(payload);
  } catch {
    try { return eval("(" + payload + ")"); } catch { return null; }
  }
}

function getCodexLastTokenUsage(obj: any): any {
  if (obj.type !== "event_msg") return null;
  const payload = parsePayload(obj.payload);
  if (payload?.type !== "token_count") return null;
  return payload.info?.last_token_usage || null;
}

function hasCodexTokenUsage(usage: any): boolean {
  return Boolean(usage.input_tokens || usage.output_tokens);
}

function codexUsageKey(usage: any): string {
  return [
    usage.input_tokens || 0,
    usage.output_tokens || 0,
    usage.cached_input_tokens || 0,
    usage.reasoning_output_tokens || 0,
  ].join(":");
}
