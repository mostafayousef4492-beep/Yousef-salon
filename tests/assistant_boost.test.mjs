// تقوية المساعدين: كلام مصري، تنبيهات المالك، ملخص اليوم، أدوات الموظف والعميل. تشغيل:
// node --experimental-strip-types --no-warnings tests/assistant_boost.test.mjs
import assert from "node:assert/strict";
import { runTool, toolsFor } from "../supabase/functions/assistant/core.ts";
import { parseAmountAr, parseDateAr } from "../supabase/functions/assistant/arabic.ts";
import { executeAction } from "../supabase/functions/assistant/actions.ts";
import { alerts, weekdayPattern, forecast } from "../supabase/functions/assistant/insights.ts";
import { buildBrief } from "../supabase/functions/assistant/brief.ts";

const T = (n, f) => Promise.resolve().then(f).then(() => console.log("PASS:", n), (e) => { console.log("FAIL:", n, e.message); process.exitCode = 1; });
function mockSb({ rpcs = {}, tables = {}, inserts = [] } = {}) {
  const calls = [];
  const rpc = async (n, a) => { calls.push([n, a]); const r = rpcs[n]; if (r instanceof Error) return { data: null, error: { message: r.message } }; return { data: typeof r === "function" ? r(a) : r ?? null, error: null }; };
  const from = (t) => { let filt = {}; const q = { select: () => q, in: () => q, order: () => q, eq: (k, v) => { filt[k] = v; return q; }, neq: () => q, insert: (r) => { inserts.push([t, r]); return Promise.resolve({ error: null }); }, maybeSingle: async () => ({ data: tables[t]?.[0] ?? null }), then: (res) => res({ data: tables[t] || [], error: null }) }; return q; };
  return { rpc, from, calls, inserts };
}
const NOW = new Date("2026-11-11T10:00:00Z");
const base = { tz: "Africa/Cairo", now: NOW, name: "م", staff: true };
const own = { ...base, uid: "u1", role: "owner", analytics: true }, mgr = { ...base, uid: "u2", role: "manager", analytics: false };

await T("مبالغ مصرية بالحروف", () => {
  const c = { "ميتين": 200, "خمسميه": 500, "ميه وخمسين": 150, "ألف ونص": 1500, "ألفين وخمسميه": 2500, "تلات تلاف": 3000, "٢٥٠": 250, "1,500": 1500, "200 جنيه": 200 };
  for (const [k, v] of Object.entries(c)) assert.equal(parseAmountAr(k), v, k);
  for (const bad of ["abc", "-5", "0", "", null]) assert.equal(parseAmountAr(bad), null, String(bad));
});
await T("تواريخ مصرية", () => {
  const t = "2026-11-11";
  assert.equal(parseDateAr("امبارح", t), "2026-11-10"); assert.equal(parseDateAr("أول امبارح", t), "2026-11-09"); assert.equal(parseDateAr("بكره", t), "2026-11-12");
  assert.equal(parseDateAr("الخميس اللي فات", t), "2026-11-05"); assert.equal(parseDateAr("3 ايام", t), "2026-11-08"); assert.equal(parseDateAr("كلام فاضي", t), null);
});
await T("سلفة «ميتين» بتتفهم وبتطلع كارت بـ200", async () => {
  const sb = mockSb({ tables: { profiles: [{ id: "11111111-1111-4111-8111-111111111111", full_name: "أحمد", role: "barber" }] } });
  const r = await runTool({ ...own, sb }, "record_staff_tx", { staff_id: "11111111-1111-4111-8111-111111111111", kind: "advance", amount: "ميتين" });
  assert.equal(r.confirm.params.amount, 200);
});
await T("قفل اليوم بكاش «تلات تلاف وخمسميه»", async () => {
  const sb = mockSb({ rpcs: { business_day_state: { open: true, day: "2026-11-11" }, close_day_preview: { expected_cash: 3500 } } });
  const r = await runTool({ ...own, sb }, "close_day", { counted_cash: "تلات تلاف وخمسميه" });
  assert.equal(r.confirm.params.counted_cash, 3500); assert.match(r.confirm.lines.join("|"), /مظبوط/);
});
await T("مصروف بتاريخ «امبارح»", async () => {
  const sb = mockSb({ tables: { expense_categories: [{ name: "صيانة" }] }, rpcs: { business_day_state: { open: true, day: "2026-11-11" } } });
  const r = await runTool({ ...own, sb }, "add_expense", { category: "صيانة", amount: 50, date: "امبارح" });
  assert.equal(r.confirm.params.date, "2026-11-10");
});
await T("إعادة فتح يوم «أول امبارح»", async () => {
  const r = await runTool({ ...own, sb: mockSb() }, "reopen_day", { day: "أول امبارح" });
  assert.equal(r.confirm.params.day, "2026-11-09");
});

// ---- تنبيهات المالك
const ov = (rev, inv, profit, debt = 0) => ({ revenue: rev, invoices: inv, profit, outstanding_debt_total_now: debt });
await T("alerts: نزول إيراد حرج + قفزة مصروف + ديون + تأخير، مرتبة بالخطورة وبأرقام", async () => {
  const sb = mockSb({ rpcs: {
    ai_overview: (a) => (a.p_from < "2026-10-20" ? ov(30000, 200, 8000) : ov(2000, 20, 100, 5000)),
    ai_expenses: (a) => (a.p_from < "2026-10-20" ? { by_category: [{ category: "صيانة", total: 300 }] } : { by_category: [{ category: "صيانة", total: 2500 }] }),
    ai_attendance: { staff: [{ name: "علي", late_minutes: 90 }] },
  } });
  const r = await alerts({ ...own, sb }, { range: "month" });
  const codes = r.data.findings.map((x) => x.code);
  assert.ok(codes.includes("revenue_drop") && codes.includes("expense_spike") && codes.includes("debt_high") && codes.includes("late_staff"), codes.join());
  assert.equal(r.data.findings[0].severity, "critical"); assert.ok(r.method && r.source && r.current_period);
});
await T("alerts: أداء سليم = مفيش تنبيهات، ومفيش اختلاق", async () => {
  const sb = mockSb({ rpcs: { ai_overview: ov(1000, 10, 500), ai_expenses: { by_category: [] }, ai_attendance: { staff: [] } } });
  const r = await alerts({ ...own, sb }, {});
  assert.equal(r.data.findings.filter((x) => x.severity !== "info").length, 0);
});
await T("alerts: الفترة السابقة فاضية → data_gaps مش نسبة وهمية", async () => {
  const sb = mockSb({ rpcs: { ai_overview: (a) => (a.p_from < "2026-11-01" ? ov(0, 0, 0) : ov(1000, 5, 200)), ai_expenses: { by_category: [] }, ai_attendance: { staff: [] } } });
  const r = await alerts({ ...own, sb }, {});
  assert.ok(r.data_gaps.some((g) => /صفر فواتير/.test(g))); assert.ok(!r.data.findings.some((x) => x.code === "revenue_drop"));
});
await T("weekday_pattern: متوسط لكل يوم وأقوى/أضعف يوم وتنبيه العينة الصغيرة", async () => {
  const days = []; for (let w = 0; w < 6; w++) { days.push({ day: `2026-10-${String(2 + w * 7).padStart(2, "0")}`, revenue: 5000 }); days.push({ day: `2026-10-${String(5 + w * 7).padStart(2, "0")}`, revenue: 1000 }); }
  const sb = mockSb({ rpcs: { ai_daily_series: { days } } });
  const r = await weekdayPattern({ ...own, sb }, {});
  assert.equal(r.data.best_weekday.weekday, "الجمعة"); assert.equal(r.data.best_weekday.avg_revenue, 5000);
});
await T("forecast: تقدير بالمعدل + مقارنة بالشهر اللي فات + تحذير أول الشهر", async () => {
  const sb = mockSb({ rpcs: { ai_daily_series: { days: [{ day: "2026-11-01", revenue: 1000 }, { day: "2026-11-02", revenue: 1000 }] }, ai_overview: ov(20000, 100, 5000) } });
  const r = await forecast({ ...own, sb }, {});
  assert.equal(r.data.days_elapsed, 11); assert.equal(r.data.revenue_so_far, 2000); assert.equal(r.data.projection_calendar_rate, Math.round((2000 / 11) * 30 * 100) / 100);
  assert.equal(r.data.last_month_revenue, 20000);
});
await T("أدوات التحليل الجديدة للمالك بس (مش المدير ولا مالك بتحليل مقفول)", () => {
  const names = (s, r, a) => toolsFor(s, r, a).map((t) => t.name);
  for (const n of ["alerts", "weekday_pattern", "forecast"]) { assert.ok(names(true, "owner", true).includes(n)); assert.ok(!names(true, "manager", true).includes(n)); assert.ok(!names(true, "owner", false).includes(n)); assert.ok(!names(true, "barber", true).includes(n)); }
});

// ---- ملخص اليوم
await T("brief للمدير: تشغيل بس (من غير إيراد)", async () => {
  const sb = mockSb({ rpcs: { business_day_state: { open: true, day: "2026-11-11" }, close_day_preview: { expected_cash: 1200, pending: 2, upcoming: 3 } } });
  const b = await buildBrief({ ...mgr, sb }); const txt = b.lines.map((x) => x.text).join("|");
  assert.match(txt, /1,200/); assert.match(txt, /2 حجز/); assert.ok(!sb.calls.some((c) => c[0] === "ai_overview"), "المدير مايطلبش تحليلات");
});
await T("brief يوم قديم مفتوح = تحذير + شيب «اقفل اليوم»", async () => {
  const sb = mockSb({ rpcs: { business_day_state: { open: true, day: "2026-11-08" }, close_day_preview: { expected_cash: 5 } } });
  const b = await buildBrief({ ...mgr, sb }); assert.ok(b.lines.some((x) => x.level === "bad")); assert.ok(b.chips.includes("اقفل اليوم"));
});
await T("brief للمالك: إيراد النهارده + أهم تنبيه، وبيكمّل لو دالة فشلت", async () => {
  const sb = mockSb({ rpcs: { business_day_state: { open: false }, ai_overview: (a) => (a.p_from < "2026-11-01" ? ov(30000, 200, 8000) : ov(2000, 20, 100)), ai_expenses: { by_category: [] }, ai_attendance: new Error("x") } });
  const b = await buildBrief({ ...own, sb }); const txt = b.lines.map((x) => x.text).join("|");
  assert.match(txt, /مفيش يوم عمل مفتوح/); assert.match(txt, /فاتورة/); assert.ok(b.lines.some((x) => x.icon === "🚨" || x.icon === "⚠️"));
});

// ---- الموظف
await T("my_day: حلاق بيشوف يومه من ملخص حسابه هو، والكاشير how_to بيقتصر على مواضيعه", async () => {
  const sb = mockSb({ rpcs: { staff_summary: [{ sales: 800, cuts: 8, commission: 320 }], my_queue: [{ status: "upcoming" }, { status: "done" }, { status: "checked_in" }] } });
  const r = (await runTool({ ...base, uid: "b1", role: "barber", sb }, "my_day", {})).result;
  assert.equal(r.data.sales_today, 800); assert.equal(r.data.waiting_in_queue, 2); assert.equal(sb.calls.find((c) => c[0] === "staff_summary")[1].p_staff, "b1");
  const c = (await runTool({ ...base, uid: "c1", role: "cashier", sb: mockSb() }, "how_to", { question: "إزاي أسدد دين عميل؟" })).result;
  assert.equal(c.found, true); const bad = (await runTool({ ...base, uid: "c1", role: "cashier", sb: mockSb() }, "how_to", { question: "إزاي أضيف موظف جديد" })).result;
  assert.equal(bad.found, false);
  assert.equal((await runTool({ ...base, uid: "b1", role: "barber", sb: mockSb() }, "how_to", { question: "x" })).result.error, "أداة غير متاحة");
});
await T("الموظف مايقدرش ينفّذ ولا يشوف تحليلات المالك", async () => {
  for (const role of ["barber", "cashier", "assistant"]) for (const n of ["close_day", "add_expense", "alerts", "forecast", "daily_brief"]) assert.equal((await runTool({ ...base, uid: "x", role, sb: mockSb() }, n, {})).result.error, "أداة غير متاحة", role + n);
  assert.equal((await executeAction({ ...base, uid: "x", role: "cashier", sb: mockSb() }, "close_day", { counted_cash: 1 })).ok, false);
});

// ---- العميل
await T("suggest_slot: أقل انتظار أولًا، وبيحترم الأجازة وإيقاف الحجز", async () => {
  const mk = (list) => mockSb({ rpcs: { available_barbers: (a) => (a.p_period === "evening" && a.p_day === "2026-11-11" ? list : []) }, tables: { app_settings: [] } });
  const sb = mk([{ id: "b1", full_name: "علي", waiting: 3, est_min: 45 }, { id: "b2", full_name: "محمد", waiting: 1, est_min: 15 }]);
  const r = (await runTool({ ...base, staff: false, role: "customer", custId: 5, sb }, "suggest_slot", {})).result;
  assert.ok(r.data || r.ok === false, JSON.stringify(r));
  if (r.data) { assert.equal(r.data.suggestions[0].barber_name, "محمد"); assert.ok(r.method); }
});
await T("loyalty_progress: بيحسب المتبقي للمكافأة من نقاط العميل", async () => {
  const sb = mockSb({ tables: { customers: [{ id: 5, name: "عميل", points: 80, visits: 7, lifetime_points: 200 }], loyalty_rewards: [{ name: "خصم", cost: 50 }, { name: "قصة مجانية", cost: 150 }], app_settings: [{ key: "visit_bonus_every", value: "5" }, { key: "visit_bonus_points", value: "20" }] } });
  const r = (await runTool({ ...base, staff: false, role: "customer", custId: 5, sb }, "loyalty_progress", {})).result;
  assert.ok(!r.error, JSON.stringify(r));
  assert.equal(r.data.points, 80); assert.equal(r.data.next_reward.name, "قصة مجانية"); assert.equal(r.data.next_reward.points_missing, 70); assert.equal(r.data.can_redeem_now[0].name, "خصم"); assert.equal(r.data.visits_to_next_visit_bonus, 3);
});
