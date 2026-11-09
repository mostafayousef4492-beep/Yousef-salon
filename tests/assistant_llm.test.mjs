// اختبار محوّل المزوّدين (Gemini / Claude) بدون شبكة. تشغيل: node --experimental-strip-types tests/assistant_llm.test.mjs
import assert from "node:assert/strict";
import { pickProvider, makeLlm, toGeminiContents, toGeminiTools, fromGemini } from "../supabase/functions/assistant/llm.ts";
import { chat, toolsFor } from "../supabase/functions/assistant/core.ts";
const T = (n, f) => Promise.resolve().then(f).then(() => console.log("PASS:", n), (e) => { console.log("FAIL:", n, e.message); process.exitCode = 1; });
const env = (o) => (k) => o[k];

await T("اختيار المزوّد", () => {
  assert.equal(pickProvider(env({ GEMINI_API_KEY: "g" })).provider, "gemini");
  assert.equal(pickProvider(env({ GEMINI_API_KEY: "g" })).model, "gemini-2.5-flash");
  assert.equal(pickProvider(env({ ANTHROPIC_API_KEY: "a" })).provider, "anthropic");
  assert.equal(pickProvider(env({ ANTHROPIC_API_KEY: "a" })).model, "claude-sonnet-5-5");
  assert.equal(pickProvider(env({ GEMINI_API_KEY: "g", ANTHROPIC_API_KEY: "a" })).provider, "anthropic"); // كلود له الأولوية لما الاتنين موجودين
  assert.equal(pickProvider(env({ GEMINI_API_KEY: "g", ANTHROPIC_API_KEY: "a", ASSISTANT_PROVIDER: "gemini" })).provider, "gemini");
  assert.equal(pickProvider(env({ ASSISTANT_PROVIDER: "gemini", ANTHROPIC_API_KEY: "a" })).provider, "anthropic"); // مفيش مفتاح جيميناي
  assert.equal(pickProvider(env({})).provider, null);
  assert.equal(pickProvider(env({ GEMINI_API_KEY: "g", GEMINI_MODEL: "gemini-2.5-pro" })).model, "gemini-2.5-pro");
});
await T("تحويل الأدوات: الأداة من غير مدخلات بتتبعت من غير parameters", () => {
  const d = toGeminiTools(toolsFor(false))[0].functionDeclarations;
  assert.equal(d.find((x) => x.name === "salon_info").parameters, undefined);
  const p = d.find((x) => x.name === "propose_booking");
  assert.deepEqual(p.parameters.required, ["day", "period", "service_ids"]);
  assert.equal(p.parameters.properties.service_ids.items.type, "integer");
  assert.ok(!JSON.stringify(d).includes("additionalProperties"));
});
await T("تحويل المحادثة: tool_use/tool_result + thoughtSignature", () => {
  const c = toGeminiContents([
    { role: "user", content: "سؤال" },
    { role: "assistant", content: [{ type: "text", text: "لحظة" }, { type: "tool_use", id: "x1", name: "my_account", input: {}, sig: "SIG" }] },
    { role: "user", content: [{ type: "tool_result", tool_use_id: "x1", content: JSON.stringify({ points: 5 }) }] },
  ]);
  assert.equal(c[0].role, "user"); assert.equal(c[1].role, "model");
  assert.equal(c[1].parts[1].functionCall.name, "my_account"); assert.equal(c[1].parts[1].thoughtSignature, "SIG");
  assert.equal(c[2].parts[0].functionResponse.name, "my_account"); assert.deepEqual(c[2].parts[0].functionResponse.response, { points: 5 });
});
await T("تحويل الرد: نص / أداة / محجوب", () => {
  assert.equal(fromGemini({ candidates: [{ content: { parts: [{ text: "أهلا" }] } }] }).stop_reason, "end_turn");
  const t = fromGemini({ candidates: [{ content: { parts: [{ functionCall: { name: "salon_info", args: {} }, thoughtSignature: "S" }] } }] });
  assert.equal(t.stop_reason, "tool_use"); assert.equal(t.content[0].name, "salon_info"); assert.equal(t.content[0].sig, "S");
  assert.match(fromGemini({ promptFeedback: { blockReason: "SAFETY" } }).content[0].text, /مقدرش/);
  assert.equal(fromGemini({ candidates: [{ content: { parts: [{ thought: true, text: "تفكير" }, { text: "رد" }] } }] }).content.length, 1);
});
await T("دورة كاملة مع Gemini وهمي: أداة ثم رد، والمفتاح في الهيدر مش في الرابط", async () => {
  const reqs = []; let n = 0;
  const f = async (url, init) => { reqs.push({ url, init, body: JSON.parse(init.body) }); n++;
    const body = n === 1 ? { candidates: [{ content: { parts: [{ functionCall: { name: "my_account", args: {} }, thoughtSignature: "TS" }] } }] }
      : { candidates: [{ content: { parts: [{ text: "عندك ٥ نقاط" }] } }] };
    return new Response(JSON.stringify(body), { status: 200 }); };
  const { llm, provider } = makeLlm(env({ GEMINI_API_KEY: "SECRET" }), f);
  assert.equal(provider, "gemini");
  const sb = { from: () => new Proxy({}, { get: (_, k) => k === "maybeSingle" ? async () => ({ data: { id: 1, name: "م", points: 5, visits: 1 } }) : k === "then" ? (r) => r({ data: [] }) : () => new Proxy({}, { get: (_, k2) => k2 === "maybeSingle" ? async () => ({ data: { id: 1, name: "م", points: 5, visits: 1 } }) : k2 === "then" ? (r) => r({ data: [] }) : () => ({}) }) }), rpc: async () => ({ data: null }) };
  const ctx = { sb, uid: "u", staff: false, role: "customer", name: "م", tz: "Africa/Cairo", now: new Date() };
  const r = await chat(ctx, [{ role: "user", content: "نقاطي؟" }], llm);
  assert.equal(r.reply, "عندك ٥ نقاط");
  assert.ok(!reqs[0].url.includes("SECRET")); assert.equal(reqs[0].init.headers["x-goog-api-key"], "SECRET");
  assert.ok(reqs[0].url.includes("gemini-2.5-flash:generateContent"));
  assert.equal(reqs[1].body.contents.at(-1).parts[0].functionResponse.name, "my_account");
  assert.equal(reqs[1].body.contents.at(-2).parts[0].thoughtSignature, "TS");
  assert.ok(reqs[0].body.systemInstruction.parts[0].text.includes("مساعد صالون"));
});
await T("خطأ من Gemini بيطلع استثناء (index بيحوّله لرسالة ودية)", async () => {
  const { llm } = makeLlm(env({ GEMINI_API_KEY: "k" }), async () => new Response("bad", { status: 429 }));
  await assert.rejects(() => llm("s", [{ role: "user", content: "x" }], []), /llm 429/);
});
