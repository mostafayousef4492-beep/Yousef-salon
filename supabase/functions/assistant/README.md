# مساعد صالون أبو يوسف (Edge Function)

مساعد ذكاء اصطناعي للعملاء والموظفين. بيشتغل **بصلاحيات المستخدم نفسه** (مش service role)، فالعميل مايشوفش غير بياناته والموظف كذلك.
مساعد الإدارة هييجي في المرحلة التانية.

## خطوات التفعيل (مرة واحدة)
1. **قاعدة البيانات:** شغّل `sql/patch_assistant.sql` في Supabase SQL Editor (عدّاد يومي + مفتاح إيقاف).
2. **مفتاح الذكاء الاصطناعي** (اختار واحد، ومش بيتحط في الكود ولا في GitHub):
   - **Gemini (للتجربة):** من aistudio.google.com ← Get API key. في Supabase: Edge Functions ← Secrets ← أضف `GEMINI_API_KEY` = المفتاح.
     النموذج الافتراضي `gemini-2.5-flash` (ممكن تغيّره بسر `GEMINI_MODEL`).
   - **Claude (لاحقًا):** من console.anthropic.com ← API Keys، وأضف `ANTHROPIC_API_KEY`. لو الاتنين موجودين Claude هو اللي بيشتغل،
     أو اختار بسر `ASSISTANT_PROVIDER` = `gemini` أو `anthropic`. التبديل من غير أي تعديل في الكود أو إعادة نشر.
3. **نشر الدالة:** `supabase functions deploy assistant` أو من Dashboard ← Edge Functions ← Deploy a new function باسم `assistant`
   وارفع الملفات الثلاثة `index.ts` و`core.ts` و`llm.ts`. سيب «Verify JWT» شغّال.
4. ادمج `staging` في `main`. زرار ✨ بيظهر تحت في تطبيق العملاء وتطبيق الموظفين.

## إعدادات (اختياري — جدول app_settings، المفتاح والقيمة)
- `assistant_enabled` = `false` ← يوقف المساعد للكل فورًا.
- `assistant_limit_customer` (الافتراضي 20) و`assistant_limit_staff` (الافتراضي 40) ← عدد الأسئلة اليومي لكل مستخدم (للتحكم في التكلفة).
- `ASSISTANT_MODEL` (اختياري، لـ Claude) ← الافتراضي `claude-sonnet-5-5`؛ ممكن تحط `claude-haiku-5-5` لتكلفة أقل.

## الأمان
- الأدوات للقراءة فقط. الحجز: المساعد بيجهّز ملخص والعميل بيدوس «تأكيد الحجز» وبعدها التطبيق يستدعي `book_ticket` العادي.
- الدالة بتتحقق من JWT، وكل الاستعلامات بتعدّي على RLS والدوال الحالية (staff_summary وغيرها) اللي بتحدد المسموح لكل مستخدم.
- نتايج قاعدة البيانات بتتعامل كبيانات بس (حماية من prompt injection)، ومفيش محادثات بتتخزن على السيرفر.

## اختبار
`node --experimental-strip-types tests/assistant_core.test.mjs` و`tests/assistant_llm.test.mjs`

## مساعد الإدارة (محلل البيانات) — للمالك/المدير فقط
- **الصلاحية:** الدالة `ai_admin_ok()` (مالك دايمًا؛ المدير ما لم يكن `assistant_admin_manager = false` في `app_settings`). كل دوال `ai_*` بترفض غيرهم من القاعدة نفسها، وزرار ✨ في تطبيق الإدارة مابيظهرش إلا لو القاعدة وافقت.
- **قراءة فقط:** الأدوات (`admin.ts`) بتنادي دوال `ai_*` (stable) من `sql/patch_admin_assistant.sql`. مفيش أداة تكتب/تحذف/تبعت/تقفل يوم.
- **الخصوصية:** المساعد بيطلب البيانات بـ `p_names=false`: مفيش أسماء عملاء ولا تليفونات ولا ملاحظات مصروفات بتروح لمزوّد الذكاء الاصطناعي (أعلى العملاء برقمهم). أسماء الموظفين والخدمات بتروح (لازمة للإجابة). زرار «🔎 عرض الفواتير» في الرد بيفتح التفاصيل بالأسماء مباشرة من القاعدة بجلسة المدير، من غير ما تعدّي على النموذج.
- **الشفافية:** كل أداة بترجّع `period` و`source` و`method` و`data_gaps`، والتعليمات بتلزم المساعد يذكرهم ويصرّح لما البيانات مش كافية. الفروق والنسب في المقارنات بتتحسب بالكود.
- **الحدود:** 60 سؤال/يوم للإدارة (`assistant_limit_admin`)، 6 جولات أدوات للسؤال، فترة أقصاها 93 يوم في الدالة الخلفية (400 في القاعدة)، ونتيجة الأداة مقصوصة عند 10000 حرف. `assistant_enabled=false` بيوقف المساعد للكل.
- **الإعداد:** شغّل `patch_admin_assistant.sql` (بعد `patch_assistant.sql` و`patch_full_report.sql` و`patch_partial_pay.sql`) ثم انشر الدالة (نفس الأسرار: `GEMINI_API_KEY` أو `ANTHROPIC_API_KEY`).
