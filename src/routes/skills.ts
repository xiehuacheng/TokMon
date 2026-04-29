import { Hono } from "hono";
import { getDb, upsertSkill } from "../db.js";
import { existsSync, mkdirSync, renameSync, symlinkSync, unlinkSync, lstatSync } from "fs";
import { join, dirname } from "path";
import { describeSkill, readSkillMarkdown } from "../scanner/utils.js";

export const skillsRoutes = new Hono();

skillsRoutes.get("/", (c) => {
  const db = getDb();
  const source = c.req.query("source");
  let rows;
  if (source) {
    rows = db.prepare("SELECT * FROM skills WHERE source = ? ORDER BY name").all(source);
  } else {
    rows = db.prepare("SELECT * FROM skills ORDER BY source, name").all();
  }
  return c.json(rows);
});

skillsRoutes.post("/cleanup-broken", (c) => {
  const db = getDb();
  const rows = db.prepare("SELECT * FROM skills WHERE description LIKE 'Broken symlink %'").all() as Record<string, unknown>[];
  const removed: string[] = [];

  for (const row of rows) {
    const path = row.path as string;
    try {
      const st = lstatSync(path);
      if (st.isSymbolicLink()) unlinkSync(path);
    } catch {}
    db.prepare("DELETE FROM skills WHERE id = ?").run(row.id);
    removed.push(row.name as string);
  }

  return c.json({ ok: true, removedCount: removed.length, removed });
});

skillsRoutes.get("/:id", (c) => {
  const db = getDb();
  const row = db.prepare("SELECT * FROM skills WHERE id = ?").get(c.req.param("id"));
  if (!row) return c.json({ error: "not found" }, 404);
  return c.json(row);
});

skillsRoutes.patch("/:id", async (c) => {
  const db = getDb();
  const id = c.req.param("id");
  const row = db.prepare("SELECT * FROM skills WHERE id = ?").get(id) as Record<string, unknown> | undefined;
  if (!row) return c.json({ error: "not found" }, 404);

  const body = await c.req.json<{ enabled?: boolean }>();
  if (body.enabled !== undefined) {
    if ((row.scope || "user") !== "user") {
      return c.json({ error: "read-only skill" }, 409);
    }
    const currentPath = row.path as string;
    const dir = dirname(currentPath);
    const name = row.name as string;
    if (body.enabled) {
      const disabledPath = join(dir, `.disabled-${name}`);
      if (existsSync(disabledPath)) renameSync(disabledPath, join(dir, name));
    } else {
      const enabledPath = join(dir, name);
      if (existsSync(enabledPath)) renameSync(enabledPath, join(dir, `.disabled-${name}`));
    }
    db.prepare("UPDATE skills SET enabled = ? WHERE id = ?").run(body.enabled ? 1 : 0, id);
  }
  return c.json({ ok: true });
});

skillsRoutes.post("/", async (c) => {
  const body = await c.req.json<{ source: string; name: string; targetPath: string }>();
  const homeDir = body.source === "codex" ? `${process.env.HOME}/.codex` : `${process.env.HOME}/.claude`;
  const skillsDir = join(homeDir, "skills");
  if (!existsSync(skillsDir)) mkdirSync(skillsDir, { recursive: true });
  const linkPath = join(skillsDir, body.name);
  if (existsSync(linkPath)) return c.json({ error: "skill already exists" }, 409);
  symlinkSync(body.targetPath, linkPath);
  const skillMd = readSkillMarkdown(body.targetPath);
  upsertSkill({
    id: `${body.source}:${body.name}`,
    source: body.source,
    name: body.name,
    description: describeSkill(skillMd),
    path: linkPath,
    isSymlink: 1,
    symlinkTarget: body.targetPath,
    skillMd,
    enabled: 1,
    scannedAt: new Date().toISOString(),
  });
  return c.json({ ok: true });
});

skillsRoutes.delete("/:id", (c) => {
  const db = getDb();
  const id = c.req.param("id");
  const row = db.prepare("SELECT * FROM skills WHERE id = ?").get(id) as Record<string, unknown> | undefined;
  if (!row) return c.json({ error: "not found" }, 404);
  if ((row.scope || "user") !== "user") {
    return c.json({ error: "read-only skill" }, 409);
  }

  const path = row.path as string;
  try {
    const st = lstatSync(path);
    if (st.isSymbolicLink()) unlinkSync(path);
  } catch {}
  db.prepare("DELETE FROM skills WHERE id = ?").run(id);
  return c.json({ ok: true });
});
