import { existsSync, readdirSync } from "fs";
import { join } from "path";
import { deleteMissingByIds, upsertSkill } from "../db.js";
import { describeSkill, getSymlinkInfo, readSkillMarkdown } from "./utils.js";

export function scanClaudeSkills(claudeHome: string) {
  const skillsDir = join(claudeHome, "skills");
  const seenIds: string[] = [];
  if (!existsSync(skillsDir)) return 0;

  for (const entry of readdirSync(skillsDir)) {
    const path = join(skillsDir, entry);
    const { isSymlink, symlinkTarget, realPath, broken } = getSymlinkInfo(path);
    const skillMd = broken ? null : readSkillMarkdown(realPath);
    const name = entry.startsWith(".disabled-") ? entry.slice(10) : entry;
    const enabled = entry.startsWith(".disabled-") ? 0 : 1;
    const id = `claude-code:${name}`;
    upsertSkill({
      id,
      source: "claude-code",
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

  deleteMissingByIds("skills", "claude-code", seenIds);
  return seenIds.length;
}
