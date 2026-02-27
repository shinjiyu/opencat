import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";

const DB_PATH = process.env.DB_PATH ?? join(process.cwd(), "data", "portable.db");

let _db: Database.Database | null = null;

export function getDb(): Database.Database {
  if (!_db) {
    mkdirSync(dirname(DB_PATH), { recursive: true });
    _db = new Database(DB_PATH);
    _db.pragma("journal_mode = WAL");
    _db.pragma("foreign_keys = ON");
  }
  return _db;
}

export function initDb(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS tokens (
      token          TEXT PRIMARY KEY,
      status         TEXT NOT NULL DEFAULT 'active',
      platform       TEXT NOT NULL,
      install_id     TEXT NOT NULL,
      version        TEXT,
      daily_limit    INTEGER NOT NULL DEFAULT 100,
      monthly_limit  INTEGER NOT NULL DEFAULT 3000,
      meta           TEXT,
      created_at     TEXT NOT NULL,
      last_used_at   TEXT
    );

    CREATE TABLE IF NOT EXISTS usage (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      token             TEXT NOT NULL,
      date              TEXT NOT NULL,
      request_count     INTEGER NOT NULL DEFAULT 0,
      prompt_tokens     INTEGER NOT NULL DEFAULT 0,
      completion_tokens INTEGER NOT NULL DEFAULT 0,
      UNIQUE(token, date),
      FOREIGN KEY (token) REFERENCES tokens(token) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_usage_token_date ON usage(token, date);
  `);
}
