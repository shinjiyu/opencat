import { Hono } from "hono";
import { findToken, setTunnelUrl, clearTunnelUrl } from "../db/tokens.js";
import { extractToken } from "../middleware/auth.js";

const app = new Hono();

/**
 * PUT /api/tunnel — register / update tunnel URL.
 * Protocol spec §3.7
 */
app.put("/", async (c) => {
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

  const body = await c.req.json().catch(() => null);
  if (!body || !body.tunnel_url || typeof body.tunnel_url !== "string") {
    return c.json({ error: { code: "INVALID_REQUEST", message: "Missing required field: tunnel_url" } }, 400);
  }

  const tunnelUrl: string = body.tunnel_url.trim();
  if (!tunnelUrl.startsWith("https://")) {
    return c.json({ error: { code: "INVALID_REQUEST", message: "tunnel_url must start with https://" } }, 400);
  }

  const updated = setTunnelUrl(token, tunnelUrl);
  if (!updated) {
    return c.json({ error: { code: "UNAUTHORIZED", message: "Token not found" } }, 401);
  }

  const publicBase = process.env.PUBLIC_BASE_URL ?? `http://localhost:${process.env.PORT ?? 3000}`;

  return c.json({
    token: updated.token,
    tunnel_url: updated.tunnel_url,
    openclaw_url: `${publicBase}/openclaw?token=${updated.token}`,
    updated_at: updated.tunnel_updated_at,
  });
});

/**
 * DELETE /api/tunnel — unregister tunnel URL.
 * Protocol spec §3.8
 */
app.delete("/", (c) => {
  const token = extractToken(c);
  if (!token) {
    return c.json({ error: { code: "UNAUTHORIZED", message: "Missing token" } }, 401);
  }

  const record = findToken(token);
  if (!record) {
    return c.json({ error: { code: "UNAUTHORIZED", message: "Invalid token" } }, 401);
  }

  clearTunnelUrl(token);
  return c.body(null, 204);
});

export default app;
