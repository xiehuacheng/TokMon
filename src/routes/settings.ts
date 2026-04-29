import { Hono } from "hono";
import { existsSync, readFileSync, writeFileSync } from "fs";
import { join } from "path";
import { parse, stringify } from "smol-toml";
import { safeJsonParse } from "../scanner/utils.js";
import { getDb } from "../db.js";

export const settingsRoutes = new Hono();

settingsRoutes.get("/claude", (c) => {
  const settingsPath = join(process.env.HOME!, ".claude", "settings.json");
  if (!existsSync(settingsPath)) return c.json({});
  const settings = safeJsonParse(readFileSync(settingsPath, "utf-8")) || {};
  const { env, ...safe } = settings;
  return c.json(safe);
});

settingsRoutes.put("/claude", async (c) => {
  const settingsPath = join(process.env.HOME!, ".claude", "settings.json");
  const existing = existsSync(settingsPath) ? safeJsonParse(readFileSync(settingsPath, "utf-8")) || {} : {};
  const body = await c.req.json();
  const merged = { ...existing, ...body, env: existing.env };
  writeFileSync(settingsPath, JSON.stringify(merged, null, 2));
  return c.json({ ok: true });
});

settingsRoutes.get("/codex", (c) => {
  const configPath = join(process.env.HOME!, ".codex", "config.toml");
  if (!existsSync(configPath)) return c.json({});
  const raw = readFileSync(configPath, "utf-8");
  const config = parse(raw) as Record<string, unknown>;
  return c.json(config);
});

settingsRoutes.put("/codex", async (c) => {
  const configPath = join(process.env.HOME!, ".codex", "config.toml");
  const body = await c.req.json();
  writeFileSync(configPath, stringify(body));
  return c.json({ ok: true });
});

settingsRoutes.get("/plugins", (c) => {
  const db = getDb();
  const rows = db.prepare("SELECT * FROM plugins ORDER BY source, name").all();
  return c.json(rows);
});
