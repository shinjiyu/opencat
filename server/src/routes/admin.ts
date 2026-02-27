import { Hono } from "hono";
import { listTokens, findToken, updateToken, deleteToken, getUsageToday, getUsageMonth } from "../db/tokens.js";

const app = new Hono();

/**
 * GET /api/admin/tokens — list all tokens.
 * Protocol spec §3.6.1
 */
app.get("/tokens", (c) => {
  const page = Number(c.req.query("page") ?? 1);
  const limit = Number(c.req.query("limit") ?? 20);
  const status = c.req.query("status");

  const result = listTokens({ page, limit, status: status || undefined });

  const tokensWithUsage = result.tokens.map((t) => {
    const usageToday = getUsageToday(t.token);
    const usageMonth = getUsageMonth(t.token);
    return {
      ...t,
      meta: t.meta ? JSON.parse(t.meta) : null,
      quota: {
        daily_limit: t.daily_limit,
        daily_used: usageToday?.request_count ?? 0,
        monthly_limit: t.monthly_limit,
        monthly_used: usageMonth.request_count,
      },
    };
  });

  return c.json({
    tokens: tokensWithUsage,
    total: result.total,
    page,
    limit,
  });
});

/**
 * PATCH /api/admin/tokens/:token — modify a token.
 * Protocol spec §3.6.2
 */
app.patch("/tokens/:token", async (c) => {
  const token = c.req.param("token");
  const body = await c.req.json().catch(() => null);
  if (!body) {
    return c.json({ error: { code: "INVALID_REQUEST", message: "Invalid JSON body" } }, 400);
  }

  const existing = findToken(token);
  if (!existing) {
    return c.json({ error: { code: "TOKEN_NOT_FOUND", message: "Token not found" } }, 404);
  }

  const updates: { status?: string; daily_limit?: number; monthly_limit?: number } = {};

  if (body.status !== undefined) {
    if (!["active", "disabled"].includes(body.status)) {
      return c.json({ error: { code: "INVALID_REQUEST", message: "status must be 'active' or 'disabled'" } }, 400);
    }
    updates.status = body.status;
  }
  if (body.quota?.daily_limit !== undefined) updates.daily_limit = body.quota.daily_limit;
  if (body.quota?.monthly_limit !== undefined) updates.monthly_limit = body.quota.monthly_limit;

  const updated = updateToken(token, updates);
  return c.json(updated);
});

/**
 * DELETE /api/admin/tokens/:token — delete a token.
 * Protocol spec §3.6.3
 */
app.delete("/tokens/:token", (c) => {
  const token = c.req.param("token");
  const deleted = deleteToken(token);
  if (!deleted) {
    return c.json({ error: { code: "TOKEN_NOT_FOUND", message: "Token not found" } }, 404);
  }
  return c.body(null, 204);
});

export default app;
