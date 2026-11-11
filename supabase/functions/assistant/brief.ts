// ملخص اليوم الاستباقي (من غير نموذج ذكاء اصطناعي): حقائق من دوال القاعدة، بتظهر للمالك/المدير أول ما يفتح المساعد.
// المدير بيشوف التشغيل بس (اليوم/الدرج/الحجوزات). المالك بيشوف كمان الإيراد والتنبيهات.
import type { Ctx } from "./core.ts";
import { rangeFor, localDate } from "./core.ts";
import { alerts } from "./insights.ts";

const J = (n: number) => `${Math.round(n).toLocaleString("en-US")} جنيه`;
async function rpc(ctx: Ctx, fn: string, args?: any) { const { data, error } = await ctx.sb.rpc(fn, args ?? {}); if (error) throw new Error(error.message); return data; }

export async function buildBrief(ctx: Ctx): Promise<{ lines: { icon: string; text: string; level?: "warn" | "bad" | "ok" }[]; chips: string[] }> {
  const lines: { icon: string; text: string; level?: "warn" | "bad" | "ok" }[] = [], chips: string[] = [];
  const today = localDate(ctx.now, ctx.tz);
  let day: any = null;
  try { day = await rpc(ctx, "business_day_state"); } catch { /* */ }
  const open = !!(day && day.open && day.day);
  if (!day) lines.push({ icon: "❔", text: "مقدرتش أعرف حالة يوم العمل." });
  else if (!open) { lines.push({ icon: "🔴", text: "مفيش يوم عمل مفتوح دلوقتي.", level: "warn" }); chips.push("افتح يوم النهارده"); }
  else {
    const d = String(day.day).slice(0, 10);
    const hrs = day.opened_at ? Math.round((ctx.now.getTime() - Date.parse(day.opened_at)) / 36e5) : Math.round((Date.parse(today) - Date.parse(d)) / 36e5);
    if (d < today) { lines.push({ icon: "⚠️", text: `يوم ${d} لسه مفتوح (قديم) — اقفله بجرد الدرج.`, level: "bad" }); chips.push("اقفل اليوم"); }
    else lines.push({ icon: "🟢", text: `يوم العمل ${d} مفتوح${hrs > 0 && day.opened_at ? ` من حوالي ${hrs} ساعة` : ""}.`, level: hrs > 16 ? "warn" : "ok" });
    try {
      const pv = await rpc(ctx, "close_day_preview", { p_day: d });
      const exp = Number(pv?.expected_cash);
      if (Number.isFinite(exp)) lines.push({ icon: "💰", text: `المتوقع في الدرج دلوقتي ${J(exp)}.` });
      if (Number(pv?.pending) > 0) lines.push({ icon: "⏳", text: `${pv.pending} حجز لسه في الدور (دخل أو على الكرسي).`, level: "warn" });
      if (Number(pv?.upcoming) > 0) lines.push({ icon: "📅", text: `${pv.upcoming} حجز لسه مستني.` });
    } catch { /* */ }
    if (hrs > 16 || d < today) { if (!chips.includes("اقفل اليوم")) chips.push("اقفل اليوم"); }
  }
  if (ctx.role === "owner" && ctx.analytics !== false) {
    try {
      const r = rangeFor("today", undefined, undefined, ctx.now, ctx.tz);
      const o = await rpc(ctx, "ai_overview", { p_from: r.fromISO, p_to: r.toISO });
      if (o && o.invoices) lines.push({ icon: "🧾", text: `النهارده: ${o.invoices} فاتورة بإيراد ${J(Number(o.revenue || 0))}.` });
      else lines.push({ icon: "🧾", text: "مفيش فواتير النهارده لحد دلوقتي." });
    } catch { /* */ }
    try {
      const a = await alerts(ctx, { range: "week" });
      const top = (a.data.findings as any[]).filter((x) => x.severity !== "info").slice(0, 2);
      for (const x of top) lines.push({ icon: x.severity === "critical" ? "🚨" : "⚠️", text: x.message, level: x.severity === "critical" ? "bad" : "warn" });
      chips.push("إيه الجديد في الأداء؟");
    } catch { /* */ }
  }
  chips.push(ctx.role === "owner" ? "قارن الشهر ده بالشهر اللي فات" : "مين المتأخر النهارده؟");
  return { lines: lines.slice(0, 7), chips: chips.slice(0, 4) };
}
