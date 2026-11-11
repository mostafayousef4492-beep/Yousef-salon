// فهم الكلام المصري: مبالغ بالحروف («ميتين»، «ألف ونص»)، أرقام عربية، وتواريخ («امبارح»، «بكره»، «من 3 أيام»).
// بيتستخدم في التحقق من مدخلات التنفيذ علشان «سلفة ميتين» أو «امبارح» ماتتخمنش غلط.
const DIGITS = (s: string) => s.replace(/[٠-٩]/g, (d) => String("٠١٢٣٤٥٦٧٨٩".indexOf(d))).replace(/[۰-۹]/g, (d) => String("۰۱۲۳۴۵۶۷۸۹".indexOf(d)));
const norm = (s: string) => DIGITS(String(s ?? "")).replace(/(\d),(?=\d{3}\b)/g, "$1").toLowerCase().replace(/[ً-ٟـ]/g, "").replace(/[أإآ]/g, "ا").replace(/ى/g, "ي").replace(/ة/g, "ه").replace(/[،,]/g, " ").replace(/\s+/g, " ").trim();

const UNITS: Record<string, number> = {
  تلات: 3, اربع: 4, خمس: 5, ست: 6, سبع: 7, تمن: 8, تسع: 9, واحد: 1, واحده: 1, اتنين: 2, اثنين: 2, تلاته: 3, ثلاثه: 3, اربعه: 4, خمسه: 5, سته: 6, سبعه: 7, تمانيه: 8, ثمانيه: 8, تسعه: 9, عشره: 10,
  احداشر: 11, اتناشر: 12, تلتاشر: 13, اربعتاشر: 14, خمستاشر: 15, ستاشر: 16, سبعتاشر: 17, تمنتاشر: 18, تسعتاشر: 19,
};
const TENS: Record<string, number> = { عشرين: 20, تلاتين: 30, ثلاثين: 30, اربعين: 40, خمسين: 50, ستين: 60, سبعين: 70, تمانين: 80, ثمانين: 80, تسعين: 90 };
const HUND: Record<string, number> = { ميه: 100, مايه: 100, مئه: 100, ميتين: 200, مئتين: 200, تلتميه: 300, تلاتميه: 300, ثلاثميه: 300, ربعميه: 400, اربعميه: 400, خمسميه: 500, خمسمايه: 500, ستميه: 600, سبعميه: 700, تمنميه: 800, تمانميه: 800, تسعميه: 900 };
const THOU: Record<string, number> = { الف: 1000, الفين: 2000, الاف: 1000, تلاف: 1000 };

// بيرجّع رقم موجب أو null. بيقبل: "200" "٢٠٠" "1,500" "200 جنيه" "ميتين" "خمسميه وخمسين" "الف ونص" "ألفين وخمسميه"
export function parseAmountAr(x: any): number | null {
  if (typeof x === "number") return Number.isFinite(x) && x > 0 ? x : null;
  const s = norm(String(x ?? "")).replace(/جنيه|جنية|ج\.م|ج م|egp|l\.e/g, " ").replace(/\s+/g, " ").trim();
  if (!s) return null;
  const plain = s;
  if (/^\d+(\.\d+)?$/.test(plain)) { const n = Number(plain); return n > 0 ? n : null; }
  const m = plain.match(/^(\d+(?:\.\d+)?)\s*(الف|الاف|k)$/);
  if (m) return Number(m[1]) * 1000;
  const words = s.split(" ").map((w) => w.replace(/^و(?=[ا-ي]{2,})/, "")).filter((w) => w && w !== "و");
  let total = 0, cur = 0, seen = false, half = false;
  for (const w of words) {
    if (UNITS[w] !== undefined) { cur += UNITS[w]; seen = true; }
    else if (TENS[w] !== undefined) { cur += TENS[w]; seen = true; }
    else if (HUND[w] !== undefined) { cur += HUND[w]; seen = true; }
    else if (THOU[w] !== undefined) { total += (THOU[w] === 2000 ? 2000 : (cur > 0 && cur < 1000 ? cur : 1) * 1000); cur = 0; seen = true; }
    else if (w === "نص" || w === "نصف") { half = true; seen = true; }
    else if (/^\d+$/.test(w)) { cur += Number(w); seen = true; }
    else if (w === "ربع") { return null; }
    else return null;
  }
  let n = total + cur;
  if (half) n += total >= 1000 && cur === 0 ? 500 : cur >= 100 ? 50 : 0.5;
  return seen && n > 0 ? n : null;
}

function addDays(d: string, n: number): string { const [y, m, da] = d.split("-").map(Number); return new Date(Date.UTC(y, m - 1, da + n)).toISOString().slice(0, 10); }
const DOW: Record<string, number> = { الاحد: 0, الحد: 0, الاتنين: 1, الاثنين: 1, التلات: 2, الثلاثاء: 2, الاربع: 3, الاربعاء: 3, الخميس: 4, الجمعه: 5, السبت: 6 };
function dowOf(d: string) { const [y, m, da] = d.split("-").map(Number); return new Date(Date.UTC(y, m - 1, da)).getUTCDay(); }

// بيحوّل تعبير تاريخ مصري لـ YYYY-MM-DD بالنسبة لـ today (تاريخ الصالون). بيرجّع null لو مش فاهم.
export function parseDateAr(x: any, today: string): string | null {
  const s = norm(String(x ?? ""));
  if (!s) return null;
  if (/^\d{4}-\d{2}-\d{2}$/.test(s) && !isNaN(Date.parse(s))) return s;
  if (/^(النهارده|النهاردة|انهارده|اليوم|دلوقتي)$/.test(s)) return today;
  if (/^(اول امبارح|اول مبارح|اول امس|قبل امبارح)$/.test(s)) return addDays(today, -2);
  if (/^(امبارح|مبارح|امس|الامس)$/.test(s)) return addDays(today, -1);
  if (/^(بكره|بكرا|غدا|بكرة)$/.test(s)) return addDays(today, 1);
  let m = s.match(/^(?:من |بعد |قبل )?(\d+) (?:ايام|يوم)(?: فاتت| فات| ماضيه| مضت)?$/);
  if (m) return addDays(today, -Number(m[1]));
  m = s.match(/^(?:يوم )?([ا-ي]+?)(?: اللي فات| الماضي| اللي فاتت)?$/);
  if (m && DOW[m[1]] !== undefined) { let d = addDays(today, -1); for (let i = 0; i < 7 && dowOf(d) !== DOW[m[1]]; i++) d = addDays(d, -1); return d; }
  m = s.match(/^(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{2,4}))?$/);
  if (m) { const y = m[3] ? (m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3])) : Number(today.slice(0, 4)); const d = `${y}-${String(+m[2]).padStart(2, "0")}-${String(+m[1]).padStart(2, "0")}`; if (!isNaN(Date.parse(d))) return d; }
  return null;
}

// قاموس مختصر بيتضاف على برومبت الإدارة علشان النموذج يفهم الكلام المصري
export const EGY_GLOSSARY = `
فهم الكلام المصري:
- «الدرج/الخزنة/الكاش» = كاش الدرج. «سلفة/سحب» = advance. «خصم/جزاء» = deduction. «مكافأة/حافز/بونص/إيداع» = bonus. «المرتب/الماهية/الراتب» = المرتب الشهري.
- «اقفل اليوم/قفّل/جرد الدرج» = close_day. «افتح يوم/ابدأ اليوم» = open_day. «الدين/الآجل/عليه فلوس» = دين العميل.
- المبالغ ممكن تيجي بالحروف: «ميتين»=200، «خمسميه»=500، «ألف ونص»=1500، «تلات تلاف»=3000. حوّلها لرقم، ولو مش متأكد من الرقم اسأل.
- التواريخ: «النهارده/امبارح/أول امبارح/بكره/الخميس اللي فات» حوّلها لتاريخ YYYY-MM-DD بالنسبة لتاريخ النهارده المكتوب فوق.
- الأسماء: ممكن تتكتب من غير همزة أو بتهجئة مختلفة (أحمد/احمد، محمود/محمد). لو الأداة رجّعت أكتر من واحد أو مفيش، اسأل المدير بالكود بدل التخمين.
- لو الجملة فيها أكتر من طلب (مثلًا «اسحب سلفة 100 لأحمد وخصم 20 لمحمود») نفّذ كل واحد بأداته، وكل عملية حساسة بكارت تأكيد لوحدها.
- لو اتقال «اللي قبله/نفس الكلام/كمان واحد» ارجع لآخر طلب في المحادثة واسأل لو الاختلاف مش واضح.`;
