# مساعد صالون أبو يوسف (Edge Function)

مساعد ذكاء اصطناعي للعملاء والموظفين. بيشتغل **بصلاحيات المستخدم نفسه** (مش service role)، فالعميل مايشوفش غير بياناته والموظف كذلك.
مساعد الإدارة هييجي في المرحلة التانية.

## خطوات التفعيل (مرة واحدة)
1. **قاعدة البيانات:** شغّل `sql/patch_assistant.sql` في Supabase SQL Editor (عدّاد يومي + مفتاح إيقاف).
2. **مفتاح الذكاء الاصطناعي:** اعمل حساب على console.anthropic.com ← API Keys ← Create Key، وحط رصيد بسيط.
   بعدين في Supabase: Edge Functions ← Secrets ← أضف `ANTHROPIC_API_KEY` = المفتاح. (مش بيتحط في الكود ولا في GitHub.)
3. **نشر الدالة:** `supabase functions deploy assistant` أو من Dashboard ← Edge Functions ← Deploy a new function باسم `assistant`
   وارفع الملفين `index.ts` و`core.ts`. سيب «Verify JWT» شغّال.
4. ادمج `staging` في `main`. زرار ✨ بيظهر تحت في تطبيق العملاء وتطبيق الموظفين.

## إعدادات (اختياري — جدول app_settings، المفتاح والقيمة)
- `assistant_enabled` = `false` ← يوقف المساعد للكل فورًا.
- `assistant_limit_customer` (الافتراضي 20) و`assistant_limit_staff` (الافتراضي 40) ← عدد الأسئلة اليومي لكل مستخدم (للتحكم في التكلفة).
- سر `ASSISTANT_MODEL` (اختياري) ← الافتراضي `claude-sonnet-5-5`؛ ممكن تحط `claude-haiku-5-5` لتكلفة أقل.

## الأمان
- الأدوات للقراءة فقط. الحجز: المساعد بيجهّز ملخص والعميل بيدوس «تأكيد الحجز» وبعدها التطبيق يستدعي `book_ticket` العادي.
- الدالة بتتحقق من JWT، وكل الاستعلامات بتعدّي على RLS والدوال الحالية (staff_summary وغيرها) اللي بتحدد المسموح لكل مستخدم.
- نتايج قاعدة البيانات بتتعامل كبيانات بس (حماية من prompt injection)، ومفيش محادثات بتتخزن على السيرفر.

## اختبار
`node --experimental-strip-types tests/assistant_core.test.mjs`
