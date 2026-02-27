import { Hono } from "hono";
import { createToken, findToken, getUsageToday, getUsageMonth } from "../db/tokens.js";

const VALID_PLATFORMS = ["win-x64", "darwin-arm64", "darwin-x64", "linux-x64"];

const app = new Hono();

/**
 * POST /api/tokens — allocate a new token (build/packaging only; requires X-Build-Secret).
 * Not callable from install script; only from build server with BUILD_SECRET.
 * Protocol spec §3.1
 */
app.post("/", async (c) => {
  const buildSecret = process.env.BUILD_SECRET;
  if (buildSecret) {
    const provided = c.req.header("X-Build-Secret");
    if (provided !== buildSecret) {
      return c.json(
        { error: { code: "UNAUTHORIZED", message: "Token allocation requires build secret" } },
        401,
      );
    }
  }

  const body = await c.req.json().catch(() => null);
  if (!body) {
    return c.json({ error: { code: "INVALID_REQUEST", message: "Invalid JSON body" } }, 400);
  }

  const { platform, install_id, version, meta } = body;

  if (!platform || !VALID_PLATFORMS.includes(platform)) {
    return c.json(
      { error: { code: "INVALID_REQUEST", message: `Missing or invalid platform. Must be one of: ${VALID_PLATFORMS.join(", ")}` } },
      400,
    );
  }
  if (!install_id || typeof install_id !== "string") {
    return c.json({ error: { code: "INVALID_REQUEST", message: "Missing required field: install_id" } }, 400);
  }

  const record = createToken({ platform, install_id, version, meta });

  const publicBase = process.env.PUBLIC_BASE_URL ?? `http://localhost:${process.env.PORT ?? 3000}`;

  return c.json({
    token: record.token,
    proxy_base_url: `${publicBase}/v1`,
    quota: {
      daily_limit: record.daily_limit,
      monthly_limit: record.monthly_limit,
    },
    created_at: record.created_at,
  });
});

/**
 * GET /api/tokens/:token/status — query token status.
 * Protocol spec §3.2
 */
app.get("/:token/status", (c) => {
  const token = c.req.param("token");
  const record = findToken(token);
  if (!record) {
    return c.json({ error: { code: "TOKEN_NOT_FOUND", message: "Token not found" } }, 404);
  }

  const usageToday = getUsageToday(token);
  const usageMonth = getUsageMonth(token);
  const dailyUsed = usageToday?.request_count ?? 0;
  const monthlyUsed = usageMonth.request_count;

  let status = record.status;
  if (status === "active") {
    if (dailyUsed >= record.daily_limit || monthlyUsed >= record.monthly_limit) {
      status = "quota_exceeded";
    }
  }

  return c.json({
    token: record.token,
    status,
    quota: {
      daily_limit: record.daily_limit,
      daily_used: dailyUsed,
      daily_remaining: Math.max(0, record.daily_limit - dailyUsed),
      monthly_limit: record.monthly_limit,
      monthly_used: monthlyUsed,
      monthly_remaining: Math.max(0, record.monthly_limit - monthlyUsed),
    },
    created_at: record.created_at,
  });
});

export default app;
