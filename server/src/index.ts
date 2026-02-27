import "dotenv/config";
import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { serveStatic } from "@hono/node-server/serve-static";
import { cors } from "hono/cors";

import { getDb, initDb } from "./db/schema.js";
import tokenRoutes from "./routes/tokens.js";
import adminRoutes from "./routes/admin.js";
import proxyRoutes from "./routes/proxy.js";
import { adminAuth } from "./middleware/auth.js";

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

// Chat Web UI (static files)
app.use("/chat/*", serveStatic({ root: "./public" }));
app.get("/chat", serveStatic({ root: "./public", path: "index.html" }));

// Health check
app.get("/health", (c) => c.json({ status: "ok", protocol_version: "1.0.0" }));

// --- Start ---

const port = Number(process.env.PORT ?? 3000);
const host = process.env.HOST ?? "0.0.0.0";

// Init database
const db = getDb();
initDb(db);
console.log(`Database initialized`);

serve({ fetch: app.fetch, port, hostname: host }, (info) => {
  console.log(`OpenCat Server listening on http://${host}:${info.port}`);
  console.log(`  Chat UI:  http://localhost:${info.port}/chat`);
  console.log(`  API:      http://localhost:${info.port}/v1/chat/completions`);
  console.log(`  Tokens:   http://localhost:${info.port}/api/tokens`);
});
