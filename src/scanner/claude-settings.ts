import { existsSync, readFileSync } from "fs";
import { join } from "path";
import { deleteMissingByIds, upsertMcp, upsertPlugin } from "../db.js";
import { getIsoMtime, safeJsonParse } from "./utils.js";

export function scanClaudeSettings(claudeHome: string) {
  let count = 0;
  const settingsPath = join(claudeHome, "settings.json");
  const pluginsPath = join(claudeHome, "plugins", "installed_plugins.json");

  if (existsSync(settingsPath)) {
    const settings = safeJsonParse(readFileSync(settingsPath, "utf-8"));
    const mcpServers = settings?.mcpServers && typeof settings.mcpServers === "object" ? settings.mcpServers : {};
    const ids: string[] = [];
    for (const [name, value] of Object.entries(mcpServers)) {
      const id = `claude-code:${name}`;
      upsertMcp({
        id,
        source: "claude-code",
        name,
        url: typeof value === "object" && value && "url" in value && typeof value.url === "string" ? value.url : null,
        command: typeof value === "object" && value && "command" in value && typeof value.command === "string" ? value.command : null,
        args: JSON.stringify(typeof value === "object" && value && "args" in value ? value.args : []),
        env: JSON.stringify(typeof value === "object" && value && "env" in value ? value.env : {}),
        enabled: !(typeof value === "object" && value && "disabled" in value && value.disabled === true) ? 1 : 0,
        configRaw: JSON.stringify(value),
        scannedAt: getIsoMtime(settingsPath) ?? new Date().toISOString(),
      });
      ids.push(id);
      count += 1;
    }
    deleteMissingByIds("mcp_servers", "claude-code", ids);
  } else {
    deleteMissingByIds("mcp_servers", "claude-code", []);
  }

  if (existsSync(pluginsPath)) {
    const payload = safeJsonParse(readFileSync(pluginsPath, "utf-8"));
    const ids: string[] = [];
    const plugins = payload?.plugins && typeof payload.plugins === "object" ? payload.plugins : {};
    for (const [name, installs] of Object.entries(plugins)) {
      const first = Array.isArray(installs) ? installs[0] : null;
      const id = `claude-code:${name}`;
      upsertPlugin({
        id,
        source: "claude-code",
        name,
        version: first && typeof first === "object" && "version" in first && typeof first.version === "string" ? first.version : null,
        enabled: 1,
        scannedAt: first && typeof first === "object" && "lastUpdated" in first && typeof first.lastUpdated === "string" ? first.lastUpdated : new Date().toISOString(),
      });
      ids.push(id);
      count += 1;
    }
    deleteMissingByIds("plugins", "claude-code", ids);
  } else {
    deleteMissingByIds("plugins", "claude-code", []);
  }

  return count;
}
