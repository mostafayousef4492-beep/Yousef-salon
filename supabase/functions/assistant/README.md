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
