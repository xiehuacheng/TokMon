import { basename } from "path";
import { statSync } from "fs";
import { deleteMissingByIds, getSessionIdByFilePath, getSessionScanState, setSessionScanState, updateSessionActive, upsertSession } from "../db.js";
import { extractCodexText, safeJsonParse, safeReadText, walkFiles } from "./utils.js";

const CODEX_ACTIVE_WINDOW_MS = 10 * 60 * 1000;

export function scanCodexSessions(codexHome: string) {
  const sessionsRoot = `${codexHome}/sessions`;
  const seenIds: string[] = [];

  walkFiles(sessionsRoot, (filePath) => {
    if (!filePath.endsWith(".jsonl")) return;
    const fileState = currentFileState(filePath);
    if (!fileState) return;

    const indexedId = getSessionIdByFilePath("codex", filePath);
    const scanState = getSessionScanState(filePath);
    if (
      indexedId &&
      scanState.offset === fileState.size &&
      scanState.mtime === fileState.mtime
    ) {
      updateSessionActive("codex", indexedId, isRecentlyWritten(filePath) ? 1 : 0);
      seenIds.push(indexedId);
      return;
    }

    const text = safeReadText(filePath);
    if (!text) return;

    let sessionId: string | null = null;
    let firstUserMessage: string | null = null;
    let lastUserMessage: string | null = null;
    let firstResponseUser: string | null = null;
    let summary: string | null = null;
    let model: string | null = null;
    let projectPath: string | null = null;
    let version: string | null = null;
    let startedAt: string | null = null;
    let lastActiveAt: string | null = null;
    let messageCount = 0;

    for (const line of text.split("\n")) {
      if (!line.trim()) continue;
      const obj = safeJsonParse(line);
      if (!obj || typeof obj !== "object") continue;
      if (typeof obj.timestamp === "string") {
        startedAt ??= obj.timestamp;
        lastActiveAt = obj.timestamp;
      }

      if (obj.type === "session_meta" && obj.payload) {
        sessionId ??= typeof obj.payload.id === "string" ? obj.payload.id : null;
        projectPath ??= typeof obj.payload.cwd === "string" ? obj.payload.cwd : null;
        version ??= typeof obj.payload.cli_version === "string" ? obj.payload.cli_version : null;
        model ??= typeof obj.payload.model === "string" ? obj.payload.model : null;
      }

      if (obj.type === "turn_context" && obj.payload) {
        projectPath ??= typeof obj.payload.cwd === "string" ? obj.payload.cwd : null;
        model ??= typeof obj.payload.model === "string" ? obj.payload.model : null;
      }

      if (obj.type === "event_msg" && obj.payload?.type === "user_message") {
        const msg = typeof obj.payload.message === "string" ? obj.payload.message : null;
        firstUserMessage ??= msg;
        if (msg) lastUserMessage = msg;
      }

      if (obj.type === "response_item" && obj.payload?.type === "message") {
        if (obj.payload.role === "user") {
          messageCount += 1;
          firstResponseUser ??= extractCodexText(obj.payload.content);
        }
        if (obj.payload.role === "assistant") {
          messageCount += 1;
          summary ??= extractCodexText(obj.payload.content);
        }
      }
    }

    const firstPrompt = firstUserMessage ?? firstResponseUser;
    const lastPrompt = lastUserMessage ?? firstPrompt;

    sessionId ??= basename(filePath).match(/([0-9a-f]{8,}-[0-9a-f-]{20,})/)?.[1] ?? basename(filePath, ".jsonl");
    upsertSession({
      id: sessionId,
      source: "codex",
      projectPath,
      firstPrompt,
      lastPrompt,
      summary,
      model,
      gitBranch: null,
      messageCount,
      version,
      kind: "interactive",
      entrypoint: "cli",
      startedAt: startedAt ?? new Date().toISOString(),
      lastActiveAt: lastActiveAt ?? startedAt ?? new Date().toISOString(),
      isActive: isRecentlyWritten(filePath) ? 1 : 0,
      filePath,
    });
    setSessionScanState(filePath, fileState.size, fileState.mtime);
    seenIds.push(sessionId);
  });

  deleteMissingByIds("sessions", "codex", seenIds);
  return seenIds.length;
}

function isRecentlyWritten(filePath: string) {
  try {
    return Date.now() - statSync(filePath).mtimeMs <= CODEX_ACTIVE_WINDOW_MS;
  } catch {
    return false;
  }
}

function currentFileState(filePath: string): { size: number; mtime: string } | null {
  try {
    const st = statSync(filePath);
    return { size: st.size, mtime: st.mtime.toISOString() };
  } catch {
    return null;
  }
}
