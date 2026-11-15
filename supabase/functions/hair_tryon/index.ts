// hair_tryon — تجربة القصة بالذكاء الاصطناعي (Gemini Flash Image)
// السرّ المطلوب: GEMINI_API_KEY (نفس مفتاح المساعد). اختياري: TRYON_MODEL (الافتراضي gemini-2.5-flash-image)
// الصورة بتتعالج في الذاكرة بس ومش بتتخزّن ولا بتتسجّل. بنسجّل في tryon_log: العميل + الشكل + نجح/فشل (للحد اليومي).
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });

export const STYLES: Record<string, string> = {
  classic: "a classic short men's haircut with a neat side part",
  low_fade: "a low fade haircut with a short textured top",
  mid_fade: "a mid skin fade with a textured quiff on top",
  high_fade: "a high fade with a clean short top",
  buzz: "a very short even buzz cut",
  crop: "a textured French crop with a short fringe and tapered sides",
  pompadour: "a modern pompadour with tapered sides",
  undercut: "an undercut with longer slicked-back hair on top",
  beard_light: "keep the current hair unchanged and add a short, neatly trimmed stubble beard with sharp lines",
  beard_full: "keep the current hair unchanged and add a full, well-groomed medium-length beard with a clean cheek line",
};
const MIMES = new Set(["image/jpeg", "image/png", "image/webp"]);
const MAX_B64 = 3_000_000; // حوالي 2.2MB

export function buildPrompt(style: string): string {
  return `Edit this photograph of a person. Change ONLY the hairstyle/beard as follows: ${STYLES[style]}. ` +
    `Keep the person's face, identity, facial features, skin tone, expression, apparent age, clothing, pose, background and lighting exactly the same. ` +
    `The result must look like a natural, realistic photograph. ` +
    `If the photo does not clearly show exactly one adult person's face, do not generate an image.`;
}

// بيطلّع الصورة من رد Gemini (inlineData أو inline_data) أو سبب الرفض
export function parseGemini(j: any): { image?: string; mime?: string; reason?: string } {
  const parts = j?.candidates?.[0]?.content?.parts || [];
  for (const p of parts) {
    const d = p.inlineData || p.inline_data;
    if (d?.data) return { image: d.data, mime: d.mimeType || d.mime_type || "image/png" };
  }
  return { reason: j?.promptFeedback?.blockReason || j?.candidates?.[0]?.finishReason || "no_image" };
}

export async function handle(req: Request, env: (k: string) => string | undefined, doFetch: typeof fetch = fetch, mk: typeof createClient = createClient): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST بس" }, 405);

  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "سجّل دخول الأول" }, 401);
  const url = env("SUPABASE_URL")!, anon = env("SUPABASE_ANON_KEY")!, svc = env("SUPABASE_SERVICE_ROLE_KEY")!;
  const userSb = mk(url, anon, { global: { headers: { Authorization: `Bearer ${jwt}` } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: u, error: ue } = await userSb.auth.getUser(jwt);
  if (ue || !u?.user) return json({ error: "سجّل دخول الأول" }, 401);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "طلب غلط" }, 400); }
  if (body?.consent !== true) return json({ error: "لازم توافق الأول إن صورتك تتبعت للمعالجة" }, 400);
  const style = String(body?.style || ""), mime = String(body?.mime || ""), image = String(body?.image || "");
  if (!STYLES[style]) return json({ error: "الشكل ده مش متاح" }, 400);
  if (!MIMES.has(mime)) return json({ error: "نوع الصورة غير مدعوم (JPG / PNG / WebP)" }, 400);
  if (image.length < 1000 || image.length > MAX_B64 || !/^[A-Za-z0-9+/=]+$/.test(image)) return json({ error: "الصورة كبيرة أو مش واضحة، جرّب صورة تانية" }, 400);

  const key = env("GEMINI_API_KEY");
  if (!key) return json({ error: "الخدمة مش متفعّلة لسه" }, 503);

  const admin = mk(url, svc, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: c } = await admin.from("customers").select("id").eq("user_id", u.user.id).maybeSingle();
  if (!c) return json({ error: "الخدمة للعملاء المسجّلين بس" }, 403);

  const { data: logId, error: re } = await admin.rpc("tryon_reserve", { p_customer: c.id, p_style: style });
  if (re) return json({ error: re.message }, 429);
  const finish = (ok: boolean, err?: string) => admin.rpc("tryon_finish", { p_id: logId, p_ok: ok, p_err: err ?? null });

  const model = env("TRYON_MODEL") || "gemini-2.5-flash-image";
  const ctl = new AbortController(), timer = setTimeout(() => ctl.abort(), 60_000);
  try {
    const r = await doFetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
      method: "POST", signal: ctl.signal,
      headers: { "Content-Type": "application/json", "x-goog-api-key": key },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: buildPrompt(style) }, { inline_data: { mime_type: mime, data: image } }] }],
        generationConfig: { responseModalities: ["TEXT", "IMAGE"] },
      }),
    });
    if (!r.ok) { await finish(false, "http_" + r.status); return json({ error: r.status === 429 ? "الخدمة مشغولة دلوقتي، جرّب كمان شوية" : "حصلت مشكلة في الخدمة، جرّب تاني" }, 502); }
    const out = parseGemini(await r.json());
    if (!out.image) { await finish(false, out.reason); return json({ error: "مقدرناش نعمل تصوّر للصورة دي. جرّب صورة وش واضحة لشخص واحد." }, 422); }
    await finish(true);
    return json({ image: out.image, mime: out.mime });
  } catch (e) {
    await finish(false, (e as Error)?.name === "AbortError" ? "timeout" : "error");
    return json({ error: "الخدمة اتأخرت، جرّب تاني" }, 504);
  } finally { clearTimeout(timer); }
}

Deno.serve((req) => handle(req, (k) => Deno.env.get(k)));
