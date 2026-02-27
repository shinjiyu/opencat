import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";

const DB_PATH = process.env.DB_PATH ?? join(process.cwd(), "data", "db.json");

export interface DbData {
  tokens: Record<string, import("./tokens.js").TokenRecord>;
  usage: Record<string, import("./tokens.js").UsageRecord>;
}

let _data: DbData | null = null;

export function getDb(): DbData {
  if (!_data) {
    mkdirSync(dirname(DB_PATH), { recursive: true });
    if (existsSync(DB_PATH)) {
      _data = JSON.parse(readFileSync(DB_PATH, "utf-8"));
    } else {
      _data = { tokens: {}, usage: {} };
      saveDb();
    }
  }
  return _data!;
}

export function saveDb(): void {
  if (!_data) return;
  mkdirSync(dirname(DB_PATH), { recursive: true });
  writeFileSync(DB_PATH, JSON.stringify(_data, null, 2));
}

export function initDb(): void {
  getDb();
  console.log(`Database initialized at ${DB_PATH}`);
}
