// اختبار مساعد الإدارة: الأدوات للقراءة بس + الصلاحيات + الخصوصية + الحسابات + الاستكشاف (drills).
// تشغيل: node --experimental-strip-types --no-warnings tests/assistant_admin.test.mjs
import assert from "node:assert/strict";
import { chat, runTool, toolsFor, systemPrompt, dedupeDrills } from "../supabase/functions/assistant/core.ts";
import { ACTION_NAMES } from "../supabase/functions/assistant/actions.ts";

const T = (n, f) => Promise.resolve().then(f).then(() => console.log("PASS:", n), (e) => { console.log("FAIL:", n, e.message); process.exitCode = 1; });

function mockSb({ tables = {}, rpcs = {} } = {}) {
  const calls = [];
  const from = (t) => {
    const q = { filters: [] };
    const b = new Proxy({}, { get(_, k) {
      if (k === "then") return (res) => { calls.push(["from", t, q.filters]); return res({ data: tables[t] ?? [], error: null }); };
      return (...a) => { q.filters.push([k, ...a]); return b; };
    } });
    return b;
  };
  const rpc = async (n, a) => { calls.push(["rpc", n, a]); const r = rpcs[n]; return { data: typeof r === "function" ? r(a) : r ?? null, error: null }; };
  return { from, rpc, calls };
}
const NOW = new Date("2026-11-09T10:00:00Z");
const adm = { uid: "own-1", tz: "Africa/Cairo", now: NOW, name: "مصطفى", role: "owner", staff: true };

const OV = (rev, n, exp, prof) => ({ revenue: rev, invoices: n, avg_invoice: n ? rev / n : null, cogs: 0, expenses: exp, staff_cost: 10, commissions: 5, salaries: 5, bonuses: 0, deductions: 0, profit: prof, unpaid_created_in_range: 0, outstanding_debt_total_now: 0, by_pay: [{ m: "cash", n, t: rev }], staff: [{ id: "b1", name: "أحمد", role: "barber", sales: 700, cuts: 7, commission: 100 }, { id: "b2", name: "محمود", role: "barber", sales: 300, cuts: 3, commission: 50 }, { id: "c", name: "كاشير", role: "cashier", sales: 0, cuts: 0, commission: 0 }] });

await T("الأدوات: كلها قراءة فقط (مفيش اسم بيدل على تعديل/إرسال)", () => {
  const names = toolsFor(true, "owner").map((t) => t.name);
  assert.ok(names.includes("overview") && names.includes("compare_periods") && names.includes("list_invoices"));
  for (const n of names.filter((x) => !ACTION_NAMES.includes(x))) assert.ok(!/(create|delete|update|insert|send|write|close|pay|book|set_|remove|edit)/i.test(n), n);
});
await T("الحلاق/الكاشير/العميل مالهمش أدوات الإدارة، ومفيش نداء للقاعدة", async () => {
  for (const [staff, role] of [[true, "barber"], [true, "cashier"], [false, "customer"], [true, "assistant"]]) {
    const sb = mockSb();
    const r = await runTool({ ...adm, sb, staff, role }, "overview", {});
    assert.match(r.result.error, /غير متاحة/); assert.equal(sb.calls.length, 0);
  }
});
await T("المالك مالوش أدوات الموظف الشخصية (my_money) ولا الحجز", async () => {
  const sb = mockSb();
  assert.match((await runTool({ ...adm, sb }, "my_money", {})).result.error, /غير متاحة/);
  assert.match((await runTool({ ...adm, sb }, "propose_booking", {})).result.error, /غير متاحة/);
});
await T("overview: الفترة والمصدر وطريقة الحساب موجودين، والأرقام مطابقة للدالة", async () => {
  const sb = mockSb({ rpcs: { ai_overview: OV(1000, 10, 200, 500) } });
  const r = (await runTool({ ...adm, sb }, "overview", { range: "month" })).result;
  assert.equal(r.period, "2026-11-01 → 2026-11-30"); assert.ok(r.source && r.method);
  assert.equal(r.data.revenue, 1000); assert.equal(r.data.profit, 500); assert.equal(r.data.avg_invoice, 100);
  const c = sb.calls.find((x) => x[1] === "ai_overview"); assert.equal(c[2].p_from, "2026-10-31T22:00:00.000Z");
});
await T("overview: صفر فواتير = تصريح واضح إن البيانات غير كافية", async () => {
  const sb = mockSb({ rpcs: { ai_overview: OV(0, 0, 0, 0) } });
  const r = (await runTool({ ...adm, sb }, "overview", { range: "today" })).result;
  assert.ok(r.data_gaps.length && /مفيش فواتير/.test(r.data_gaps[0]));
});
await T("compare_periods: الفروق والنسب بالكود + تنبيه اختلاف الطول", async () => {
  const sb = mockSb({ rpcs: { ai_overview: (a) => (a.p_from.startsWith("2026-10-31") ? OV(1200, 12, 300, 600) : OV(1000, 10, 200, 500)), ai_expenses: (a) => ({ by_category: a.p_from.startsWith("2026-10-31") ? [{ category: "إيجار", total: 300 }] : [{ category: "إيجار", total: 200 }, { category: "كهرباء", total: 50 }] }) } });
  const r = (await runTool({ ...adm, sb }, "compare_periods", { a_range: "month", b_range: "last_month" })).result;
  assert.equal(r.data.delta.revenue.diff, 200); assert.equal(r.data.delta.revenue.change_pct, 20);
  assert.equal(r.data.delta.revenue.current, 1200); assert.equal(r.data.delta.revenue.previous, 1000);
});
await T("compare_periods: نسبة التغيير صح + بنود المصروفات مرتبة بأكبر فرق", async () => {
  const sb = mockSb({ rpcs: { ai_overview: (a) => (a.p_from.startsWith("2026-11") || a.p_from.startsWith("2026-10-31") ? OV(1500, 10, 400, 700) : OV(1000, 10, 200, 500)), ai_expenses: (a) => ({ by_category: a.p_from.startsWith("2026-10-31") ? [{ category: "إيجار", total: 300 }, { category: "كهرباء", total: 100 }] : [{ category: "إيجار", total: 190 }, { category: "كهرباء", total: 10 }] }) } });
  const r = (await runTool({ ...adm, sb }, "compare_periods", { a_range: "month", b_range: "custom", b_from: "2026-10-01", b_to: "2026-10-31" })).result;
  assert.equal(r.data.delta.revenue.change_pct, 50); assert.equal(r.data.delta.revenue.diff, 500);
  assert.equal(r.data.expense_by_category[0].category, "إيجار");
});
await T("compare_periods: فترتين مختلفين الطول = تحذير", async () => {
  const sb = mockSb({ rpcs: { ai_overview: OV(100, 1, 0, 100), ai_expenses: { by_category: [] } } });
  const r = (await runTool({ ...adm, sb }, "compare_periods", { a_range: "today", b_range: "month" })).result;
  assert.ok(r.data_gaps.some((g) => /مختلفين في الطول/.test(g)));
});
await T("الخصوصية: كل نداءات القاعدة من المساعد بدون أسماء/ملاحظات (p_names=false)", async () => {
  const sb = mockSb({ rpcs: { ai_overview: OV(1, 1, 0, 1), ai_expenses: { total: 0, by_category: [], largest: [] }, ai_customers: { top_spenders: [{ customer_id: 7, spent: 90, invoices: 2 }] }, ai_invoices: { matching: 0 }, ai_items_rank: { items: [] }, ai_purchases: {}, ai_appointments: {}, ai_attendance: {}, ai_daily_series: { days: [] } }, tables: { profiles: [{ id: "b1", full_name: "أحمد", role: "barber" }] } });
  for (const [n, a] of [["overview", {}], ["expenses_breakdown", {}], ["customers_summary", {}], ["list_invoices", { barber_name: "أحمد" }], ["top_items", {}], ["purchases_summary", {}], ["appointments_summary", {}], ["attendance_summary", {}], ["daily_sales", {}], ["compare_periods", { a_range: "month", b_range: "last_month" }]]) await runTool({ ...adm, sb }, n, a);
  for (const c of sb.calls.filter((x) => x[0] === "rpc" && "p_names" in (x[2] || {}))) assert.equal(c[2].p_names, false, c[1]);
  assert.ok(sb.calls.filter((x) => x[1] === "ai_invoices" || x[1] === "ai_customers" || x[1] === "ai_expenses").every((c) => c[2].p_names === false));
  const cs = (await runTool({ ...adm, sb }, "customers_summary", {})).result;
  assert.equal(cs.data.top_spenders[0].customer, "عميل #7");
  assert.ok(!sb.calls.some((x) => x[0] === "from" && x[1] === "customers"));
});
await T("list_invoices: بيحوّل اسم الحلاق لـ id، ويرفض الاسم المتكرر أو المجهول", async () => {
  const sb = mockSb({ rpcs: { ai_invoices: { matching: 2, matching_total: 300, invoices: [] } }, tables: { profiles: [{ id: "b1", full_name: "أحمد", role: "barber" }] } });
  await runTool({ ...adm, sb }, "list_invoices", { barber_name: "أحمد", range: "week" });
  assert.equal(sb.calls.find((x) => x[1] === "ai_invoices")[2].p_barber, "b1");
  const dup = mockSb({ tables: { profiles: [{ id: "1", full_name: "أحمد علي" }, { id: "2", full_name: "أحمد سعيد" }] } });
  assert.match((await runTool({ ...adm, sb: dup }, "list_invoices", { barber_name: "أحمد" })).result.error, /أكتر من موظف/);
  const none = mockSb({ tables: { profiles: [] } });
  assert.match((await runTool({ ...adm, sb: none }, "list_invoices", { barber_name: "س" })).result.error, /مفيش موظف/);
});
await T("خطأ القاعدة (غير مصرح) بيتحوّل لخطأ واضح من غير تسريب", async () => {
  const sb = { from: () => ({}), rpc: async () => ({ data: null, error: { message: "غير مصرح" } }) };
  assert.equal((await runTool({ ...adm, sb }, "overview", {})).result.error, "غير مصرح");
});
await T("barbers_ranking: الأعلى مبيعات + متوسط القصة + أزرار الاستكشاف", async () => {
  const sb = mockSb({ rpcs: { ai_overview: OV(1000, 10, 0, 1) } });
  const out = await runTool({ ...adm, sb }, "barbers_ranking", {});
  assert.equal(out.result.data.ranking.length, 2); assert.equal(out.result.data.ranking[0].avg_per_cut, 100);
  assert.equal(out.drills[0].barber_id, "b1");
});
await T("dedupeDrills: بيشيل المكرر والتواريخ الغلط ويحدد 6", () => {
  const d = { label: "x", from: "2026-11-01T00:00:00Z", to: "2026-12-01T00:00:00Z" };
  assert.equal(dedupeDrills([d, d, { ...d, from: "bad" }, null]).length, 1);
  assert.equal(dedupeDrills(Array.from({ length: 10 }, (_, i) => ({ ...d, service: "s" + i }))).length, 6);
});
await T("البرومبت: للإدارة بيلزم الفترة/المصدر/الطريقة ومفيش «بيانات المستخدم بس»", () => {
  const p = systemPrompt({ ...adm });
  assert.match(p, /الفترة/); assert.match(p, /المصدر/); assert.match(p, /مش كافية/); assert.ok(!/مسموحلك بس بيانات المستخدم/.test(p));
  assert.match(p, /بتحلل وبتنفّذ بدل المالك/);
});
await T("حلقة الدردشة: الإدارة بتشغّل أدوات، وبترجع drills، ومفيش drill/ISO في اللي بيروح للنموذج", async () => {
  const sb = mockSb({ rpcs: { ai_overview: OV(1000, 10, 200, 500) } });
  let seen = null, step = 0;
  const llm = async (_s, msgs, tools) => {
    assert.ok(tools.some((t) => t.name === "overview"));
    if (step++ === 0) return { stop_reason: "tool_use", content: [{ type: "tool_use", id: "t1", name: "overview", input: { range: "month" } }] };
    seen = msgs[msgs.length - 1].content[0].content;
    return { stop_reason: "end_turn", content: [{ type: "text", text: "الإيراد 1000" }] };
  };
  const r = await chat({ ...adm, sb }, [{ role: "user", content: "إيراد الشهر ده كام؟" }], llm);
  assert.equal(r.reply, "الإيراد 1000"); assert.equal(r.drills.length, 1);
  assert.ok(!/"drill"/.test(seen)); assert.ok(/"revenue":1000/.test(seen));
});
await T("مفيش كتابة: مفيش أي نداء قاعدة غير ai_*/profiles قراءة", async () => {
  const sb = mockSb({ rpcs: { ai_overview: OV(1, 1, 0, 1), ai_expenses: { by_category: [] }, ai_items_rank: { items: [] }, ai_purchases: {}, ai_customers: {}, ai_appointments: {}, ai_attendance: {}, ai_daily_series: {}, ai_invoices: {} } });
  for (const t of toolsFor(true, "manager")) await runTool({ ...adm, role: "manager", sb }, t.name, { a_range: "month", b_range: "last_month" });
  for (const c of sb.calls.filter((x) => x[0] === "rpc")) assert.ok(c[1].startsWith("ai_") || c[1] === "business_day_state", c[1]);
});
await T("overview: لو الدالة رجّعت صفر فواتير والجدول فيه فواتير → خطأ تناقض مش «مفيش مبيعات»", async () => {
  const sb = mockSb({ rpcs: { ai_overview: OV(0, 0, 0, 0) } });
  const base = sb.from; sb.from = (t) => { const b = base(t); if (t !== "invoices") return b; const p = new Proxy({}, { get: (_, k) => k === "then" ? (res) => res({ data: null, count: 162, error: null }) : () => p }); return p; };
  const out = await runTool({ ...adm, sb }, "overview", { range: "month" });
  assert.ok(/تناقض/.test(JSON.stringify(out)), JSON.stringify(out).slice(0, 200));
  const sb2 = mockSb({ rpcs: { ai_overview: OV(0, 0, 0, 0) } });
  const ok = await runTool({ ...adm, sb: sb2 }, "overview", { range: "month" });
  assert.ok(!/تناقض/.test(JSON.stringify(ok)));
});
