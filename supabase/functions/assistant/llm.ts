// مزوّد الذكاء الاصطناعي: Gemini أو Claude بنفس الواجهة. المنطق في core.ts بيتكلم بصيغة Anthropic (tool_use / tool_result)
// والمحوّل هنا بيترجمها لـ Gemini ويرجّعها بنفس الصيغة، فالتبديل بين المزوّدين = تغيير أسرار بس.
import type { Llm } from "./core.ts";

type Env = (k: string) => string | undefined;

export function pickProvider(env: Env): { provider: "gemini" | "anthropic" | null; model: string } {
  const want = (env("ASSISTANT_PROVIDER") || "").toLowerCase();
  const hasA = !!env("ANTHROPIC_API_KEY"), hasG = !!env("GEMINI_API_KEY");
  const provider = want === "gemini" && hasG ? "gemini" : want === "anthropic" && hasA ? "anthropic" : hasA && !want ? "anthropic" : hasG ? "gemini" : hasA ? "anthropic" : null;
  const model = provider === "gemini" ? env("GEMINI_MODEL") || env("ASSISTANT_MODEL") || "gemini-2.5-flash" : env("ASSISTANT_MODEL") || "claude-sonnet-5-5";
  return { provider, model };
}

export function makeLlm(env: Env, doFetch: typeof fetch = fetch): { llm: Llm | null; provider: string | null; model: string } {
  const { provider, model } = pickProvider(env);
  if (provider === "anthropic") return { llm: anthropicLlm(env("ANTHROPIC_API_KEY")!, model, doFetch), provider, model };
  if (provider === "gemini") return { llm: geminiLlm(env("GEMINI_API_KEY")!, model, doFetch), provider, model };
  return { llm: null, provider: null, model };
}

function anthropicLlm(key: string, model: string, doFetch: typeof fetch): Llm {
  return async (system, messages, tools) => {
    const r = await doFetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model, max_tokens: 1200, system, messages, tools }),
    });
    if (!r.ok) { console.error("anthropic", r.status, (await r.text()).slice(0, 300)); throw new Error("llm " + r.status); }
    return await r.json();
  };
}

// ---------- Gemini ----------
export function toGeminiTools(tools: any[]) {
  const decl = tools.map((t) => {
    const props = t.input_schema?.properties || {};
    const d: any = { name: t.name, description: t.description };
    if (Object.keys(props).length) d.parameters = { type: "object", properties: props, ...(t.input_schema.required ? { required: t.input_schema.required } : {}) };
    return d;
  });
  return [{ functionDeclarations: decl }];
}

export function toGeminiContents(messages: any[]) {
  const names: Record<string, string> = {};
  const out: any[] = [];
  for (const m of messages) {
    if (typeof m.content === "string") { out.push({ role: m.role === "assistant" ? "model" : "user", parts: [{ text: m.content }] }); continue; }
    if (m.role === "assistant") {
      const parts: any[] = [];
      for (const b of m.content) {
        if (b.type === "text" && b.text) parts.push({ text: b.text });
        else if (b.type === "tool_use") { names[b.id] = b.name; const p: any = { functionCall: { name: b.name, args: b.input || {} } }; if (b.sig) p.thoughtSignature = b.sig; parts.push(p); }
      }
      if (parts.length) out.push({ role: "model", parts });
    } else {
      const parts: any[] = [];
      for (const b of m.content) {
        if (b.type === "tool_result") {
          let resp: any; try { resp = JSON.parse(b.content); } catch { resp = { text: String(b.content) }; }
          if (resp === null || typeof resp !== "object" || Array.isArray(resp)) resp = { result: resp };
          parts.push({ functionResponse: { name: names[b.tool_use_id] || "tool", response: resp } });
        } else if (b.type === "text" && b.text) parts.push({ text: b.text });
      }
      if (parts.length) out.push({ role: "user", parts });
    }
  }
  return out;
}

export function fromGemini(j: any) {
  const cand = j?.candidates?.[0];
  const parts: any[] = cand?.content?.parts || [];
  const content: any[] = [];
  let n = 0, tool = false;
  for (const p of parts) {
    if (p.thought) continue;
    if (typeof p.text === "string" && p.text) content.push({ type: "text", text: p.text });
    else if (p.functionCall) { tool = true; content.push({ type: "tool_use", id: "g" + (++n) + "_" + Math.random().toString(36).slice(2, 7), name: p.functionCall.name, input: p.functionCall.args || {}, sig: p.thoughtSignature }); }
  }
  if (!content.length) content.push({ type: "text", text: cand?.finishReason === "SAFETY" || j?.promptFeedback?.blockReason ? "معلش، مقدرش أرد على السؤال ده." : "" });
  return { stop_reason: tool ? "tool_use" : "end_turn", content };
}

function geminiLlm(key: string, model: string, doFetch: typeof fetch): Llm {
  return async (system, messages, tools) => {
    const r = await doFetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
      method: "POST",
      headers: { "x-goog-api-key": key, "content-type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents: toGeminiContents(messages),
        tools: toGeminiTools(tools),
        generationConfig: { maxOutputTokens: 2048, temperature: 0.4 },
      }),
    });
    if (!r.ok) { console.error("gemini", r.status, (await r.text()).slice(0, 400)); throw new Error("llm " + r.status); }
    return fromGemini(await r.json());
  };
}
