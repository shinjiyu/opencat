import { randomBytes } from "node:crypto";
import type Database from "better-sqlite3";
import { getDb } from "./schema.js";

export interface TokenRecord {
  token: string;
  status: string;
  platform: string;
  install_id: string;
  version: string | null;
  daily_limit: number;
  monthly_limit: number;
  meta: string | null;
  created_at: string;
  last_used_at: string | null;
}

export interface UsageRecord {
  token: string;
  date: string;
  request_count: number;
  prompt_tokens: number;
  completion_tokens: number;
}

export function generateToken(): string {
  return "ocp_" + randomBytes(16).toString("hex");
}

export function createToken(params: {
  platform: string;
  install_id: string;
  version?: string;
  meta?: Record<string, unknown>;
}): TokenRecord {
  const db = getDb();
  const token = generateToken();
  const now = new Date().toISOString();
  const dailyLimit = Number(process.env.DEFAULT_DAILY_LIMIT ?? 100);
  const monthlyLimit = Number(process.env.DEFAULT_MONTHLY_LIMIT ?? 3000);

  db.prepare(`
    INSERT INTO tokens (token, platform, install_id, version, daily_limit, monthly_limit, meta, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    token,
    params.platform,
    params.install_id,
    params.version ?? null,
    dailyLimit,
    monthlyLimit,
    params.meta ? JSON.stringify(params.meta) : null,
    now,
  );

  return {
    token,
    status: "active",
    platform: params.platform,
    install_id: params.install_id,
    version: params.version ?? null,
    daily_limit: dailyLimit,
    monthly_limit: monthlyLimit,
    meta: params.meta ? JSON.stringify(params.meta) : null,
    created_at: now,
    last_used_at: null,
  };
}

export function findToken(token: string): TokenRecord | undefined {
  const db = getDb();
  return db.prepare("SELECT * FROM tokens WHERE token = ?").get(token) as TokenRecord | undefined;
}

export function updateToken(
  token: string,
  updates: { status?: string; daily_limit?: number; monthly_limit?: number },
): TokenRecord | undefined {
  const db = getDb();
  const fields: string[] = [];
  const values: unknown[] = [];

  if (updates.status !== undefined) {
    fields.push("status = ?");
    values.push(updates.status);
  }
  if (updates.daily_limit !== undefined) {
    fields.push("daily_limit = ?");
    values.push(updates.daily_limit);
  }
  if (updates.monthly_limit !== undefined) {
    fields.push("monthly_limit = ?");
    values.push(updates.monthly_limit);
  }

  if (fields.length === 0) return findToken(token);

  values.push(token);
  db.prepare(`UPDATE tokens SET ${fields.join(", ")} WHERE token = ?`).run(...values);

  return findToken(token);
}

export function deleteToken(token: string): boolean {
  const db = getDb();
  const result = db.prepare("DELETE FROM tokens WHERE token = ?").run(token);
  return result.changes > 0;
}

export function listTokens(params: {
  page?: number;
  limit?: number;
  status?: string;
}): { tokens: TokenRecord[]; total: number } {
  const db = getDb();
  const page = params.page ?? 1;
  const limit = params.limit ?? 20;
  const offset = (page - 1) * limit;

  let where = "";
  const whereValues: unknown[] = [];
  if (params.status) {
    where = "WHERE status = ?";
    whereValues.push(params.status);
  }

  const total = (
    db.prepare(`SELECT COUNT(*) as count FROM tokens ${where}`).get(...whereValues) as { count: number }
  ).count;

  const tokens = db
    .prepare(`SELECT * FROM tokens ${where} ORDER BY created_at DESC LIMIT ? OFFSET ?`)
    .all(...whereValues, limit, offset) as TokenRecord[];

  return { tokens, total };
}

export function touchToken(token: string): void {
  const db = getDb();
  db.prepare("UPDATE tokens SET last_used_at = ? WHERE token = ?").run(new Date().toISOString(), token);
}

function todayUTC(): string {
  return new Date().toISOString().slice(0, 10);
}

function monthStartUTC(): string {
  const now = new Date();
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}-01`;
}

export function getUsageToday(token: string): UsageRecord | undefined {
  const db = getDb();
  return db.prepare("SELECT * FROM usage WHERE token = ? AND date = ?").get(token, todayUTC()) as
    | UsageRecord
    | undefined;
}

export function getUsageMonth(token: string): { request_count: number; prompt_tokens: number; completion_tokens: number } {
  const db = getDb();
  const start = monthStartUTC();
  const result = db
    .prepare(
      `SELECT COALESCE(SUM(request_count), 0) as request_count,
              COALESCE(SUM(prompt_tokens), 0) as prompt_tokens,
              COALESCE(SUM(completion_tokens), 0) as completion_tokens
       FROM usage WHERE token = ? AND date >= ?`,
    )
    .get(token, start) as { request_count: number; prompt_tokens: number; completion_tokens: number };
  return result;
}

export function incrementUsage(
  token: string,
  promptTokens: number,
  completionTokens: number,
): void {
  const db = getDb();
  const date = todayUTC();

  db.prepare(`
    INSERT INTO usage (token, date, request_count, prompt_tokens, completion_tokens)
    VALUES (?, ?, 1, ?, ?)
    ON CONFLICT(token, date) DO UPDATE SET
      request_count = request_count + 1,
      prompt_tokens = prompt_tokens + excluded.prompt_tokens,
      completion_tokens = completion_tokens + excluded.completion_tokens
  `).run(token, date, promptTokens, completionTokens);
}
