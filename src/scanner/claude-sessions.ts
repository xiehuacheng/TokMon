import { readdirSync } from "fs";
import { join } from "path";
import { deleteMissingByIds, upsertSession } from "../db.js";
import { extractClaudeText, processAlive, safeJsonParse, safeReadText } from "./utils.js";

export function scanClaudeSessions(claudeHome: string) {
  const sessionStateDir = join(claudeHome, "sessions");
  const projectsDir = join(claudeHome, "projects");
  const activeSessions = new Set<string>();
  const seenIds: string[] = [];

  try {
    for (const file of readdirSync(sessionStateDir)) {
      if (!file.endsWith(".json")) continue;
      const payload = safeJsonParse(safeReadText(join(sessionStateDir, file)) || "");
      if (payload?.sessionId && typeof payload.pid === "number" && processAlive(payload.pid)) {
        activeSessions.add(payload.sessionId);
      }
    }
  } catch {}

  try {
    for (const project of readdirSync(projectsDir)) {
      const projectDir = join(projectsDir, project);
      for (const file of readdirSync(projectDir)) {
        if (!file.endsWith(".jsonl")) continue;
        const filePath = join(projectDir, file);
        const sessionId = file.replace(/\.jsonl$/, "");
        const text = safeReadText(filePath);
        if (!text) continue;

        let firstPrompt: string | null = null;
        let lastPrompt: string | null = null;
        let summary: string | null = null;
        let model: string | null = null;
        let gitBranch: string | null = null;
        let projectPath: string | null = null;
        let version: string | null = null;
        let kind: string | null = null;
        let entrypoint: string | null = null;
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
          if (typeof obj.cwd === "string") projectPath ??= obj.cwd;
          if (typeof obj.version === "string") version ??= obj.version;
          if (typeof obj.gitBranch === "string") gitBranch ??= obj.gitBranch;
          if (typeof obj.entrypoint === "string") entrypoint ??= obj.entrypoint;
          if (typeof obj.kind === "string") kind ??= obj.kind;

          if (obj.type === "user" && obj.message) {
            messageCount += 1;
            const text = extractClaudeText(obj.message.content);
            if (text && !text.startsWith("<")) {
              firstPrompt ??= text;
              lastPrompt = text;
            }
          }
          if (obj.type === "assistant" && obj.message) {
            messageCount += 1;
            if (typeof obj.message.model === "string") model = obj.message.model;
            summary ??= extractClaudeText(obj.message.content);
          }
        }

        if (messageCount === 0) continue;

        upsertSession({
          id: sessionId,
          source: "claude-code",
          projectPath,
          firstPrompt,
          lastPrompt,
          summary,
          model,
          gitBranch,
          messageCount,
          version,
          kind,
          entrypoint,
          startedAt: startedAt ?? new Date().toISOString(),
          lastActiveAt: lastActiveAt ?? startedAt ?? new Date().toISOString(),
          isActive: activeSessions.has(sessionId) ? 1 : 0,
          filePath,
        });
        seenIds.push(sessionId);
      }
    }
  } catch {}

  deleteMissingByIds("sessions", "claude-code", seenIds);
  return seenIds.length;
}
