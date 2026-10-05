// صالون أبو يوسف — دالة إرسال الإشعارات (Supabase Edge Function)
// بتتنادى من قاعدة البيانات بس (header سري)، وبتبعت Web Push لكل أجهزة المستخدمين المطلوبين.
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
webpush.setVapidDetails(Deno.env.get("VAPID_SUBJECT")!, Deno.env.get("VAPID_PUBLIC")!, Deno.env.get("VAPID_PRIVATE")!);

const BASE: Record<string, string> = { admin: "/admin", staff: "/staff", customer: "/" };

Deno.serve(async (req) => {
  if (req.headers.get("x-push-secret") !== Deno.env.get("PUSH_SECRET")) return new Response("forbidden", { status: 401 });
  let p: any;
  try { p = await req.json(); } catch { return new Response("bad json", { status: 400 }); }
  const users: string[] = Array.isArray(p.users) ? p.users : [];
  if (!users.length) return Response.json({ sent: 0 });

  const { data: subs, error } = await sb.from("push_subscriptions").select("id,endpoint,p256dh,auth_key,app").in("user_id", users);
  if (error) return new Response(error.message, { status: 500 });

  const dead: number[] = [];
  let sent = 0;
  await Promise.all((subs ?? []).map(async (s) => {
    const url = (BASE[s.app] ?? "/") + (p.tab ? `?tab=${encodeURIComponent(p.tab)}` : "");
    const payload = JSON.stringify({ title: p.title, body: p.body, tag: p.tag, tab: p.tab, urgent: !!p.urgent, url });
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth_key } },
        payload,
        { TTL: p.urgent ? 600 : 3600, urgency: p.urgent ? "high" : "normal" },
      );
      sent++;
    } catch (e: any) {
      if (e?.statusCode === 404 || e?.statusCode === 410) dead.push(s.id); // الجهاز اتشال أو الإذن اتسحب
      else console.error("push failed", e?.statusCode, e?.body);
    }
  }));
  if (dead.length) await sb.from("push_subscriptions").delete().in("id", dead);
  return Response.json({ sent, removed: dead.length });
});
