import { randomBytes } from "node:crypto";
import { getDb, saveDb } from "./schema.js";

export interface TokenRecord {
  token: string;
  status: string;
  platform: string;
  install_id: string;
  version: string | null;
  daily_limit: number;
  monthly_limit: number;
  meta: string | null;
  tunnel_url: string | null;
  tunnel_updated_at: string | null;
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
  return "occ_" + randomBytes(16).toString("hex");
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

  const record: TokenRecord = {
    token,
    status: "active",
    platform: params.platform,
    install_id: params.install_id,
    version: params.version ?? null,
    daily_limit: dailyLimit,
    monthly_limit: monthlyLimit,
    meta: params.meta ? JSON.stringify(params.meta) : null,
    tunnel_url: null,
    tunnel_updated_at: null,
    created_at: now,
    last_used_at: null,
  };

  db.tokens[token] = record;
  saveDb();
  return record;
}

export function findToken(token: string): TokenRecord | undefined {
  return getDb().tokens[token];
}

export function updateToken(
  token: string,
  updates: { status?: string; daily_limit?: number; monthly_limit?: number },
): TokenRecord | undefined {
  const db = getDb();
  const record = db.tokens[token];
  if (!record) return undefined;

  if (updates.status !== undefined) record.status = updates.status;
  if (updates.daily_limit !== undefined) record.daily_limit = updates.daily_limit;
  if (updates.monthly_limit !== undefined) record.monthly_limit = updates.monthly_limit;

  saveDb();
  return record;
}

export function deleteToken(token: string): boolean {
  const db = getDb();
  if (!db.tokens[token]) return false;
  delete db.tokens[token];
  // Clean up usage entries for this token
  for (const key of Object.keys(db.usage)) {
    if (key.startsWith(token + "|")) {
      delete db.usage[key];
    }
  }
  saveDb();
  return true;
}

export function listTokens(params: {
  page?: number;
  limit?: number;
  status?: string;
}): { tokens: TokenRecord[]; total: number } {
  const db = getDb();
  let all = Object.values(db.tokens);

  if (params.status) {
    all = all.filter((t) => t.status === params.status);
  }

  all.sort((a, b) => b.created_at.localeCompare(a.created_at));

  const total = all.length;
  const page = params.page ?? 1;
  const limit = params.limit ?? 20;
  const offset = (page - 1) * limit;

  return { tokens: all.slice(offset, offset + limit), total };
}

export function touchToken(token: string): void {
  const db = getDb();
  if (db.tokens[token]) {
    db.tokens[token].last_used_at = new Date().toISOString();
    saveDb();
  }
}

export function setTunnelUrl(token: string, tunnelUrl: string): TokenRecord | undefined {
  const db = getDb();
  const record = db.tokens[token];
  if (!record) return undefined;
  record.tunnel_url = tunnelUrl;
  record.tunnel_updated_at = new Date().toISOString();
  saveDb();
  return record;
}

export function clearTunnelUrl(token: string): boolean {
  const db = getDb();
  const record = db.tokens[token];
  if (!record) return false;
  record.tunnel_url = null;
  record.tunnel_updated_at = null;
  saveDb();
  return true;
}

function todayUTC(): string {
  return new Date().toISOString().slice(0, 10);
}

function monthStartUTC(): string {
  const now = new Date();
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}-01`;
}

function usageKey(token: string, date: string): string {
  return `${token}|${date}`;
}

export function getUsageToday(token: string): UsageRecord | undefined {
  return getDb().usage[usageKey(token, todayUTC())];
}

export function getUsageMonth(token: string): { request_count: number; prompt_tokens: number; completion_tokens: number } {
  const db = getDb();
  const start = monthStartUTC();
  let request_count = 0;
  let prompt_tokens = 0;
  let completion_tokens = 0;

  for (const [key, record] of Object.entries(db.usage)) {
    if (key.startsWith(token + "|") && record.date >= start) {
      request_count += record.request_count;
      prompt_tokens += record.prompt_tokens;
      completion_tokens += record.completion_tokens;
    }
  }

  return { request_count, prompt_tokens, completion_tokens };
}

export function incrementUsage(
  token: string,
  promptTokens: number,
  completionTokens: number,
): void {
  const db = getDb();
  const date = todayUTC();
  const key = usageKey(token, date);

  if (db.usage[key]) {
    db.usage[key].request_count += 1;
    db.usage[key].prompt_tokens += promptTokens;
    db.usage[key].completion_tokens += completionTokens;
  } else {
    db.usage[key] = {
      token,
      date,
      request_count: 1,
      prompt_tokens: promptTokens,
      completion_tokens: completionTokens,
    };
  }
  saveDb();
}
