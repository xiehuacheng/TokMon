import { mkdirSync } from "fs";
import { resolve } from "path";

let cachedDataDir: string | undefined;

export function getDataDir(): string {
  if (cachedDataDir) return cachedDataDir;

  const configuredDir = process.env.AGENTMON_DATA_DIR?.trim();
  cachedDataDir = configuredDir ? resolve(configuredDir) : process.cwd();
  mkdirSync(cachedDataDir, { recursive: true });
  return cachedDataDir;
}

export function dataPath(fileName: string): string {
  return resolve(getDataDir(), fileName);
}
