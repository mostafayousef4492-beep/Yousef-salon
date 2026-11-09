// مساعد صالون أبو يوسف — Supabase Edge Function
// بتتنادى من التطبيق بـ JWT المستخدم. بتشتغل بصلاحياته هو (مش service role) فمفيش تسريب بيانات بين المستخدمين.
// أسرار: GEMINI_API_KEY (Gemini) أو ANTHROPIC_API_KEY (Claude). ASSISTANT_PROVIDER=gemini|anthropic لو الاتنين موجودين.
// نموذج اختياري: GEMINI_MODEL (الافتراضي gemini-2.5-flash) أو ASSISTANT_MODEL (الافتراضي claude-sonnet-5-5).
import { createClient } from "npm:@supabase/supabase-js@2";
import { chat, type Ctx } from "./core.ts";
import { makeLlm } from "./llm.ts";

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
  const { llm, provider, model } = makeLlm((k) => Deno.env.get(k));
  if (!llm) return json({ reply: "المساعد لسه مش متفعّل (مفتاح الذكاء الاصطناعي ناقص).", off: true });

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
  if (role === "owner" || role === "manager") {
    const ok = await sb.rpc("ai_mode");
    if (ok.error && /ai_mode|PGRST202|42883/.test(JSON.stringify(ok.error))) return json({ reply: "مساعد الإدارة محتاج تحديث قاعدة البيانات (patch_manager_assistant.sql).", off: true });
    if (!ok.data) return json({ reply: "مساعد الإدارة مش مفعّل لحسابك. المالك يقدر يفعّله (assistant_manager_enabled).", off: true });
  }

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
  try {
    const out = await chat(ctx, history, llm);
    return json({ reply: out.reply, proposal: out.proposal, drills: out.drills, left: hit.data.left });
  } catch (e) {
    console.error("assistant", provider, model, String((e as Error)?.message || e));
    return json({ reply: "حصلت مشكلة مؤقتة في المساعد. جرّب تاني كمان شوية 🙏", error: true });
  }
});
