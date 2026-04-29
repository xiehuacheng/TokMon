import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { resolve } from "path";
import { scanClaudeSessions } from "./claude-sessions.js";
import { scanClaudeSkills } from "./claude-skills.js";
import { scanClaudeSettings } from "./claude-settings.js";
import { scanCodexSessions } from "./codex-sessions.js";
import { scanCodexSkills } from "./codex-skills.js";
import { scanCodexSettings } from "./codex-settings.js";

export interface SourceHomeConfig {
  home: string;
}

export interface AgentMonConfig {
  port: number;
  sources: {
    "claude-code": SourceHomeConfig;
    codex: SourceHomeConfig;
  };
}

let config: AgentMonConfig;

function expandPath(p: string) {
  return resolve(p.replace(/^~/, homedir()));
}

export function loadConfig(): AgentMonConfig {
  const configPath = resolve(process.cwd(), "agentmon.config.json");
  if (existsSync(configPath)) {
    config = JSON.parse(readFileSync(configPath, "utf-8"));
  } else {
    config = {
      port: 3388,
      sources: {
        "claude-code": { home: "~/.claude" },
        codex: { home: "~/.codex" },
      },
    };
  }
  return config;
}

export function getConfig() {
  return config;
}

export function scanAll() {
  const claudeHome = expandPath(config.sources["claude-code"].home);
  const codexHome = expandPath(config.sources.codex.home);

  return [
    scanClaudeSessions(claudeHome),
    scanClaudeSkills(claudeHome),
    scanClaudeSettings(claudeHome),
    scanCodexSessions(codexHome),
    scanCodexSkills(codexHome),
    scanCodexSettings(codexHome),
  ].reduce((sum, count) => sum + count, 0);
}
