import { existsSync, readdirSync } from "fs";
import { basename, dirname, join } from "path";
import { deleteMissingByIds, upsertSkill } from "../db.js";
import { describeSkill, getSymlinkInfo, readSkillMarkdown, walkFiles } from "./utils.js";

export function scanClaudeSkills(claudeHome: string) {
  const skillsDir = join(claudeHome, "skills");
  const seenIds: string[] = [];
  if (!existsSync(skillsDir)) return scanClaudePluginSkills(claudeHome, seenIds);

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
      scope: "user",
      skillMd,
      enabled: broken ? 0 : enabled,
      scannedAt: new Date().toISOString(),
    });
    seenIds.push(id);
  }

  scanClaudePluginSkills(claudeHome, seenIds);
  deleteMissingByIds("skills", "claude-code", seenIds);
  return seenIds.length;
}

function scanClaudePluginSkills(claudeHome: string, seenIds: string[]) {
  const pluginsDir = join(claudeHome, "plugins");
  if (!existsSync(pluginsDir)) return 0;

  let count = 0;
  walkFiles(pluginsDir, (filePath) => {
    if (!filePath.endsWith("/SKILL.md") && !filePath.endsWith("/skill.md")) return;
    const skillDir = dirname(filePath);
    const name = basename(skillDir);
    const id = `claude-code:plugin:${name}:${skillDir}`;
    const skillMd = readSkillMarkdown(skillDir);
    upsertSkill({
      id,
      source: "claude-code",
      name,
      description: describeSkill(skillMd),
      path: skillDir,
      isSymlink: 0,
      symlinkTarget: null,
      scope: "plugin",
      skillMd,
      enabled: 1,
      scannedAt: new Date().toISOString(),
    });
    seenIds.push(id);
    count++;
  });
  return count;
}
