import type { Context, Next } from "hono";
import { findToken, getUsageToday, getUsageMonth, touchToken } from "../db/tokens.js";

/**
 * Extract token from Authorization header or URL query param.
 * Header takes precedence per protocol spec §2.1.
 */
export function extractToken(c: Context): string | null {
  const authHeader = c.req.header("Authorization");
  if (authHeader?.startsWith("Bearer ")) {
    return authHeader.slice(7).trim();
  }
  const queryToken = c.req.query("token");
  return queryToken?.trim() || null;
}

/** Sliding-window per-minute rate limiter (in-memory). */
const RPM_LIMIT = Number(process.env.RPM_LIMIT ?? 20);
const rpmBuckets = new Map<string, number[]>();

function checkRateLimit(token: string): { allowed: boolean; retryAfterMs: number } {
  const now = Date.now();
  const windowMs = 60_000;
  let timestamps = rpmBuckets.get(token);
  if (!timestamps) {
    timestamps = [];
    rpmBuckets.set(token, timestamps);
  }
  // Prune entries older than the window
  while (timestamps.length > 0 && timestamps[0] <= now - windowMs) {
    timestamps.shift();
  }
  if (timestamps.length >= RPM_LIMIT) {
    const retryAfterMs = timestamps[0] + windowMs - now;
    return { allowed: false, retryAfterMs };
  }
  timestamps.push(now);
  return { allowed: true, retryAfterMs: 0 };
}

/**
 * Middleware: validate token, enforce quota + per-minute rate limit.
 * Sets c.set("tokenRecord", record) on success.
 */
export async function tokenAuth(c: Context, next: Next): Promise<Response | void> {
  const token = extractToken(c);
  if (!token) {
    return c.json({ error: { code: "UNAUTHORIZED", message: "Missing token" } }, 401);
  }

  const record = findToken(token);
  if (!record) {
    return c.json({ error: { code: "UNAUTHORIZED", message: "Invalid token" } }, 401);
  }

  if (record.status === "disabled") {
    return c.json({ error: { code: "TOKEN_DISABLED", message: "Token has been disabled" } }, 403);
  }

  // Per-minute rate limit
  const rl = checkRateLimit(token);
  if (!rl.allowed) {
    c.header("Retry-After", String(Math.ceil(rl.retryAfterMs / 1000)));
    return c.json(
      { error: { code: "RATE_LIMITED", message: `Rate limit exceeded (${RPM_LIMIT} req/min). Retry after ${Math.ceil(rl.retryAfterMs / 1000)}s.` } },
      429,
    );
  }

  // Daily quota
  const usageToday = getUsageToday(token);
  const dailyUsed = usageToday?.request_count ?? 0;
  if (dailyUsed >= record.daily_limit) {
    return c.json(
      { error: { code: "QUOTA_EXCEEDED", message: "Daily quota exceeded. Resets at 00:00 UTC.", type: "insufficient_quota" } },
      429,
    );
  }

  // Monthly quota
  const usageMonth = getUsageMonth(token);
  if (usageMonth.request_count >= record.monthly_limit) {
    return c.json(
      { error: { code: "QUOTA_EXCEEDED", message: "Monthly quota exceeded. Resets on the 1st.", type: "insufficient_quota" } },
      429,
    );
  }

  touchToken(token);
  c.set("tokenRecord", record);
  await next();
}

/**
 * Middleware: admin secret check.
 */
export async function adminAuth(c: Context, next: Next): Promise<Response | void> {
  const secret = c.req.header("X-Admin-Secret");
  const expected = process.env.ADMIN_SECRET;
  if (!expected || secret !== expected) {
    return c.json({ error: { code: "UNAUTHORIZED", message: "Invalid admin secret" } }, 401);
  }
  await next();
}
