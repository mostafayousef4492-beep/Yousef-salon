// مساعد صالون أبو يوسف — Supabase Edge Function
// بتتنادى من التطبيق بـ JWT المستخدم. بتشتغل بصلاحياته هو (مش service role) فمفيش تسريب بيانات بين المستخدمين.
// أسرار مطلوبة: ANTHROPIC_API_KEY  — اختياري: ASSISTANT_MODEL (الافتراضي claude-sonnet-5-5)
import { createClient } from "npm:@supabase/supabase-js@2";
import { chat, type Ctx } from "./core.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const auth = req.headers.get("Authorization") || "";
  const jwt = auth.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "auth" }, 401);
  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return json({ reply: "المساعد لسه مش متفعّل (مفتاح الذكاء الاصطناعي ناقص).", off: true });

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: `Bearer ${jwt}` } }, auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: u, error: ue } = await sb.auth.getUser(jwt);
  if (ue || !u?.user) return json({ error: "auth" }, 401);
  const uid = u.user.id;

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "bad json" }, 400); }
  const history = Array.isArray(body?.messages) ? body.messages : [];

  // حد يومي + مفتاح إيقاف (patch_assistant.sql)
  const hit = await sb.rpc("assistant_hit");
  if (hit.error) {
    const missing = /assistant_hit|PGRST202|42883/.test(JSON.stringify(hit.error));
    return json({ reply: missing ? "المساعد محتاج تحديث قاعدة البيانات (patch_assistant.sql)." : "حصلت مشكلة، جرّب تاني بعد شوية.", off: true });
  }
  if (!hit.data?.ok) {
    return json({ reply: hit.data?.reason === "limit" ? `وصلت للحد اليومي للأسئلة (${hit.data.limit}). كمّل بكرة بإذن الله 🌙` : "المساعد متوقف مؤقتًا.", off: true });
  }
  const staffRoles = ["owner", "manager", "cashier", "barber", "assistant"];
  const role: string = hit.data.role || "customer";
  const staff = staffRoles.includes(role);

  let name = "", custId: number | undefined, phone: string | undefined;
  if (staff) {
    const { data: p } = await sb.from("profiles").select("full_name").eq("id", uid).maybeSingle();
    name = p?.full_name || "";
  } else {
    const { data: c } = await sb.from("customers").select("id,name,phone").eq("user_id", uid).maybeSingle();
    if (!c) return json({ reply: "حسابك لسه مش مربوط بملف عميل. اطلب من الكاشير يربطه الأول 🙏", off: true });
    name = c.name; custId = c.id; phone = c.phone;
  }
  let tz = "Africa/Cairo";
  try { const t = await sb.from("app_settings").select("value").eq("key", "timezone").maybeSingle(); const v = String(t.data?.value ?? "").replace(/"/g, ""); if (v) tz = v; } catch { /* */ }

  const ctx: Ctx = { sb, uid, staff, role, name, tz, now: new Date(), custId, phone };
  const model = Deno.env.get("ASSISTANT_MODEL") || "claude-sonnet-5-5";
  const llm = async (system: string, messages: any[], tools: any[]) => {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model, max_tokens: 1200, system, messages, tools }),
    });
    if (!r.ok) { console.error("anthropic", r.status, (await r.text()).slice(0, 300)); throw new Error("llm " + r.status); }
    return await r.json();
  };

  try {
    const out = await chat(ctx, history, llm);
    return json({ reply: out.reply, proposal: out.proposal, left: hit.data.left });
  } catch (e) {
    console.error("assistant", String((e as Error)?.message || e));
    return json({ reply: "حصلت مشكلة مؤقتة في المساعد. جرّب تاني كمان شوية 🙏", error: true });
  }
});
