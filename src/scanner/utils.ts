import { existsSync, lstatSync, readdirSync, readFileSync, readlinkSync, realpathSync, statSync } from "fs";
import { homedir } from "os";
import { join, resolve } from "path";

export function expandPath(p: string) {
  return resolve(p.replace(/^~/, homedir()));
}

export function safeJsonParse(value: string) {
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

export function safeReadText(filePath: string) {
  try {
    return readFileSync(filePath, "utf-8");
  } catch {
    return null;
  }
}

export function walkFiles(dir: string, visit: (filePath: string) => void) {
  try {
    for (const entry of readdirSync(dir)) {
      const fullPath = join(dir, entry);
      const st = statSync(fullPath);
      if (st.isDirectory()) walkFiles(fullPath, visit);
      else visit(fullPath);
    }
  } catch {}
}

export function processAlive(pid: number) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export function getIsoMtime(filePath: string) {
  try {
    return statSync(filePath).mtime.toISOString();
  } catch {
    return null;
  }
}

export function readSkillMarkdown(dirPath: string) {
  const candidates = [join(dirPath, "SKILL.md"), join(dirPath, "skill.md")];
  for (const filePath of candidates) {
    if (existsSync(filePath)) return safeReadText(filePath);
  }
  return null;
}

export function describeSkill(skillMd: string | null) {
  if (!skillMd) return null;
  const lines = skillMd.split("\n");
  const descriptionLine = lines.find((line) => line.startsWith("description:"));
  if (descriptionLine) return descriptionLine.replace(/^description:\s*/, "").trim();
  const bodyLine = lines.find((line) => line.trim());
  return bodyLine?.trim() || null;
}

export function getSymlinkInfo(path: string) {
  try {
    const st = lstatSync(path);
    if (!st.isSymbolicLink()) return { isSymlink: 0, symlinkTarget: null as string | null, realPath: path, broken: false };
    try {
      const target = realpathSync(path);
      return { isSymlink: 1, symlinkTarget: target, realPath: target, broken: false };
    } catch {
      return { isSymlink: 1, symlinkTarget: readlinkSync(path), realPath: path, broken: true };
    }
  } catch {
    return { isSymlink: 0, symlinkTarget: null as string | null, realPath: path, broken: false };
  }
}

export function extractClaudeText(content: unknown): string | null {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    for (const part of content) {
      if (typeof part === "string") return part;
      if (part && typeof part === "object" && "text" in part && typeof part.text === "string") return part.text;
    }
  }
  return null;
}

export function extractCodexText(content: unknown): string | null {
  if (!Array.isArray(content)) return null;
  for (const part of content) {
    if (part && typeof part === "object" && "text" in part && typeof part.text === "string") return part.text;
  }
  return null;
}
