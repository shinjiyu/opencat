import { Hono } from "hono";
import { stream } from "hono/streaming";
import { incrementUsage } from "../db/tokens.js";
import { tokenAuth } from "../middleware/auth.js";

const app = new Hono();

app.use("/*", tokenAuth);

/**
 * GET /v1/models — list available models.
 * Protocol spec §3.5
 */
app.get("/models", (c) => {
  const defaultModel = process.env.UPSTREAM_DEFAULT_MODEL ?? "auto";
  return c.json({
    object: "list",
    data: [
      { id: "auto", object: "model", owned_by: "proxy" },
      { id: defaultModel, object: "model", owned_by: "upstream" },
    ],
  });
});

/**
 * POST /v1/chat/completions — proxy chat request to upstream LLM.
 * Protocol spec §3.3
 */
app.post("/chat/completions", async (c) => {
  const body = await c.req.json().catch(() => null);
  if (!body || !body.messages) {
    return c.json({ error: { code: "INVALID_REQUEST", message: "Missing required field: messages" } }, 400);
  }

  const tokenRecord = c.get("tokenRecord");
  const upstreamBase = process.env.UPSTREAM_BASE_URL ?? "https://openrouter.ai/api/v1";
  const upstreamKey = process.env.UPSTREAM_API_KEY;
  if (!upstreamKey) {
    return c.json({ error: { code: "SERVICE_UNAVAILABLE", message: "Upstream LLM not configured" } }, 503);
  }

  const defaultModel = process.env.UPSTREAM_DEFAULT_MODEL ?? "deepseek/deepseek-chat:free";
  const requestedModel = body.model === "auto" || !body.model ? defaultModel : body.model;
  const isStream = body.stream !== false;

  const upstreamBody = {
    ...body,
    model: requestedModel,
    stream: isStream,
  };

  let upstreamRes: Response;
  try {
    upstreamRes = await fetch(`${upstreamBase}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${upstreamKey}`,
      },
      body: JSON.stringify(upstreamBody),
    });
  } catch (err) {
    return c.json({ error: { code: "UPSTREAM_ERROR", message: `Failed to reach upstream: ${(err as Error).message}` } }, 502);
  }

  if (!upstreamRes.ok) {
    const errBody = await upstreamRes.text().catch(() => "");
    return c.json(
      { error: { code: "UPSTREAM_ERROR", message: `Upstream returned ${upstreamRes.status}: ${errBody.slice(0, 500)}` } },
      upstreamRes.status as 400,
    );
  }

  if (!isStream) {
    const data = await upstreamRes.json();
    const usage = data.usage;
    incrementUsage(tokenRecord.token, usage?.prompt_tokens ?? 0, usage?.completion_tokens ?? 0);
    c.header("X-Protocol-Version", "1.0.0");
    return c.json(data);
  }

  // Streaming: pipe upstream SSE to client
  c.header("Content-Type", "text/event-stream");
  c.header("Cache-Control", "no-cache");
  c.header("Connection", "keep-alive");
  c.header("X-Protocol-Version", "1.0.0");

  return stream(c, async (s) => {
    const reader = upstreamRes.body?.getReader();
    if (!reader) {
      await s.write("data: [DONE]\n\n");
      return;
    }

    const decoder = new TextDecoder();
    let done = false;

    while (!done) {
      const { value, done: readerDone } = await reader.read();
      done = readerDone;
      if (value) {
        await s.write(decoder.decode(value, { stream: true }));
      }
    }

    // Best-effort usage tracking for streamed responses
    incrementUsage(tokenRecord.token, 0, 0);
  });
});

export default app;
