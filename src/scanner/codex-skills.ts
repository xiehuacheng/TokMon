import { existsSync, readdirSync } from "fs";
import { join } from "path";
import { deleteMissingByIds, upsertSkill } from "../db.js";
import { describeSkill, getSymlinkInfo, readSkillMarkdown } from "./utils.js";

export function scanCodexSkills(codexHome: string) {
  const skillsDir = join(codexHome, "skills");
  const seenIds: string[] = [];
  if (!existsSync(skillsDir)) return 0;

  for (const entry of readdirSync(skillsDir)) {
    if (entry === ".system") continue;
    const path = join(skillsDir, entry);
    const { isSymlink, symlinkTarget, realPath, broken } = getSymlinkInfo(path);
    const skillMd = broken ? null : readSkillMarkdown(realPath);
    const name = entry.startsWith(".disabled-") ? entry.slice(10) : entry;
    const enabled = entry.startsWith(".disabled-") ? 0 : 1;
    const id = `codex:${name}`;
    upsertSkill({
      id,
      source: "codex",
      name,
      description: broken ? `Broken symlink → ${symlinkTarget}` : describeSkill(skillMd),
      path,
      isSymlink,
      symlinkTarget,
      skillMd,
      enabled: broken ? 0 : enabled,
      scannedAt: new Date().toISOString(),
    });
    seenIds.push(id);
  }

  deleteMissingByIds("skills", "codex", seenIds);
  return seenIds.length;
}
