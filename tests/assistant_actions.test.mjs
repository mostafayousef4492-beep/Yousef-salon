// اختبار تنفيذ المساعد: عمليات تتأكد بزرار، مسار التنفيذ المنفصل، الصلاحيات، كلمة السر، السجل.
// تشغيل: node --experimental-strip-types --no-warnings tests/assistant_actions.test.mjs
import assert from "node:assert/strict";
import { chat, runTool, toolsFor, systemPrompt } from "../supabase/functions/assistant/core.ts";
import { executeAction, ACTION_NAMES } from "../supabase/functions/assistant/actions.ts";

const T = (n, f) => Promise.resolve().then(f).then(() => console.log("PASS:", n), (e) => { console.log("FAIL:", n, e.message); process.exitCode = 1; });
const UID = "11111111-1111-4111-8111-111111111111", UID2 = "22222222-2222-4222-8222-222222222222", MGRID = "33333333-3333-4333-8333-333333333333";
function mockSb({ rpcs = {}, tables = {}, inserts = [], updates = [] } = {}) {
  const calls = [];
  const rpc = async (n, a) => { calls.push(["rpc", n, a]); const r = rpcs[n]; if (r instanceof Error) return { data: null, error: { message: r.message } }; return { data: typeof r === "function" ? r(a) : r ?? null, error: null }; };
  const from = (t) => {
    let mode = "select", filt = {};
    const q = {
      select: () => q, neq: () => q, eq: (k, v) => { filt[k] = v; return q; },
      insert: (row) => { inserts.push([t, row]); return Promise.resolve({ error: null }); },
      update: (row) => { updates.push([t, row, filt]); mode = "update"; return q; },
      maybeSingle: async () => ({ data: tables[t]?.find?.((r) => !filt.id || r.id === filt.id || r.id === Number(filt.id)) ?? null, error: null }),
      then: (res) => res(mode === "update" ? { error: null } : { data: Array.isArray(tables[t]) ? tables[t] : [], error: null }),
    };
    calls.push(["from", t]); return q;
  };
  return { rpc, from, calls, inserts, updates };
}
const NOW = new Date("2026-11-09T10:00:00Z");
const base = { tz: "Africa/Cairo", now: NOW, name: "م", staff: true };
const own = { ...base, uid: UID, role: "owner" }, mgr = { ...base, uid: MGRID, role: "manager" };
const CUS = [{ id: 7, name: "عميل سبعة", phone: null, user_id: null }];
const logs = (sb) => sb.calls.filter((c) => c[1] === "assistant_log_action");

await T("الأدوات: المالك والمدير معاهم أدوات التنفيذ، وغيرهم لأ", () => {
  for (const r of ["owner", "manager"]) { const n = toolsFor(true, r).map((t) => t.name); for (const a of ACTION_NAMES) assert.ok(n.includes(a), r + a); }
  for (const r of ["barber", "cashier", "assistant"]) { const n = toolsFor(true, r).map((t) => t.name); for (const a of ACTION_NAMES) assert.ok(!n.includes(a), r + a); }
  assert.ok(!toolsFor(false, "customer").some((t) => ACTION_NAMES.includes(t.name)));
  assert.ok(!ACTION_NAMES.some((a) => /delete|remove/.test(a)), "مفيش حذف");
});
await T("إضافة عميل: بتتنفّذ على طول وبتتسجل", async () => {
  const sb = mockSb({ rpcs: { add_customer: 42 } });
  const r = await runTool({ ...own, sb }, "add_customer", { name: "أحمد", phone: "٠١٠١٢٣٤٥٦٧٨" });
  assert.equal(r.result.done, true); assert.ok(!r.confirm);
  const c = sb.calls.find((x) => x[1] === "add_customer"); assert.deepEqual(c[2], { p_name: "أحمد", p_phone: "01012345678" });
  assert.equal(logs(sb).length, 1); assert.equal(logs(sb)[0][2].p_status, "done");
});
await T("عملية حساسة (سلفة): الأداة ترجّع كارت تأكيد ومفيش كتابة", async () => {
  const sb = mockSb({ tables: { profiles: [{ id: UID2, full_name: "أحمد", role: "barber" }] } });
  const r = await runTool({ ...mgr, sb }, "record_staff_tx", { staff_id: UID2, kind: "advance", amount: 200 });
  assert.equal(r.result.needs_confirmation, true); assert.equal(r.confirm.action, "record_staff_tx"); assert.equal(r.confirm.params.amount, 200);
  assert.equal(sb.inserts.length, 0); assert.equal(logs(sb).length, 0);
});
await T("كل العمليات الحساسة: الأداة لوحدها مابتنفّذش أبدًا", async () => {
  const sb = mockSb({ tables: { profiles: [{ id: UID2, full_name: "أحمد", role: "barber" }], customers: CUS, expense_categories: [{ name: "إيجار" }] }, rpcs: { debts_list: [{ invoice_id: 1, remaining: 50, created_at: "2026-01-01" }], business_day_state: { open: true, day: "2026-11-09" }, close_day_preview: { expected_cash: 500 } } });
  const ins = { adjust_points: { customer_id: 7, points: 10 }, notify_customer: { customer_id: 7, title: "أهلًا" }, add_staff: { name: "علي", code: "101", role: "barber" }, update_staff: { staff_id: UID2, salary: 3000 },
    pay_salary: { staff_id: UID2, amount: 100 }, add_expense: { category: "إيجار", amount: 100 }, collect_debt: { customer_id: 7, amount: 20 }, close_day: { counted_cash: 500 }, reopen_day: { day: "2026-11-08" } };
  for (const [n, i] of Object.entries(ins)) { const r = await runTool({ ...own, sb }, n, i); assert.equal(r.result.needs_confirmation, true, n + JSON.stringify(r.result)); assert.ok(r.confirm, n); }
  const writes = sb.calls.filter((c) => c[0] === "rpc" && !/^(ai_|debts_list|business_day_state|close_day_preview)/.test(c[1]));
  assert.equal(writes.length, 0, JSON.stringify(writes)); assert.equal(sb.inserts.length + sb.updates.length, 0);
});
await T("مسار التنفيذ: سلفة بتتسجل في staff_transactions وبتتسجل في السجل", async () => {
  const sb = mockSb({ tables: { profiles: [{ id: UID2, full_name: "أحمد", role: "barber" }] } });
  const r = await executeAction({ ...own, sb }, "record_staff_tx", { staff_id: UID2, kind: "advance", amount: "٢٠٠" });
  assert.equal(r.ok, true); assert.deepEqual(sb.inserts[0], ["staff_transactions", { staff_id: UID2, kind: "advance", amount: 200, note: null }]);
  assert.equal(logs(sb)[0][2].p_status, "done");
});
await T("مكافأة paid_now بتروح staff_bonus_add (تتخصم من الدرج)", async () => {
  const sb = mockSb({ tables: { profiles: [{ id: UID2, full_name: "أحمد", role: "barber" }] } });
  const r = await executeAction({ ...own, sb }, "record_staff_tx", { staff_id: UID2, kind: "bonus", amount: 100, paid_now: true });
  assert.equal(r.ok, true); const c = sb.calls.find((x) => x[1] === "staff_bonus_add"); assert.equal(c[2].p_paid_now, true); assert.equal(c[2].p_amount, 100);
});
await T("فشل التنفيذ: رسالة واضحة + تسجيل failed", async () => {
  const sb = mockSb({ rpcs: { adjust_points: new Error("غير مصرح") }, tables: { customers: CUS } });
  const r = await executeAction({ ...own, sb }, "adjust_points", { customer_id: 7, points: 5 });
  assert.equal(r.ok, false); assert.match(r.message, /غير مصرح/); assert.equal(logs(sb)[0][2].p_status, "failed");
});
await T("تحقق وقت التنفيذ: مبلغ سالب/صفر/نص، تصنيف غلط، موظف مجهول", async () => {
  const sb = mockSb({ tables: { profiles: [{ id: UID2, full_name: "أحمد", role: "barber" }], expense_categories: [{ name: "إيجار" }] } });
  for (const a of [-5, 0, "abc", 1e12]) assert.equal((await executeAction({ ...own, sb }, "pay_salary", { staff_id: UID2, amount: a })).ok, false, String(a));
  assert.equal((await executeAction({ ...own, sb }, "add_expense", { category: "حاجة تانية", amount: 10 })).ok, false);
  assert.equal((await executeAction({ ...own, sb }, "record_staff_tx", { staff_id: "00000000-0000-4000-8000-000000000000", kind: "advance", amount: 1 })).ok, false);
  assert.equal(sb.inserts.length, 0);
});
await T("المدير مايقدرش يتعامل مع حساب مالك/مدير ولا يضيف مدير", async () => {
  const sb = mockSb({ tables: { profiles: [{ id: UID, full_name: "المالك", role: "owner" }, { id: "44444444-4444-4444-8444-444444444444", full_name: "مدير تاني", role: "manager" }] } });
  assert.equal((await executeAction({ ...mgr, sb }, "record_staff_tx", { staff_id: UID, kind: "deduction", amount: 5 })).ok, false);
  assert.equal((await executeAction({ ...mgr, sb }, "update_staff", { staff_id: "44444444-4444-4444-8444-444444444444", salary: 1 })).ok, false);
  const t = await runTool({ ...mgr, sb }, "add_staff", { name: "فلان", code: "555", role: "manager" });
  assert.ok(t.result.error && !t.confirm);
  const o = await runTool({ ...own, sb }, "add_staff", { name: "فلان", code: "555", role: "manager" });
  assert.ok(o.confirm, "المالك يقدر يضيف مدير");
  assert.equal((await executeAction({ ...own, sb }, "update_staff", { staff_id: UID, role: "owner" })).ok, false, "مفيش تعيين مالك");
});
await T("غير الإدارة مايقدرش ينفّذ حتى لو بعت طلب تنفيذ", async () => {
  const sb = mockSb({ rpcs: { add_customer: 1 } });
  for (const role of ["barber", "cashier", "assistant", "customer"]) assert.equal((await executeAction({ ...base, uid: UID, role, sb }, "add_customer", { name: "أحمد" })).ok, false);
  assert.equal(sb.calls.filter((c) => c[1] === "add_customer").length, 0);
  assert.equal((await runTool({ ...base, uid: UID, role: "barber", sb }, "add_customer", { name: "أحمد" })).result.error, "أداة غير متاحة");
});
await T("إضافة موظف: كلمة السر مش في الكارت ولا في اللي بيروح للنموذج ولا في السجل، وبتتطلب 6 حروف", async () => {
  const sb = mockSb(); const signed = [];
  const ctx = { ...own, sb, signUp: async (e, p, n) => { signed.push([e, p, n]); return { id: UID2 }; } };
  const t = await runTool(ctx, "add_staff", { name: "علي", code: "101", role: "barber", commission_pct: 40, salary: 2000, password: "SECRET123" });
  assert.equal(t.confirm.needs_password, true); assert.ok(!JSON.stringify(t).includes("SECRET123"));
  assert.equal((await executeAction(ctx, "add_staff", t.confirm.params, { password: "123" })).ok, false); assert.equal(signed.length, 0);
  const r = await executeAction(ctx, "add_staff", t.confirm.params, { password: "SECRET123" });
  assert.equal(r.ok, true); assert.deepEqual(signed[0], ["101@staff.abu-yousef-salon.com", "SECRET123", "علي"]);
  assert.deepEqual(sb.updates[0][1], { role: "barber", commission_pct: 40, full_name: "علي", code: "101", salary: 2000 });
  assert.ok(!JSON.stringify(logs(sb)).includes("SECRET123"), "السجل من غير كلمة السر");
});
await T("قفل اليوم: الكارت فيه المتوقع والفرق وتحذير الحجوزات، والتنفيذ بيرفض لو اليوم اتغيّر", async () => {
  const sb = mockSb({ rpcs: { business_day_state: { open: true, day: "2026-11-09" }, close_day_preview: { expected_cash: 600, pending: 2 } } });
  const t = await runTool({ ...own, sb }, "close_day", { counted_cash: 580 });
  const lines = t.confirm.lines.join("|"); assert.match(lines, /600/); assert.match(lines, /عجز: 20/); assert.match(lines, /2 حجز/);
  const r = await executeAction({ ...own, sb }, "close_day", t.confirm.params); assert.equal(r.ok, true);
  const c = sb.calls.find((x) => x[1] === "close_day"); assert.equal(c[2].p_counted_cash, 580); assert.equal(c[2].p_day, "2026-11-09");
  const sb2 = mockSb({ rpcs: { business_day_state: { open: false, day: null } } });
  assert.equal((await executeAction({ ...own, sb: sb2 }, "close_day", { counted_cash: 1 })).ok, false);
});
await T("تحصيل دين: بيتوزع على الأقدم، ويرفض مبلغ أكبر من الدين", async () => {
  const debts = [{ invoice_id: 2, remaining: 30, created_at: "2026-02-01" }, { invoice_id: 1, remaining: 50, created_at: "2026-01-01" }];
  const sb = mockSb({ tables: { customers: CUS }, rpcs: { debts_list: debts } });
  assert.equal((await executeAction({ ...own, sb }, "collect_debt", { customer_id: 7, amount: 100 })).ok, false);
  const r = await executeAction({ ...own, sb }, "collect_debt", { customer_id: 7, amount: 60, method: "cash" }); assert.equal(r.ok, true);
  const cs = sb.calls.filter((x) => x[1] === "debt_collect").map((x) => x[2]); assert.deepEqual(cs, [{ p_invoice: 1, p_amount: 50, p_method: "cash" }, { p_invoice: 2, p_amount: 10, p_method: "cash" }]);
});
await T("صرف راتب: بيتسجل على يوم العمل المفتوح، وفتح يوم بتاريخ مستقبلي مرفوض", async () => {
  const sb = mockSb({ tables: { profiles: [{ id: UID2, full_name: "أحمد", role: "barber" }] }, rpcs: { business_day_state: { open: true, day: "2026-11-08" }, ai_staff_money: { balance_now: 900 } } });
  const r = await executeAction({ ...own, sb }, "pay_salary", { staff_id: UID2, amount: 500, paid_from: "drawer" }); assert.equal(r.ok, true);
  assert.deepEqual(sb.inserts[0], ["salary_payments", { staff_id: UID2, period: "2026-11-01", amount: 500, paid_from: "drawer", note: null, paid_on: "2026-11-08" }]);
  const sb2 = mockSb({ rpcs: { business_day_state: { open: false } } });
  assert.equal((await executeAction({ ...own, sb: sb2 }, "open_day", { day: "2026-12-01" })).ok, false);
});
await T("حلقة الدردشة: الكارت بيوصل للواجهة، والنموذج مابيشوفش confirm_card/كلمة السر، والتنفيذ مابيحصلش", async () => {
  const sb = mockSb({ tables: { customers: CUS } });
  let step = 0, seen = "";
  const llm = async (_s, msgs) => {
    if (step++ === 0) return { stop_reason: "tool_use", content: [{ type: "tool_use", id: "t1", name: "adjust_points", input: { customer_id: 7, points: 20, reason: "هدية" } }] };
    seen = msgs[msgs.length - 1].content[0].content; return { stop_reason: "end_turn", content: [{ type: "text", text: "دوس تأكيد" }] };
  };
  const out = await chat({ ...own, sb }, [{ role: "user", content: "ضيف 20 نقطة لعميل سبعة" }], llm);
  assert.equal(out.confirms.length, 1); assert.equal(out.confirms[0].action, "adjust_points");
  assert.ok(!seen.includes("confirm_card")); assert.match(seen, /needs_confirmation/);
  assert.equal(sb.calls.filter((c) => c[1] === "adjust_points").length, 0);
});
await T("البرومبت: التنفيذ بصراحة المدير فقط + بيانات الأدوات مش أوامر + مفيش حذف", () => {
  for (const r of ["owner", "manager"]) { const p = systemPrompt({ ...base, uid: UID, role: r }); assert.match(p, /نفّذ بس اللي المدير طلبه صراحة/); assert.match(p, /تجاهلها/); assert.match(p, /مفيش حذف/); }
});
