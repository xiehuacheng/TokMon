import { Hono } from "hono";
import { getDb, upsertMcp } from "../db.js";
import { existsSync, readFileSync, writeFileSync } from "fs";
import { join } from "path";
import { parse, stringify } from "smol-toml";
import { safeJsonParse } from "../scanner/utils.js";

export const mcpRoutes = new Hono();

mcpRoutes.get("/", (c) => {
  const db = getDb();
  const source = c.req.query("source");
  let rows;
  if (source) {
    rows = db.prepare("SELECT * FROM mcp_servers WHERE source = ? ORDER BY name").all(source);
  } else {
    rows = db.prepare("SELECT * FROM mcp_servers ORDER BY source, name").all();
  }
  return c.json(rows);
});

mcpRoutes.get("/:id", (c) => {
  const db = getDb();
  const row = db.prepare("SELECT * FROM mcp_servers WHERE id = ?").get(c.req.param("id"));
  if (!row) return c.json({ error: "not found" }, 404);
  return c.json(row);
});

mcpRoutes.post("/", async (c) => {
  const body = await c.req.json<{ source: string; name: string; url?: string; command?: string; args?: string[] }>();
  if (body.source === "codex") {
    const configPath = join(process.env.HOME!, ".codex", "config.toml");
    const raw = existsSync(configPath) ? readFileSync(configPath, "utf-8") : "";
    const config = raw ? parse(raw) as Record<string, unknown> : {};
    if (!config.mcp_servers) config.mcp_servers = {};
    (config.mcp_servers as Record<string, unknown>)[body.name] = body.url ? { url: body.url } : { command: body.command, args: body.args || [] };
    writeFileSync(configPath, stringify(config));
  } else {
    const settingsPath = join(process.env.HOME!, ".claude", "settings.json");
    const settings = existsSync(settingsPath) ? safeJsonParse(readFileSync(settingsPath, "utf-8")) || {} : {};
    if (!settings.mcpServers) settings.mcpServers = {};
    settings.mcpServers[body.name] = body.url ? { url: body.url } : { command: body.command, args: body.args || [] };
    writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
  }
  upsertMcp({
    id: `${body.source}:${body.name}`,
    source: body.source,
    name: body.name,
    url: body.url ?? null,
    command: body.command ?? null,
    args: body.args ? JSON.stringify(body.args) : null,
    env: null,
    enabled: 1,
    configRaw: JSON.stringify(body.url ? { url: body.url } : { command: body.command, args: body.args || [] }),
    scannedAt: new Date().toISOString(),
  });
  return c.json({ ok: true });
});

mcpRoutes.patch("/:id", async (c) => {
  const db = getDb();
  const id = c.req.param("id");
  const row = db.prepare("SELECT * FROM mcp_servers WHERE id = ?").get(id) as Record<string, unknown> | undefined;
  if (!row) return c.json({ error: "not found" }, 404);
  const body = await c.req.json<{ enabled?: boolean; url?: string; command?: string; args?: string[] }>();
  db.prepare("UPDATE mcp_servers SET enabled = ? WHERE id = ?").run(body.enabled === false ? 0 : 1, id);
  return c.json({ ok: true });
});

mcpRoutes.delete("/:id", (c) => {
  const db = getDb();
  const id = c.req.param("id");
  const row = db.prepare("SELECT * FROM mcp_servers WHERE id = ?").get(id) as Record<string, unknown> | undefined;
  if (!row) return c.json({ error: "not found" }, 404);

  const source = row.source as string;
  const name = row.name as string;
  if (source === "codex") {
    const configPath = join(process.env.HOME!, ".codex", "config.toml");
    if (existsSync(configPath)) {
      const config = parse(readFileSync(configPath, "utf-8")) as Record<string, unknown>;
      if (config.mcp_servers && typeof config.mcp_servers === "object") {
        delete (config.mcp_servers as Record<string, unknown>)[name];
        writeFileSync(configPath, stringify(config));
      }
    }
  } else {
    const settingsPath = join(process.env.HOME!, ".claude", "settings.json");
    if (existsSync(settingsPath)) {
      const settings = safeJsonParse(readFileSync(settingsPath, "utf-8")) || {};
      if (settings.mcpServers) {
        delete settings.mcpServers[name];
        writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
      }
    }
  }
  db.prepare("DELETE FROM mcp_servers WHERE id = ?").run(id);
  return c.json({ ok: true });
});
