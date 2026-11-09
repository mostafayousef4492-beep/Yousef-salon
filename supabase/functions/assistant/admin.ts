// مساعد الإدارة — أدوات تحليل للقراءة فقط (مالك/مدير). كل أداة بتنادي دالة ai_* في القاعدة بصلاحية المستخدم،
// والقاعدة نفسها بترفض لو مش مالك/مدير. مفيش أداة هنا بتكتب أو تحذف أو تبعت حاجة.
// الخصوصية: الأدوات بتطلب البيانات بدون أسماء عملاء ولا تليفونات ولا ملاحظات حرة (p_names=false)؛
// واجهة المدير هي اللي بتفتح التفاصيل بالأسماء من القاعدة مباشرة عن طريق «drills».
import type { Ctx } from "./core.ts";
import { rangeFor, localDate } from "./core.ts";

const RANGE = { type: "string", enum: ["today", "yesterday", "week", "month", "last_month", "custom"], description: "الفترة. week = من السبت. custom تحتاج from/to" };
const RP = { range: RANGE, from: { type: "string", description: "YYYY-MM-DD (لـ custom)" }, to: { type: "string", description: "YYYY-MM-DD شامل (لـ custom)" } };

const fmt = (x: any) => (x === null || x === undefined ? null : Math.round(Number(x) * 100) / 100);
const pct = (cur: number, prev: number) => (prev ? Math.round(((cur - prev) / Math.abs(prev)) * 1000) / 10 : null);

type Rng = ReturnType<typeof rangeFor>;
function rng(ctx: Ctx, a: any, pre = ""): Rng {
  return rangeFor(a?.[pre + "range"] || "month", a?.[pre + "from"], a?.[pre + "to"], ctx.now, ctx.tz);
}
async function rpc(ctx: Ctx, fn: string, args: any) {
  const { data, error } = await ctx.sb.rpc(fn, args);
  if (error) throw new Error(error.message);
  return data;
}
const span = (r: Rng) => ({ period: `${r.fromDay} → ${r.toDay}`, from: r.fromISO, to: r.toISO });
const base = (r: Rng) => ({ p_from: r.fromISO, p_to: r.toISO });
const drillAll = (r: Rng, label = "كل فواتير الفترة") => ({ label, from: r.fromISO, to: r.toISO });

const SRC_INV = "فواتير المبيعات (جدول invoices) بتاريخ إنشاء الفاتورة بتوقيت الصالون";
const NO_DATA = "مفيش فواتير في الفترة دي — الأرقام صفر لأن مفيش بيانات مش لأن الأداء صفر بالضرورة. قول ده للمدير بوضوح.";

async function overview(ctx: Ctx, a: any) {
  const r = rng(ctx, a);
  const o = await rpc(ctx, "ai_overview", base(r));
  const gaps: string[] = [];
  if (!o.invoices) gaps.push(NO_DATA);
  return {
    ...span(r), source: "دالة ai_overview (نفس معادلات «التقرير الشامل») + " + SRC_INV,
    method: "الإيراد = مجموع totals الفواتير المدفوعة (المبلغ المدفوع فقط؛ المتبقي بيتحسب في unpaid). تكلفة البضاعة = تكلفة المنتجات المباعة. المصروفات من جدول expenses بتاريخ الصرف. تكلفة الموظفين = عمولات + مرتبات الفترة + مكافآت − خصومات. الربح = الإيراد − تكلفة البضاعة − المصروفات − تكلفة الموظفين. متوسط الفاتورة = الإيراد ÷ عدد الفواتير.",
    data: {
      revenue: fmt(o.revenue), invoices: o.invoices, avg_invoice: fmt(o.avg_invoice), cogs: fmt(o.cogs), expenses: fmt(o.expenses),
      staff_cost: fmt(o.staff_cost), commissions: fmt(o.commissions), salaries: fmt(o.salaries), bonuses: fmt(o.bonuses), deductions: fmt(o.deductions),
      profit: fmt(o.profit), unpaid_created_in_range: fmt(o.unpaid_created_in_range), outstanding_debt_total_now: fmt(o.outstanding_debt_total_now),
      by_payment_method: (o.by_pay || []).map((x: any) => ({ method: x.m, invoices: x.n, total: fmt(x.t) })),
    },
    data_gaps: gaps, drill: drillAll(r),
  };
}

async function compare(ctx: Ctx, a: any) {
  const A = rng(ctx, a, "a_"), B = rng(ctx, a, "b_");
  const [x, y, ex, ey] = await Promise.all([
    rpc(ctx, "ai_overview", base(A)), rpc(ctx, "ai_overview", base(B)),
    rpc(ctx, "ai_expenses", { ...base(A), p_names: false }), rpc(ctx, "ai_expenses", { ...base(B), p_names: false }),
  ]);
  const keys = ["revenue", "invoices", "avg_invoice", "expenses", "staff_cost", "profit"];
  const delta: any = {};
  for (const k of keys) {
    const cur = Number(x[k] ?? 0), prev = Number(y[k] ?? 0);
    delta[k] = { current: fmt(cur), previous: fmt(prev), diff: fmt(cur - prev), change_pct: pct(cur, prev) };
  }
  const cats = new Map<string, { c: number; p: number }>();
  for (const e of ex.by_category || []) cats.set(e.category, { c: Number(e.total), p: 0 });
  for (const e of ey.by_category || []) cats.set(e.category, { c: cats.get(e.category)?.c || 0, p: Number(e.total) });
  const expense_by_category = [...cats.entries()].map(([category, v]) => ({ category, current: fmt(v.c), previous: fmt(v.p), diff: fmt(v.c - v.p), change_pct: pct(v.c, v.p) })).sort((m, n) => Math.abs(n.diff!) - Math.abs(m.diff!));
  const gaps: string[] = [];
  if (!x.invoices) gaps.push("فترة «الحالية» فيها صفر فواتير.");
  if (!y.invoices) gaps.push("فترة «السابقة» فيها صفر فواتير — النسب المئوية ممكن تبقى null.");
  const lenA = (Date.parse(A.toDay) - Date.parse(A.fromDay)) / 864e5 + 1, lenB = (Date.parse(B.toDay) - Date.parse(B.fromDay)) / 864e5 + 1;
  if (lenA !== lenB) gaps.push(`الفترتين مختلفين في الطول (${lenA} يوم مقابل ${lenB} يوم) — نبّه المدير إن المقارنة مش متكافئة، وقارن بالمتوسط اليومي لو مفيد.`);
  return {
    current_period: `${A.fromDay} → ${A.toDay}`, previous_period: `${B.fromDay} → ${B.toDay}`,
    source: "دالة ai_overview + ai_expenses لكل فترة", method: "الفرق = الحالية − السابقة. النسبة = الفرق ÷ |السابقة| × 100 (محسوبة بالكود مش تقدير).",
    data: { delta, expense_by_category }, data_gaps: gaps, drill: drillAll(A, "فواتير الفترة الحالية"),
  };
}

async function topItems(ctx: Ctx, a: any) {
  const r = rng(ctx, a);
  const type = a?.type === "product" ? "product" : "service";
  const o = await rpc(ctx, "ai_items_rank", { ...base(r), p_type: type, p_limit: Math.min(Math.max(+a?.limit || 10, 1), 30) });
  const items = (o.items || []).map((x: any) => ({ name: x.name, qty: Number(x.qty), revenue_before_discount: fmt(x.revenue) }));
  return {
    ...span(r), source: "بنود الفواتير (invoice_items) المرتبطة بفواتير الفترة", method: "الترتيب بعدد المرات المباعة (qty) ثم الإيراد. الإيراد = السعر × الكمية قبل خصم الفاتورة، فمجموعه ممكن يزيد عن إيراد الفترة.",
    data: { type, total_qty: Number(o.total_qty), items }, data_gaps: items.length ? [] : ["مفيش بنود مباعة من النوع ده في الفترة."],
    drills: items.slice(0, 3).map((x: any) => ({ label: `فواتير «${x.name}»`, from: r.fromISO, to: r.toISO, service: x.name })),
  };
}

async function barbers(ctx: Ctx, a: any) {
  const r = rng(ctx, a);
  const o = await rpc(ctx, "ai_overview", base(r));
  const list = (o.staff || []).filter((s: any) => Number(s.sales) > 0).map((s: any) => ({
    id: s.id, name: s.name, role: s.role, sales: fmt(s.sales), cuts: s.cuts, avg_per_cut: s.cuts ? fmt(Number(s.sales) / Number(s.cuts)) : null, commission: fmt(s.commission),
  }));
  return {
    ...span(r), source: "ai_overview.staff (مبيعات كل موظف من الفواتير المنسوبة لحلاقه)", method: "المبيعات = مجموع الفواتير اللي حلاقها الموظف. متوسط القصة = المبيعات ÷ عدد الفواتير. العمولة بنسبة الموظف على صافي المبيعات (بعد نصيب المساعد).",
    data: { ranking: list }, data_gaps: list.length ? [] : ["مفيش مبيعات منسوبة لحلاقين في الفترة."],
    drills: list.slice(0, 3).map((s: any) => ({ label: `فواتير ${s.name}`, from: r.fromISO, to: r.toISO, barber_id: s.id })),
  };
}

async function daily(ctx: Ctx, a: any) {
  const r = rng(ctx, a);
  const o = await rpc(ctx, "ai_daily_series", base(r));
  const days = (o.days || []).map((d: any) => ({ day: d.day, revenue: fmt(d.revenue), invoices: d.invoices }));
  const sorted = [...days].sort((m, n) => n.revenue - m.revenue);
  const tot = days.reduce((s: number, d: any) => s + d.revenue, 0);
  return {
    ...span(r), source: SRC_INV, method: "الإيراد اليومي بتجميع الفواتير بتاريخها بتوقيت الصالون. الأيام اللي مفيهاش فواتير مش ظاهرة (مش صفر مؤكد).",
    data: { days_with_sales: days.length, total: fmt(tot), avg_per_active_day: days.length ? fmt(tot / days.length) : null, best_day: sorted[0] || null, weakest_day: sorted[sorted.length - 1] || null, days: days.slice(-62) },
    data_gaps: days.length ? [] : [NO_DATA], drill: drillAll(r),
  };
}

async function expenses(ctx: Ctx, a: any) {
  const r = rng(ctx, a);
  const o = await rpc(ctx, "ai_expenses", { ...base(r), p_names: false });
  return {
    ...span(r), source: "جدول المصروفات expenses بتاريخ الصرف (spent_on)", method: "الإجمالي = مجموع المصروفات المسجلة. بنود المصروفات (إيجار/كهرباء…) من حقل category. المشتريات المدفوعة بتتسجل هنا كمصروف مرتبط (purchase_id). ملاحظات المصروفات مخفية عن المساعد.",
    data: { total: fmt(o.total), by_category: (o.by_category || []).map((x: any) => ({ category: x.category, total: fmt(x.total), count: x.count })), largest: (o.largest || []).map((x: any) => ({ date: x.date, category: x.category, amount: fmt(x.amount), from_purchase: !!x.purchase_id })) },
    data_gaps: Number(o.total) ? [] : ["مفيش مصروفات مسجلة في الفترة."],
  };
}

async function purchases(ctx: Ctx, a: any) {
  const r = rng(ctx, a);
  const o = await rpc(ctx, "ai_purchases", base(r));
  return {
    ...span(r), source: "فواتير الشراء purchases بتاريخ الشراء (bought_on) + الموردين", method: "المتبقي = إجمالي الشراء − المدفوع (مستحق للموردين).",
    data: { count: o.count, total: fmt(o.total), paid: fmt(o.paid), unpaid: fmt(o.unpaid), by_kind: o.by_kind, by_supplier: (o.by_supplier || []).map((x: any) => ({ supplier: x.supplier, total: fmt(x.total), unpaid: fmt(x.unpaid) })) },
    data_gaps: o.count ? [] : ["مفيش فواتير شراء مسجلة في الفترة."],
  };
}

async function customers(ctx: Ctx, a: any) {
  const r = rng(ctx, a);
  const o = await rpc(ctx, "ai_customers", { ...base(r), p_names: false });
  return {
    ...span(r), source: "جدولا customers وinvoices", method: "نشطين = عملاء ليهم فاتورة في الفترة. راجعين = ليهم فاتورتين أو أكتر. فواتير مجهولة = فواتير من غير عميل مسجل. أعلى المنفقين معروضين برقم العميل بس (الأسماء مخفية عن المساعد، المدير يشوفها من زرار التفاصيل).",
    data: { customers_total: o.customers_total, new_in_range: o.new_in_range, active_in_range: o.active_in_range, repeat_in_range: o.repeat_in_range, anonymous_invoices: o.anonymous_invoices, top_spenders: (o.top_spenders || []).map((x: any) => ({ customer: "عميل #" + x.customer_id, spent: fmt(x.spent), invoices: x.invoices })) },
    data_gaps: [], drill: drillAll(r),
  };
}

async function appointments(ctx: Ctx, a: any) {
  const r = rng(ctx, a);
  const o = await rpc(ctx, "ai_appointments", base(r));
  return {
    ...span(r), source: "جدول الحجوزات appointments بيوم الحجز", method: "نسبة عدم الحضور = حجوزات no_show ÷ كل الحجوزات. الحجز بالفترة (صبح/عصر/مساء) مش بالساعة.",
    data: o, data_gaps: o.total ? [] : ["مفيش حجوزات في الفترة."],
  };
}

async function attendance(ctx: Ctx, a: any) {
  const r = rng(ctx, a);
  const o = await rpc(ctx, "ai_attendance", base(r));
  return {
    ...span(r), source: "جدول الحضور attendance", method: "ساعات = مجموع (انصراف − حضور) للسجلات المقفولة بس. التأخير بالدقايق من حقل late_min.",
    data: o, data_gaps: (o.staff || []).length ? [] : ["مفيش سجلات حضور في الفترة."],
  };
}

async function invoices(ctx: Ctx, a: any) {
  const r = rng(ctx, a);
  let barber: string | null = null;
  if (a?.barber_name) {
    const { data } = await ctx.sb.from("profiles").select("id,full_name,role").neq("role", "customer").ilike("full_name", `%${String(a.barber_name).slice(0, 40)}%`).limit(5);
    if (!data?.length) return { error: "مفيش موظف بالاسم ده" };
    if (data.length > 1) return { error: "أكتر من موظف بنفس الاسم: " + data.map((x: any) => x.full_name).join("، ") + " — حدد أدق." };
    barber = data[0].id;
  }
  const o = await rpc(ctx, "ai_invoices", { ...base(r), p_barber: barber, p_service: a?.service || null, p_method: a?.method || null, p_limit: Math.min(Math.max(+a?.limit || 15, 1), 30), p_names: false });
  return {
    ...span(r), source: SRC_INV, method: "الفواتير اللي بتكوّن الإجمالي. matching_total = مجموع الفواتير المطابقة كلها (مش بس المعروضة).",
    data: o, data_gaps: o.matching ? [] : ["مفيش فواتير مطابقة."],
  };
}

export const ADMIN_TOOLS = [
  { name: "overview", description: "نظرة عامة على أداء الصالون في فترة: الإيراد، عدد الفواتير، متوسط الفاتورة، المصروفات، تكلفة الموظفين، الربح، طرق الدفع، الديون. (نفس معادلات التقرير الشامل)", input_schema: { type: "object", properties: RP } },
  { name: "compare_periods", description: "مقارنة فترتين (الحالية a مقابل السابقة b) في الإيراد والفواتير والمصروفات والربح وبنود المصروفات. الفروق والنسب محسوبة بالكود. مثال: الشهر ده (a_range=month) مقابل اللي فات (b_range=last_month).", input_schema: { type: "object", properties: { a_range: RANGE, a_from: { type: "string" }, a_to: { type: "string" }, b_range: RANGE, b_from: { type: "string" }, b_to: { type: "string" } }, required: ["a_range", "b_range"] } },
  { name: "top_items", description: "أكتر الخدمات (أو المنتجات) طلبًا في فترة بالعدد والإيراد.", input_schema: { type: "object", properties: { ...RP, type: { type: "string", enum: ["service", "product"] }, limit: { type: "integer" } } } },
  { name: "barbers_ranking", description: "ترتيب الحلاقين بالمبيعات وعدد القصات ومتوسط القصة والعمولة في فترة.", input_schema: { type: "object", properties: RP } },
  { name: "daily_sales", description: "المبيعات يوم بيوم في فترة + أفضل يوم وأضعف يوم والمتوسط.", input_schema: { type: "object", properties: RP } },
  { name: "expenses_breakdown", description: "المصروفات بالبند وأكبر المصروفات في فترة.", input_schema: { type: "object", properties: RP } },
  { name: "purchases_summary", description: "المشتريات: الإجمالي والمدفوع والمتبقي للموردين، بالنوع وبالمورد.", input_schema: { type: "object", properties: RP } },
  { name: "customers_summary", description: "العملاء: جدد، نشطين، راجعين، فواتير بدون عميل، وأعلى المنفقين (برقم العميل بس).", input_schema: { type: "object", properties: RP } },
  { name: "appointments_summary", description: "الحجوزات: العدد بالحالة والمصدر والفترة ونسبة عدم الحضور.", input_schema: { type: "object", properties: RP } },
  { name: "attendance_summary", description: "حضور الموظفين: أيام وساعات ودقايق تأخير لكل موظف في فترة.", input_schema: { type: "object", properties: RP } },
  { name: "list_invoices", description: "عرض الفواتير اللي بتكوّن إجمالي معين، بفلتر اختياري (اسم الحلاق/الخدمة/طريقة الدفع). للاستكشاف من الإجمالي للتفاصيل.", input_schema: { type: "object", properties: { ...RP, barber_name: { type: "string" }, service: { type: "string", description: "اسم الخدمة بالظبط" }, method: { type: "string", description: "طريقة الدفع زي cash أو wallet" }, limit: { type: "integer" } } } },
];

export const ADMIN_HANDLERS: Record<string, (ctx: Ctx, a: any) => Promise<any>> = {
  overview, compare_periods: compare, top_items: topItems, barbers_ranking: barbers, daily_sales: daily,
  expenses_breakdown: expenses, purchases_summary: purchases, customers_summary: customers,
  appointments_summary: appointments, attendance_summary: attendance, list_invoices: invoices,
};

export function adminPrompt(ctx: Ctx): string {
  const today = localDate(ctx.now, ctx.tz);
  return `\nإنت بتخدم ${ctx.role === "owner" ? "مالك" : "مدير"} الصالون (${ctx.name || "—"}) كمحلل بيانات ومساعد إداري. اليوم ${today}.
مهمتك: تجاوب عن أداء الصالون (إيراد، خدمات، حلاقين، مصروفات، مشتريات، عملاء، حجوزات، حضور) وتقارن فترات.
قواعد التحليل:
- الأرقام من الأدوات بس. ماتحسبش ولا تخمّن ولا تجمع من دماغك؛ الأدوات بترجّع الفروق والنسب جاهزة. لو محتاج مجموع مش موجود نادي أداة تانية.
- في كل إجابة رقمية اذكر: الفترة (من → إلى)، المصدر، وطريقة الحساب باختصار (من حقول source/method في نتيجة الأداة).
- لو data_gaps فيها حاجة أو الأداة رجّعت صفر/فاضي: قول بوضوح إن البيانات مش كافية أو مفيش بيانات، ولا تستنتج حاجة منها.
- «الشهر ده» = range month، «الشهر اللي فات» = last_month، «النهارده» = today، «الأسبوع» = week. لو السؤال مش واضح فترته، افترض الشهر الحالي وقول ده.
- مقارنة الفترتين لو طولهم مختلف (شهر لسه ماخلصش مقابل شهر كامل) نبّه إنها مش متكافئة.
- أنت للقراءة والتحليل بس. ماتقدرش تعدّل أو تحذف أو تسجّل أو تبعت رسائل أو تقفل يوم. لو طلب ده اشرح له الخطوات في التطبيق (من غير ما تنفّذ) وقول إنك مش بتنفّذ.
- خصوصية: أسماء العملاء وتليفوناتهم مش متاحة ليك. أعلى العملاء بيظهروا برقم. قول للمدير يدوس على زرار «عرض الفواتير» تحت الرد لو عايز الأسماء والتفاصيل.
- ردودك مختصرة ومنظمة: الخلاصة في أول سطر، وبعدها نقاط قصيرة. اقترح خطوة تحليل تالية لو مفيدة.`;
}
