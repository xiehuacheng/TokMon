import { existsSync, readFileSync } from "fs";
import { join } from "path";
import { parse } from "smol-toml";
import { deleteMissingByIds, upsertMcp, upsertPlugin } from "../db.js";
import { getIsoMtime } from "./utils.js";

export function scanCodexSettings(codexHome: string) {
  const configPath = join(codexHome, "config.toml");
  if (!existsSync(configPath)) {
    deleteMissingByIds("mcp_servers", "codex", []);
    deleteMissingByIds("plugins", "codex", []);
    return 0;
  }

  let count = 0;
  const raw = readFileSync(configPath, "utf-8");
  const config = parse(raw) as Record<string, unknown>;
  const scannedAt = getIsoMtime(configPath) ?? new Date().toISOString();

  const mcpServers = config.mcp_servers && typeof config.mcp_servers === "object" ? config.mcp_servers as Record<string, unknown> : {};
  const mcpIds: string[] = [];
  for (const [name, value] of Object.entries(mcpServers)) {
    const v = value && typeof value === "object" ? value as Record<string, unknown> : {};
    const id = `codex:${name}`;
    upsertMcp({
      id,
      source: "codex",
      name,
      url: typeof v.url === "string" ? v.url : null,
      command: typeof v.command === "string" ? v.command : null,
      args: v.args ? JSON.stringify(v.args) : null,
      env: v.env ? JSON.stringify(v.env) : null,
      enabled: 1,
      configRaw: JSON.stringify(v),
      scannedAt,
    });
    mcpIds.push(id);
    count += 1;
  }
  deleteMissingByIds("mcp_servers", "codex", mcpIds);

  const plugins = config.plugins && typeof config.plugins === "object" ? config.plugins as Record<string, unknown> : {};
  const pluginIds: string[] = [];
  for (const [name, value] of Object.entries(plugins)) {
    const v = value && typeof value === "object" ? value as Record<string, unknown> : {};
    const id = `codex:${name}`;
    upsertPlugin({
      id,
      source: "codex",
      name,
      version: null,
      enabled: v.enabled === false ? 0 : 1,
      scannedAt,
    });
    pluginIds.push(id);
    count += 1;
  }
  deleteMissingByIds("plugins", "codex", pluginIds);

  return count;
}
