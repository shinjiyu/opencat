import { Hono } from "hono";
import { incrementUsage } from "../db/tokens.js";
import { tokenAuth } from "../middleware/auth.js";

const app = new Hono();

app.use("/*", tokenAuth);

const DEFAULT_UPSTREAM_BASE = "https://open.bigmodel.cn/api/coding/paas/v4";
const DEFAULT_UPSTREAM_MODEL = "glm-5";

/**
 * GET /v1/models — list available models.
 */
app.get("/models", (c) => {
  const defaultModel = process.env.UPSTREAM_DEFAULT_MODEL ?? DEFAULT_UPSTREAM_MODEL;
  return c.json({
    object: "list",
    data: [
      { id: "auto", object: "model", owned_by: "proxy" },
      { id: defaultModel, object: "model", owned_by: "upstream" },
    ],
  });
});

/**
 * POST /v1/chat/completions — 完全透传到上游，仅替换 Authorization 和 model(auto→default)。
 */
app.post("/chat/completions", async (c) => {
  const tokenRecord = c.get("tokenRecord");
  const upstreamBase = process.env.UPSTREAM_BASE_URL ?? DEFAULT_UPSTREAM_BASE;
  const upstreamKey = process.env.UPSTREAM_API_KEY;
  if (!upstreamKey) {
    return c.json({ error: { code: "SERVICE_UNAVAILABLE", message: "Upstream LLM not configured (set UPSTREAM_API_KEY)" } }, 503);
  }

  const rawBody = await c.req.text();
  let bodyForUpstream = rawBody;

  // Only rewrite model when it's "auto" or missing
  try {
    const parsed = JSON.parse(rawBody);
    if (!parsed.model || parsed.model === "auto") {
      parsed.model = process.env.UPSTREAM_DEFAULT_MODEL ?? DEFAULT_UPSTREAM_MODEL;
      bodyForUpstream = JSON.stringify(parsed);
    }
  } catch {
    // If JSON parse fails, pass raw body through
  }

  let upstreamRes: Response;
  try {
    upstreamRes = await fetch(`${upstreamBase}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": c.req.header("Content-Type") ?? "application/json",
        Authorization: `Bearer ${upstreamKey}`,
      },
      body: bodyForUpstream,
    });
  } catch (err) {
    return c.json({ error: { code: "UPSTREAM_ERROR", message: `Failed to reach upstream: ${(err as Error).message}` } }, 502);
  }

  // Transparent proxy: forward status + headers + body as-is
  const resHeaders = new Headers();
  for (const key of ["content-type", "x-request-id", "x-ratelimit-remaining", "x-ratelimit-limit"]) {
    const val = upstreamRes.headers.get(key);
    if (val) resHeaders.set(key, val);
  }
  resHeaders.set("X-Protocol-Version", "1.0.0");

  // Best-effort usage tracking (count request; token counts from non-stream only)
  if (upstreamRes.ok) {
    const ct = upstreamRes.headers.get("content-type") ?? "";
    if (!ct.includes("text/event-stream")) {
      // Non-streaming: clone to read usage, then return
      const cloned = upstreamRes.clone();
      const data = await cloned.json().catch(() => null);
      const usage = data?.usage;
      incrementUsage(tokenRecord.token, usage?.prompt_tokens ?? 0, usage?.completion_tokens ?? 0);
    } else {
      incrementUsage(tokenRecord.token, 0, 0);
    }
  }

  return new Response(upstreamRes.body, {
    status: upstreamRes.status,
    headers: resHeaders,
  });
});

export default app;
