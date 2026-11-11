// أدوات تحليل متقدمة للمالك (قراءة بس): تنبيهات غير طبيعية، نمط أيام الأسبوع، وتوقّع آخر الشهر.
// كل الأرقام والنسب محسوبة بالكود من دوال ai_* الموجودة (نفس مصادر باقي أدوات التحليل). مفيش بيانات عملاء ولا أسماء.
import type { Ctx } from "./core.ts";
import { rangeFor, localDate } from "./core.ts";

const fmt = (x: any) => (x === null || x === undefined ? null : Math.round(Number(x) * 100) / 100);
const J = (n: number) => `${Math.round(n).toLocaleString("en-US")} جنيه`;
const DAY_AR = ["الأحد", "الاتنين", "التلات", "الأربع", "الخميس", "الجمعة", "السبت"];

function addDays(d: string, n: number): string { const [y, m, da] = d.split("-").map(Number); return new Date(Date.UTC(y, m - 1, da + n)).toISOString().slice(0, 10); }
function dow(d: string): number { const [y, m, da] = d.split("-").map(Number); return new Date(Date.UTC(y, m - 1, da)).getUTCDay(); }
function daysBetween(a: string, b: string): number { return Math.round((Date.parse(b) - Date.parse(a)) / 864e5) + 1; }
async function rpc(ctx: Ctx, fn: string, args: any) { const { data, error } = await ctx.sb.rpc(fn, args); if (error) throw new Error(error.message); return data; }
const base = (r: { fromISO: string; toISO: string }) => ({ p_from: r.fromISO, p_to: r.toISO });

type Finding = { severity: "critical" | "warning" | "info"; code: string; message: string; numbers?: any };
const ORDER = { critical: 0, warning: 1, info: 2 };

// المقارنة بالمتوسط اليومي علشان الفترة الحالية (لسه ماخلصتش) تتقارن بعدل بفترة سابقة كاملة
export async function alerts(ctx: Ctx, a: any) {
  const kind = a?.range === "week" ? "week" : "month";
  const today = localDate(ctx.now, ctx.tz);
  const A = rangeFor(kind, undefined, undefined, ctx.now, ctx.tz);
  const B = kind === "week" ? rangeFor("custom", addDays(A.fromDay, -7), addDays(A.fromDay, -1), ctx.now, ctx.tz) : rangeFor("last_month", undefined, undefined, ctx.now, ctx.tz);
  const elapsedA = Math.max(1, daysBetween(A.fromDay, A.toDay < today ? A.toDay : today));
  const lenB = daysBetween(B.fromDay, B.toDay);
  const [oa, ob, ea, eb, at] = await Promise.all([
    rpc(ctx, "ai_overview", base(A)), rpc(ctx, "ai_overview", base(B)),
    rpc(ctx, "ai_expenses", { ...base(A), p_names: false }), rpc(ctx, "ai_expenses", { ...base(B), p_names: false }),
    rpc(ctx, "ai_attendance", base(A)).catch(() => null),
  ]);
  const f: Finding[] = [], gaps: string[] = [];
  const revA = Number(oa.revenue || 0), revB = Number(ob.revenue || 0);
  const rdA = revA / elapsedA, rdB = revB / lenB;
  if (!ob.invoices) gaps.push("الفترة السابقة فيها صفر فواتير — مقارنة الإيراد مش ممكنة.");
  else if (rdB > 0 && elapsedA >= 2) {
    const ch = Math.round(((rdA - rdB) / rdB) * 1000) / 10;
    if (ch <= -40) f.push({ severity: "critical", code: "revenue_drop", message: `متوسط الإيراد اليومي نزل ${Math.abs(ch)}% عن الفترة السابقة (${J(rdA)} مقابل ${J(rdB)} يوميًا).`, numbers: { per_day_now: fmt(rdA), per_day_before: fmt(rdB), change_pct: ch } });
    else if (ch <= -20) f.push({ severity: "warning", code: "revenue_drop", message: `متوسط الإيراد اليومي نزل ${Math.abs(ch)}% (${J(rdA)} مقابل ${J(rdB)} يوميًا).`, numbers: { per_day_now: fmt(rdA), per_day_before: fmt(rdB), change_pct: ch } });
    else if (ch >= 20) f.push({ severity: "info", code: "revenue_up", message: `متوسط الإيراد اليومي زاد ${ch}% (${J(rdA)} مقابل ${J(rdB)} يوميًا).`, numbers: { change_pct: ch } });
  }
  if (Number(oa.profit) < 0 && oa.invoices) f.push({ severity: "critical", code: "loss", message: `الفترة الحالية خسارة: الربح ${J(Number(oa.profit))} (إيراد ${J(revA)} ومصروفات وتكلفة موظفين أكتر منه).`, numbers: { profit: fmt(oa.profit) } });
  // قفزة بند مصروفات: بمعدل يومي
  const prev = new Map<string, number>(); for (const x of eb.by_category || []) prev.set(x.category, Number(x.total));
  for (const x of ea.by_category || []) {
    const cur = Number(x.total), before = prev.get(x.category) ?? 0, curD = cur / elapsedA, bD = before / lenB;
    if (cur >= 300 && (bD === 0 ? cur >= 1000 : curD >= bD * 1.5 && (curD - bD) * elapsedA >= 300)) f.push({ severity: "warning", code: "expense_spike", message: `مصروفات «${x.category}» أعلى من المعتاد: ${J(cur)} في ${elapsedA} يوم مقابل ${J(before)} في الفترة السابقة (${lenB} يوم).`, numbers: { category: x.category, now: fmt(cur), before: fmt(before) } });
  }
  const debt = Number(oa.outstanding_debt_total_now || 0);
  if (debt >= 500 && revA > 0 && debt > revA * 0.15) f.push({ severity: "warning", code: "debt_high", message: `الديون المستحقة على العملاء ${J(debt)} (أكتر من 15% من إيراد الفترة).`, numbers: { debt: fmt(debt), revenue: fmt(revA) } });
  const late = ((at?.staff as any[]) || []).filter((s) => Number(s.late_minutes) >= 60).map((s) => ({ name: s.name, late_minutes: Number(s.late_minutes) }));
  if (late.length) f.push({ severity: "info", code: "late_staff", message: `موظفين تأخيرهم 60 دقيقة أو أكتر: ${late.map((x) => `${x.name} (${x.late_minutes} د)`).join("، ")}.`, numbers: { staff: late } });
  if (!oa.invoices) gaps.push("مفيش فواتير في الفترة الحالية لحد دلوقتي.");
  if (elapsedA < 3) gaps.push("الفترة لسه في أولها — النسب ممكن تتغير بسرعة.");
  f.sort((x, y) => ORDER[x.severity] - ORDER[y.severity]);
  return {
    current_period: `${A.fromDay} → ${A.toDay} (عدّى ${elapsedA} يوم)`, previous_period: `${B.fromDay} → ${B.toDay} (${lenB} يوم)`,
    source: "ai_overview + ai_expenses + ai_attendance للفترتين", method: "المقارنة بالمتوسط اليومي (إيراد ÷ الأيام اللي عدّت) علشان الفترة الحالية لسه ماخلصتش. العتبات: نزول الإيراد ≥20% تحذير و≥40% حرج، بند مصروفات ≥1.5× المعدل اليومي السابق وبفرق 300 جنيه على الأقل، ديون >15% من الإيراد. مفيش تنبيه من غير أرقام.",
    data: { findings: f, count: f.length, revenue_now: fmt(revA), profit_now: fmt(oa.profit) }, data_gaps: gaps,
    note: f.length ? undefined : "مفيش حاجة غير طبيعية بالعتبات دي.",
  };
}

// متوسط الإيراد لكل يوم من أيام الأسبوع في آخر 90 يوم (الأيام اللي فيها مبيعات بس)
export async function weekdayPattern(ctx: Ctx, _a: any) {
  const today = localDate(ctx.now, ctx.tz);
  const r = rangeFor("custom", addDays(today, -90), today, ctx.now, ctx.tz);
  const o = await rpc(ctx, "ai_daily_series", base(r));
  const days: { day: string; revenue: number }[] = (o.days || []).map((d: any) => ({ day: String(d.day).slice(0, 10), revenue: Number(d.revenue || 0) }));
  const g: Record<number, number[]> = {};
  for (const d of days) (g[dow(d.day)] ||= []).push(d.revenue);
  const rows = [0, 1, 2, 3, 4, 5, 6].map((k) => { const v = g[k] || []; const sum = v.reduce((s, x) => s + x, 0); return { weekday: DAY_AR[k], days_counted: v.length, avg_revenue: v.length ? fmt(sum / v.length) : null }; });
  const ok = rows.filter((x) => x.avg_revenue !== null && x.days_counted >= 3).sort((x, y) => (y.avg_revenue as number) - (x.avg_revenue as number));
  const gaps: string[] = [];
  if (!days.length) gaps.push("مفيش مبيعات في آخر 90 يوم.");
  if (rows.some((x) => x.days_counted > 0 && x.days_counted < 3)) gaps.push("بعض الأيام عينتها أقل من 3 أسابيع — متقارنش بيها بثقة.");
  const todayAvg = rows[dow(today)];
  return {
    period: `${r.fromDay} → ${r.toDay}`, source: "ai_daily_series (الإيراد اليومي)", method: "متوسط إيراد اليوم = مجموع إيراد كل مرة اتباع فيها في اليوم ده ÷ عدد المرات. الأيام اللي مفيهاش مبيعات (أجازة أو إغلاق) مش داخلة في المتوسط.",
    data: { weekdays: rows, best_weekday: ok[0] || null, weakest_weekday: ok.length > 1 ? ok[ok.length - 1] : null, today_weekday_avg: todayAvg }, data_gaps: gaps,
  };
}

// توقّع آخر الشهر بمعدل الأيام اللي عدّت (تقدير مش وعد)
export async function forecast(ctx: Ctx, _a: any) {
  const today = localDate(ctx.now, ctx.tz);
  const M = rangeFor("month", undefined, undefined, ctx.now, ctx.tz), L = rangeFor("last_month", undefined, undefined, ctx.now, ctx.tz);
  const [cur, last] = await Promise.all([rpc(ctx, "ai_daily_series", base(M)), rpc(ctx, "ai_overview", base(L))]);
  const days: any[] = cur.days || [];
  const sofar = days.reduce((s, d) => s + Number(d.revenue || 0), 0);
  const elapsed = Math.max(1, daysBetween(M.fromDay, today)), total = daysBetween(M.fromDay, M.toDay), left = total - elapsed;
  const active = days.length;
  const byCalendar = (sofar / elapsed) * total, byActive = active ? (sofar / active) * (active + Math.round(left * (active / elapsed))) : null;
  const gaps: string[] = [];
  if (elapsed < 5) gaps.push("الشهر لسه في أوله (أقل من 5 أيام) — التوقّع ضعيف.");
  if (!active) gaps.push("مفيش مبيعات الشهر ده لحد دلوقتي.");
  return {
    month: `${M.fromDay} → ${M.toDay}`, source: "ai_daily_series للشهر + ai_overview للشهر اللي فات", method: "تقدير بمعدل الأيام: (الإيراد لحد دلوقتي ÷ الأيام اللي عدّت) × أيام الشهر. تقدير تاني بنسبة أيام الشغل الفعلية. مش وعد، والمواسم والأجازات ممكن تغيّره.",
    data: { revenue_so_far: fmt(sofar), days_elapsed: elapsed, days_left: left, active_days: active, projection_calendar_rate: fmt(byCalendar), projection_active_days_rate: byActive === null ? null : fmt(byActive), last_month_revenue: fmt(last.revenue), vs_last_month_pct: last.revenue ? Math.round(((byCalendar - Number(last.revenue)) / Number(last.revenue)) * 1000) / 10 : null },
    data_gaps: gaps,
  };
}

export const INSIGHT_TOOLS = [
  { name: "alerts", description: "تنبيهات الأداء غير الطبيعي: نزول الإيراد، خسارة، قفزة بند مصروفات، ديون عالية، تأخير موظفين. range: week أو month (الافتراضي month). استخدمها لما المالك يسأل «فيه حاجة غلط؟» أو «إيه الجديد؟».", input_schema: { type: "object", properties: { range: { type: "string", enum: ["week", "month"] } } } },
  { name: "weekday_pattern", description: "متوسط الإيراد لكل يوم من أيام الأسبوع في آخر 90 يوم، وأقوى وأضعف يوم. للأسئلة زي «أحسن يوم عندي» و«أنهي يوم ضعيف».", input_schema: { type: "object", properties: {} } },
  { name: "forecast", description: "توقّع إيراد آخر الشهر بمعدل الأيام اللي عدّت ومقارنته بالشهر اللي فات. اذكر إنه تقدير.", input_schema: { type: "object", properties: {} } },
];
export const INSIGHT_HANDLERS: Record<string, (ctx: Ctx, a: any) => Promise<any>> = { alerts, weekday_pattern: weekdayPattern, forecast };
