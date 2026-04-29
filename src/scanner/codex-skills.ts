import { existsSync, readdirSync } from "fs";
import { basename, dirname, join } from "path";
import { deleteMissingByIds, upsertSkill } from "../db.js";
import { describeSkill, getSymlinkInfo, readSkillMarkdown, walkFiles } from "./utils.js";

export function scanCodexSkills(codexHome: string) {
  const skillsDir = join(codexHome, "skills");
  const seenIds: string[] = [];
  if (!existsSync(skillsDir)) return scanCodexExtraSkills(codexHome, seenIds);

  for (const entry of readdirSync(skillsDir)) {
    const path = join(skillsDir, entry);
    if (entry === ".system") {
      scanSkillMarkdownTree(path, "codex", "system", seenIds);
      continue;
    }
    const { isSymlink, symlinkTarget, realPath, broken } = getSymlinkInfo(path);
    const skillMd = broken ? null : readSkillMarkdown(realPath);
    if (!broken && !skillMd) continue;
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
      scope: "user",
      skillMd,
      enabled: broken ? 0 : enabled,
      scannedAt: new Date().toISOString(),
    });
    seenIds.push(id);
  }

  scanCodexExtraSkills(codexHome, seenIds);
  deleteMissingByIds("skills", "codex", seenIds);
  return seenIds.length;
}

function scanCodexExtraSkills(codexHome: string, seenIds: string[]) {
  let count = 0;
  count += scanSkillMarkdownTree(join(codexHome, "plugins", "cache"), "codex", "plugin", seenIds);
  count += scanSkillMarkdownTree(join(codexHome, "vendor_imports", "skills", "skills", ".curated"), "codex", "curated", seenIds);
  return count;
}

function scanSkillMarkdownTree(root: string, source: string, scope: string, seenIds: string[]) {
  if (!existsSync(root)) return 0;

  let count = 0;
  walkFiles(root, (filePath) => {
    if (!filePath.endsWith("/SKILL.md") && !filePath.endsWith("/skill.md")) return;
    const skillDir = dirname(filePath);
    const name = basename(skillDir);
    const id = `${source}:${scope}:${name}:${skillDir}`;
    const skillMd = readSkillMarkdown(skillDir);
    upsertSkill({
      id,
      source,
      name,
      description: describeSkill(skillMd),
      path: skillDir,
      isSymlink: 0,
      symlinkTarget: null,
      scope,
      skillMd,
      enabled: 1,
      scannedAt: new Date().toISOString(),
    });
    seenIds.push(id);
    count++;
  });
  return count;
}
