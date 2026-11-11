// اختبار مساعد المدير (تشغيل): فصل الأدوات عن مساعد التحليل + دليل الخطوات + أرقام موظف + بيانات عميل + الخصوصية.
// تشغيل: node --experimental-strip-types --no-warnings tests/assistant_manager.test.mjs
import assert from "node:assert/strict";
import { chat, runTool, toolsFor, systemPrompt } from "../supabase/functions/assistant/core.ts";
import { ACTION_NAMES } from "../supabase/functions/assistant/actions.ts";
import { GUIDE, findTopics } from "../supabase/functions/assistant/guide.ts";

const T = (n, f) => Promise.resolve().then(f).then(() => console.log("PASS:", n), (e) => { console.log("FAIL:", n, e.message); process.exitCode = 1; });
function mockSb({ rpcs = {} } = {}) {
  const calls = [];
  const rpc = async (n, a) => { calls.push(["rpc", n, a]); const r = rpcs[n]; return { data: typeof r === "function" ? r(a) : r ?? null, error: null }; };
  const from = (t) => { calls.push(["from", t]); return new Proxy({}, { get: (_, k) => (k === "then" ? (res) => res({ data: [], error: null }) : () => from(t)) }); };
  return { rpc, from, calls };
}
const NOW = new Date("2026-11-09T10:00:00Z");
const mgr = { uid: "m-1", tz: "Africa/Cairo", now: NOW, name: "المدير", role: "manager", staff: true };
const own = { ...mgr, role: "owner", name: "المالك" };
const ANALYTICS = ["overview", "compare_periods", "top_items", "barbers_ranking", "daily_sales", "expenses_breakdown", "purchases_summary", "customers_summary", "appointments_summary", "attendance_summary", "list_invoices"];
const OPS = ["how_to", "find_staff", "staff_money", "staff_attendance", "find_customer", "customer_info"];

await T("المدير: أدوات التشغيل بس (مفيش أدوات التحليل)", () => {
  const n = toolsFor(true, "manager").map((t) => t.name);
  for (const x of OPS) assert.ok(n.includes(x), x);
  for (const x of ANALYTICS) assert.ok(!n.includes(x), x);
  assert.ok(n.includes("salon_info"));
});
await T("المالك: التحليل + التشغيل", () => {
  const n = toolsFor(true, "owner").map((t) => t.name);
  for (const x of [...ANALYTICS, ...OPS]) assert.ok(n.includes(x), x);
});
await T("كل الأدوات قراءة فقط (مفيش اسم بيدل على كتابة/إرسال)", () => {
  for (const t of toolsFor(true, "manager").filter((x) => !ACTION_NAMES.includes(x.name))) assert.ok(!/(create|delete|update|insert|send|write|close|pay_|book|set_|remove|edit|add_)/i.test(t.name), t.name);
});
await T("المدير مايقدرش يشغّل أداة تحليل (مفيش نداء قاعدة)", async () => {
  const sb = mockSb();
  for (const n of ANALYTICS) assert.match((await runTool({ ...mgr, sb }, n, {})).result.error, /غير متاحة/);
  assert.equal(sb.calls.length, 0);
});
await T("حلاق/كاشير/مساعد/عميل مالهمش أدوات المدير", async () => {
  for (const [staff, role] of [[true, "barber"], [true, "cashier"], [true, "assistant"], [false, "customer"]]) {
    const sb = mockSb();
    for (const n of OPS.filter((x) => !(x === "how_to" && role === "cashier"))) assert.match((await runTool({ ...mgr, sb, staff, role }, n, { question: "x", staff: "x", name: "x", query: "xx", customer_id: 1 })).result.error, /غير متاحة/);
    assert.equal(sb.calls.length, 0);
  }
});
await T("how_to: إزاي أضيف موظف → خطوات add_staff من الدليل", async () => {
  const r = (await runTool({ ...mgr, sb: mockSb() }, "how_to", { question: "إزاي أضيف موظف جديد؟" })).result;
  assert.equal(r.found, true); assert.equal(r.topics[0].id, "add_staff");
  assert.ok(r.topics[0].steps.some((s) => s.includes("إضافة موظف جديد")));
});
await T("how_to: قفل اليوم / سلفة / مصروف / دين بيوصلوا للموضوع الصح", async () => {
  const q = { "ازاي اقفل اليوم": "close_day", "عايز اسجل سلفة لمحمود": "staff_tx", "اضيف مصروف كهرباء": "add_expense", "عميل دفع جزء والباقي دين": "partial_pay", "افتح يوم جديد": "open_day", "اصرف مرتب": "pay_salary", "اضيف عميل جديد": "add_customer" };
  for (const [k, v] of Object.entries(q)) assert.equal(findTopics(k)[0]?.id, v, k);
});
await T("how_to: موضوع مش في الدليل → found=false + المواضيع المتاحة (من غير تخمين)", async () => {
  const r = (await runTool({ ...mgr, sb: mockSb() }, "how_to", { question: "إزاي أعمل نسخة احتياطية للسيرفر؟" })).result;
  assert.equal(r.found, false); assert.ok(r.available_topics.length === GUIDE.length); assert.match(r.note, /ماتخمنش/);
});
await T("الدليل: كل موضوع له خطوات، ومتلاقي بعنوانه، ومعرّفاته مش مكررة", () => {
  assert.equal(new Set(GUIDE.map((t) => t.id)).size, GUIDE.length);
  for (const t of GUIDE) { assert.ok(t.steps.length >= 2 && t.steps.every((s) => s.length > 10), t.id); assert.equal(findTopics(t.title)[0]?.id, t.id, t.title); }
});
await T("staff_money: اسم واحد → بيحوّله لـ id وينادي ai_staff_money بالفترة الصح", async () => {
  const sb = mockSb({ rpcs: { ai_find_staff: { staff: [{ id: "b1", name: "محمود", role: "barber", code: "102" }] }, ai_staff_money: { name: "محمود", role: "barber", commission_pct: 40, monthly_salary: 3000, summary: { sales: 5000, cuts: 40, commission: 2000, salary: 1500, bonuses: 30, advances: 300, deductions: 20, net: 3210 }, salary_paid_in_range: 500, balance_now: 2710, transactions: [{ kind: "advance", amount: 300, note: "سلفة", at: "2026-11-05T10:00:00Z" }] } } });
  const r = (await runTool({ ...mgr, sb }, "staff_money", { staff: "محمود", range: "month" })).result;
  const c = sb.calls.find((x) => x[1] === "ai_staff_money");
  assert.equal(c[2].p_staff, "b1"); assert.equal(c[2].p_from, "2026-10-31T22:00:00.000Z");
  assert.equal(r.employee, "محمود"); assert.equal(r.data.advances_withdrawals, 300); assert.equal(r.data.net_due, 3210); assert.equal(r.data.transactions[0].type, "سحب/سلفة");
  assert.ok(r.source && r.method && r.period === "2026-11-01 → 2026-11-30");
});
await T("staff_money: اسم متكرر → مرشحين من غير ما يجيب فلوس، ومجهول → خطأ واضح", async () => {
  const sb = mockSb({ rpcs: { ai_find_staff: { staff: [{ id: "1", name: "أحمد علي", role: "barber", code: "1" }, { id: "2", name: "أحمد سعيد", role: "barber", code: "2" }] } } });
  const r = (await runTool({ ...mgr, sb }, "staff_money", { staff: "أحمد" })).result;
  assert.equal(r.ambiguous, true); assert.equal(r.candidates.length, 2); assert.ok(!sb.calls.some((x) => x[1] === "ai_staff_money"));
  const sb2 = mockSb({ rpcs: { ai_find_staff: { staff: [] } } });
  assert.match((await runTool({ ...mgr, sb: sb2 }, "staff_money", { staff: "س" })).result.error, /مفيش موظف/);
  assert.match((await runTool({ ...mgr, sb: sb2 }, "staff_money", { staff: "  " })).result.error, /اكتب اسم/);
});
await T("staff_attendance: بيحوّل الاسم ويرجّع الحضور", async () => {
  const sb = mockSb({ rpcs: { ai_find_staff: { staff: [{ id: "b1", name: "أحمد", role: "barber" }] }, ai_staff_attendance: { name: "أحمد", days_present: 12, total_hours: 96, total_late_minutes: 25, records: [] } } });
  const r = (await runTool({ ...mgr, sb }, "staff_attendance", { staff: "أحمد", range: "last_month" })).result;
  assert.equal(r.data.days_present, 12); assert.equal(sb.calls.find((x) => x[1] === "ai_staff_attendance")[2].p_from, "2026-09-30T21:00:00.000Z");
});
await T("العملاء: find_customer ثم customer_info، ومفيش موبايل بيتضاف ولا قراءة مباشرة من جدول العملاء", async () => {
  const sb = mockSb({ rpcs: { ai_customer_find: { customers: [{ id: 7, name: "كريم", visits: 5, points: 120 }] }, ai_customer_info: { id: 7, name: "كريم", points: 120, visits: 5, total_spent: 900, debt_remaining: 50, has_phone: true } } });
  const f = (await runTool({ ...mgr, sb }, "find_customer", { query: "كريم" })).result;
  assert.equal(f.data.customers[0].id, 7);
  const i = (await runTool({ ...mgr, sb }, "customer_info", { customer_id: 7 })).result;
  assert.equal(i.data.debt_remaining, 50); assert.ok(!/01\d{9}/.test(JSON.stringify([f, i])));
  assert.ok(!sb.calls.some((x) => x[0] === "from"));
  assert.match((await runTool({ ...mgr, sb }, "customer_info", { customer_id: "abc" })).result.error, /customer_id/);
});
await T("خطأ القاعدة (غير مصرح) بيتحوّل لخطأ واضح", async () => {
  const sb = { from: () => ({}), rpc: async () => ({ data: null, error: { message: "غير مصرح" } }) };
  assert.equal((await runTool({ ...mgr, sb }, "find_customer", { query: "كريم" })).result.error, "غير مصرح");
});
await T("كل نداءات القاعدة من أدوات المدير ai_* بس (مفيش كتابة)", async () => {
  const sb = mockSb({ rpcs: { ai_find_staff: { staff: [{ id: "b1", name: "أحمد" }] }, ai_staff_money: { summary: {} }, ai_staff_attendance: {}, ai_customer_find: { customers: [] }, ai_customer_info: {} } });
  for (const [n, a] of [["how_to", { question: "قفل اليوم" }], ["find_staff", { name: "أ" }], ["staff_money", { staff: "أحمد" }], ["staff_attendance", { staff: "أحمد" }], ["find_customer", { query: "كريم" }], ["customer_info", { customer_id: 1 }]]) await runTool({ ...mgr, sb }, n, a);
  for (const c of sb.calls) assert.equal(c[0], "rpc"), assert.ok(c[1].startsWith("ai_"), c[1]);
});
await T("برومبت المدير: للقراءة والشرح، ممنوع التنفيذ، مفيش تليفونات، وبيلزم الدليل", () => {
  const p = systemPrompt({ ...mgr });
  assert.match(p, /how_to/); assert.match(p, /بتنفّذ بدل المدير/); assert.match(p, /تليفونات العملاء مش متاحة/); assert.match(p, /ماتخترعش أزرار/); assert.ok(!/overview/.test(p));
  assert.ok(!/مسموحلك بس بيانات المستخدم/.test(p));
});
await T("حلقة الدردشة: المدير بيسأل «إزاي أقفل اليوم» → how_to → رد بالخطوات", async () => {
  const sb = mockSb();
  let seen = null, step = 0;
  const llm = async (_s, msgs, tools) => {
    assert.ok(tools.some((t) => t.name === "how_to") && !tools.some((t) => t.name === "overview"));
    if (step++ === 0) return { stop_reason: "tool_use", content: [{ type: "tool_use", id: "t1", name: "how_to", input: { question: "إزاي أقفل اليوم" } }] };
    seen = msgs[msgs.length - 1].content[0].content;
    return { stop_reason: "end_turn", content: [{ type: "text", text: "1. دوس قفل اليوم" }] };
  };
  const r = await chat({ ...mgr, sb }, [{ role: "user", content: "إزاي أقفل اليوم" }], llm);
  assert.equal(r.reply, "1. دوس قفل اليوم"); assert.match(seen, /close_day/); assert.match(seen, /الدرج وقفل اليوم/);
});
await T("المالك لما التحليل مقفول (analytics=false): أدوات التشغيل بس والبرومبت من غير تحليل، والأداة مرفوضة", async () => {
  const n = toolsFor(true, "owner", false).map((t) => t.name);
  for (const x of OPS) assert.ok(n.includes(x), x);
  for (const x of ANALYTICS) assert.ok(!n.includes(x), x);
  const sb = mockSb();
  assert.match((await runTool({ ...own, sb, analytics: false }, "overview", {})).result.error, /غير متاحة/);
  assert.equal(sb.calls.length, 0);
  const p = systemPrompt({ ...own, analytics: false });
  assert.ok(!/overview/.test(p));
  assert.match(p, /how_to/);
  assert.ok(toolsFor(true, "owner").some((t) => t.name === "overview"));
  assert.match((await runTool({ ...own, sb, analytics: true }, "how_to", { question: "قفل اليوم" })).result.topics[0].id, /close_day/);
});
await T("analytics=false: حلقة الدردشة بتدي النموذج أدوات التشغيل بس", async () => {
  let seen = null;
  const llm = async (_s, _m, tools) => { seen = tools.map((t) => t.name); return { stop_reason: "end_turn", content: [{ type: "text", text: "تمام" }] }; };
  await chat({ ...own, sb: mockSb(), analytics: false }, [{ role: "user", content: "ازاي اقفل اليوم" }], llm);
  assert.ok(seen.includes("how_to") && !seen.includes("overview"));
});
