import "dotenv/config";
import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { serveStatic } from "@hono/node-server/serve-static";
import { cors } from "hono/cors";

import { initDb } from "./db/schema.js";
import tokenRoutes from "./routes/tokens.js";
import adminRoutes from "./routes/admin.js";
import proxyRoutes from "./routes/proxy.js";
import tunnelRoutes from "./routes/tunnel.js";
import { adminAuth } from "./middleware/auth.js";
import { findToken } from "./db/tokens.js";

const app = new Hono();

// CORS for Web UI
app.use("/*", cors());

// Protocol version header on all responses
app.use("/*", async (c, next) => {
  await next();
  c.header("X-Protocol-Version", "1.0.0");
});

// --- Routes ---

// Token allocation (install script calls this)
app.route("/api/tokens", tokenRoutes);

// Admin (protected)
app.use("/api/admin/*", adminAuth);
app.route("/api/admin", adminRoutes);

// LLM proxy (OpenAI-compatible)
app.route("/v1", proxyRoutes);

// Tunnel registration (user machine registers cloudflared URL)
app.route("/api/tunnel", tunnelRoutes);

// OpenClaw redirect — 302 to user's tunnel URL, no traffic proxied
app.get("/openclaw", (c) => {
  const token = c.req.query("token");
  if (!token) {
    return c.json({ error: { code: "UNAUTHORIZED", message: "Missing token parameter" } }, 401);
  }
  const record = findToken(token);
  if (!record) {
    return c.json({ error: { code: "UNAUTHORIZED", message: "Invalid token" } }, 401);
  }
  if (!record.tunnel_url) {
    return c.html(`<!DOCTYPE html><html><head><meta charset="utf-8"><title>OpenClaw</title></head><body style="font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;color:#333"><div style="text-align:center"><h2>OpenClaw Offline</h2><p>Please start OpenClaw on your computer first.</p><p style="color:#888;font-size:14px">The local application needs to be running with an active tunnel.</p></div></body></html>`);
  }
  return c.redirect(record.tunnel_url, 302);
});

// Chat Web UI (static files)
app.use("/chat/*", serveStatic({ root: "./public" }));
app.get("/chat", serveStatic({ root: "./public", path: "index.html" }));

// Admin Dashboard (static page, auth happens client-side via API)
app.get("/admin", serveStatic({ root: "./public", path: "admin.html" }));

// Health check
app.get("/health", (c) => c.json({ status: "ok", protocol_version: "1.0.0" }));

// --- Start ---

const port = Number(process.env.PORT ?? 3000);
const host = process.env.HOST ?? "0.0.0.0";

initDb();

serve({ fetch: app.fetch, port, hostname: host }, (info) => {
  console.log(`OpenCat Server listening on http://${host}:${info.port}`);
  console.log(`  Chat UI:  http://localhost:${info.port}/chat`);
  console.log(`  API:      http://localhost:${info.port}/v1/chat/completions`);
  console.log(`  Tokens:   http://localhost:${info.port}/api/tokens`);
});
