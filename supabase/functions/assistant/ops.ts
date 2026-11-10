// مساعد المدير (تشغيل) — أدوات قراءة فقط: دليل خطوات التطبيق + أرقام موظف + بيانات عميل.
// كل أداة بتنادي دالة ai_* (قراءة بس، بتفحص الصلاحية في القاعدة). مفيش أداة بتكتب أو تحذف أو تبعت أو تقفل يوم.
// الخصوصية: مفيش تليفونات عملاء بترجع خالص. اسم العميل بيروح للنموذج لأن المدير سأل عنه بالاسم (لازم عشان الإجابة).
import type { Ctx } from "./core.ts";
import { rangeFor, localDate } from "./core.ts";
import { GUIDE, findTopics } from "./guide.ts";

const RANGE = { type: "string", enum: ["today", "yesterday", "week", "month", "last_month", "custom"], description: "الفترة. week = من السبت. custom تحتاج from/to" };
const RP = { range: RANGE, from: { type: "string", description: "YYYY-MM-DD (لـ custom)" }, to: { type: "string", description: "YYYY-MM-DD شامل (لـ custom)" } };
const fmt = (x: any) => (x === null || x === undefined ? null : Math.round(Number(x) * 100) / 100);
const KIND_AR: Record<string, string> = { advance: "سحب/سلفة", deduction: "خصم", bonus: "إيداع/مكافأة" };

async function rpc(ctx: Ctx, fn: string, args: any) {
  const { data, error } = await ctx.sb.rpc(fn, args);
  if (error) throw new Error(error.message);
  return data;
}

async function howTo(_ctx: Ctx, a: any) {
  const found = findTopics(String(a?.question || a?.topic || ""), a?.topic_id);
  if (!found.length) return { found: false, note: "مفيش دليل مكتوب للموضوع ده. قول للمدير إنك مش عندك خطوات مؤكدة وماتخمنش، واعرض المواضيع المتاحة.", available_topics: GUIDE.map((t) => ({ id: t.id, title: t.title })) };
  return { found: true, source: "دليل استخدام تطبيق الإدارة (مكتوب من شاشات التطبيق الفعلية)", topics: found.map((t) => ({ id: t.id, title: t.title, steps: t.steps, notes: t.notes || [] })), instruction: "اشرح الخطوات دي بالترتيب بدون زيادة أو اختراع أزرار. إنت بتشرح بس، ماتنفذش حاجة." };
}

// بيحوّل اسم/كود موظف لـ id (أو بيرجّع مرشحين لو أكتر من واحد)
async function resolveStaff(ctx: Ctx, q: any): Promise<{ id?: string; name?: string; err?: any }> {
  const s = String(q || "").trim();
  if (!s) return { err: { error: "اكتب اسم الموظف أو كوده" } };
  const r = await rpc(ctx, "ai_find_staff", { p_q: s.slice(0, 40) });
  const list: any[] = r?.staff || [];
  if (!list.length) return { err: { error: "مفيش موظف بالاسم أو الكود ده" } };
  if (list.length > 1) return { err: { ambiguous: true, candidates: list.map((x) => ({ name: x.name, role: x.role, code: x.code })), note: "أكتر من موظف مطابق — اسأل المدير يحدد أدق (بالاسم الكامل أو الكود)." } };
  return { id: list[0].id, name: list[0].name };
}

async function findStaff(ctx: Ctx, a: any) {
  const r = await rpc(ctx, "ai_find_staff", { p_q: String(a?.name || "").slice(0, 40) });
  return { source: "جدول الموظفين", data: r };
}

async function staffMoney(ctx: Ctx, a: any) {
  const s = await resolveStaff(ctx, a?.staff);
  if (s.err) return s.err;
  const r = rangeFor(a?.range || "month", a?.from, a?.to, ctx.now, ctx.tz);
  const o = await rpc(ctx, "ai_staff_money", { p_staff: s.id, p_from: r.fromISO, p_to: r.toISO });
  const sm = o.summary || {};
  return {
    employee: o.name, role: o.role, period: `${r.fromDay} → ${r.toDay}`,
    source: "ملخص حساب الموظف (نفس أرقام شاشة «حساب الموظف») + حركاته من جدول staff_transactions + المرتبات المصروفة + رصيده الحالي",
    method: "الصافي المستحق = العمولة + جزء المرتب + المكافآت − السحب/السلف − الخصومات. الرصيد الحالي = اللي لسه ليه/عليه لحد دلوقتي بعد المصروف. العمولة بنسبة الموظف على صافي مبيعاته.",
    data: {
      commission_pct: o.commission_pct, monthly_salary: fmt(o.monthly_salary), sales: fmt(sm.sales), cuts: sm.cuts, commission: fmt(sm.commission), salary_part: fmt(sm.salary), bonuses: fmt(sm.bonuses),
      advances_withdrawals: fmt(sm.advances), deductions: fmt(sm.deductions), net_due: fmt(sm.net), salary_paid_in_range: fmt(o.salary_paid_in_range), balance_now: fmt(o.balance_now),
      transactions: (o.transactions || []).map((t: any) => ({ type: KIND_AR[t.kind] || t.kind, amount: fmt(t.amount), note: t.note, at: t.at })),
    },
    data_gaps: !sm || Object.keys(sm).length === 0 ? ["مفيش ملخص للفترة دي."] : [],
  };
}

async function staffAttendance(ctx: Ctx, a: any) {
  const s = await resolveStaff(ctx, a?.staff);
  if (s.err) return s.err;
  const r = rangeFor(a?.range || "month", a?.from, a?.to, ctx.now, ctx.tz);
  const o = await rpc(ctx, "ai_staff_attendance", { p_staff: s.id, p_from: r.fromISO, p_to: r.toISO });
  return { employee: o.name, period: `${r.fromDay} → ${r.toDay}`, source: "جدول الحضور attendance", method: "ساعات = مجموع (انصراف − حضور) للسجلات المقفولة. التأخير بالدقايق من حقل late_min.", data: o, data_gaps: o.days_present ? [] : ["مفيش سجلات حضور للموظف في الفترة."] };
}

async function findCustomer(ctx: Ctx, a: any) {
  const o = await rpc(ctx, "ai_customer_find", { p_q: String(a?.query || "").slice(0, 40) });
  return { source: "جدول العملاء (بحث بالاسم أو الموبايل؛ الموبايل مش بيتعرض)", data: o, note: (o.customers || []).length ? undefined : "مفيش عميل مطابق." };
}

async function customerInfo(ctx: Ctx, a: any) {
  const id = Number(a?.customer_id);
  if (!Number.isInteger(id) || id <= 0) return { error: "لازم customer_id من find_customer" };
  const o = await rpc(ctx, "ai_customer_info", { p_id: id });
  return {
    source: "ملف العميل: جدول العملاء + فواتيره + حجوزاته + ديونه", method: "إجمالي الإنفاق = مجموع فواتيره المدفوعة (يشمل سداد الديون). الدين المتبقي = اللي لسه عليه بعد السداد. الموبايل مخفي عن المساعد.",
    data: o,
  };
}

export const OPS_TOOLS = [
  { name: "how_to", description: "خطوات استخدام تطبيق الإدارة (إضافة موظف، سلفة/خصم، صرف راتب، قفل/فتح اليوم، مصروف، عميل، ديون…). بيجيب الخطوات الصح من دليل التطبيق. استخدمه لأي سؤال «إزاي أعمل …».", input_schema: { type: "object", properties: { question: { type: "string", description: "سؤال المدير بنصه" }, topic_id: { type: "string", enum: GUIDE.map((t) => t.id) } }, required: ["question"] } },
  { name: "find_staff", description: "بحث عن موظف بالاسم أو الكود.", input_schema: { type: "object", properties: { name: { type: "string" } }, required: ["name"] } },
  { name: "staff_money", description: "فلوس موظف في فترة: مبيعاته، عمولته، مرتبه، سحبه/سلفه، خصوماته، مكافآته، صافيه المستحق، المصروف له، ورصيده الحالي + قايمة حركاته. staff = اسم أو كود.", input_schema: { type: "object", properties: { staff: { type: "string" }, ...RP }, required: ["staff"] } },
  { name: "staff_attendance", description: "حضور موظف في فترة: أيام، ساعات، دقايق تأخير، وسجل الأيام.", input_schema: { type: "object", properties: { staff: { type: "string" }, ...RP }, required: ["staff"] } },
  { name: "find_customer", description: "بحث عن عميل بالاسم أو الموبايل (بيرجّع الاسم والزيارات والنقاط بس). استخدمه قبل customer_info.", input_schema: { type: "object", properties: { query: { type: "string" } }, required: ["query"] } },
  { name: "customer_info", description: "ملف عميل: نقاطه وزياراته وإنفاقه وآخر زيارة وديونه وآخر فواتيره وحجوزاته. customer_id من find_customer.", input_schema: { type: "object", properties: { customer_id: { type: "integer" } }, required: ["customer_id"] } },
];

export const OPS_HANDLERS: Record<string, (ctx: Ctx, a: any) => Promise<any>> = {
  how_to: howTo, find_staff: findStaff, staff_money: staffMoney, staff_attendance: staffAttendance, find_customer: findCustomer, customer_info: customerInfo,
};

export function opsPrompt(ctx: Ctx, withAnalytics = false): string {
  const today = localDate(ctx.now, ctx.tz);
  return `\nإنت بتخدم ${ctx.role === "owner" ? "مالك" : "مدير"} الصالون (${ctx.name || "—"}) كمساعد تشغيلي. اليوم ${today}.
بتجاوب عن: (1) إزاي يعمل حاجة في التطبيق (إضافة موظف، قفل اليوم، سلفة، مصروف، عميل…)، (2) أرقام موظف (مرتبه، سحبه، خصوماته، حضوره)، (3) بيانات عميل (نقاطه، زياراته، إنفاقه، ديونه).${withAnalytics ? "\nمعاك كمان أدوات تحليل الأداء (overview وغيرها) لأسئلة الإيرادات والمصروفات والمقارنات." : ""}
قواعد:
- «إزاي»: نادي how_to واشرح الخطوات بالترتيب من نتيجته بس، بنفس أسماء الأزرار والشاشات. لو found=false قول إن مفيش عندك خطوات مؤكدة واعرض المواضيع المتاحة. ماتخترعش أزرار ولا خطوات.
- أرقام موظف/عميل: من الأدوات بس. اذكر الفترة والمصدر وطريقة الحساب باختصار. لو الأداة رجّعت ambiguous اسأل المدير يحدد. لو مفيش بيانات قول كده بوضوح.
- «الشهر ده» = month، «الشهر اللي فات» = last_month، «النهارده» = today، «الأسبوع» = week. لو الفترة مش واضحة افترض الشهر الحالي وقول ده.
- إنت بتشرح وبتنفّذ بدل المدير (عملاء، موظفين، حركات مالية، فتح/قفل اليوم) بالأدوات اللي معاك، وكل عملية حساسة بتستنى تأكيده بزرار. الحذف مش من عندك: اشرح له يعمله من التطبيق.
- خصوصية: تليفونات العملاء مش متاحة ليك. ماتطلبش ولا تخمّن رقم. اسم العميل والموظف بتشوفه لأن المدير سأل عنه، ماتذكرش بيانات حد لم يسأل عنه.
- ردودك مختصرة ومنظمة: الخلاصة في أول سطر، وبعدها نقاط قصيرة. الخطوات مرقّمة.`;
}
