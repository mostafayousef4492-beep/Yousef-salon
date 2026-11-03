# صالون أبو يوسف — Barber Pro

واجهة ثابتة (HTML/JS) + Supabase. من غير build.

## الصفحات
| المسار | الملف | الاستخدام |
|---|---|---|
| `/` | index.html | تطبيق العميل |
| `/staff` | staff.html | الكاشير/الحلاق/المساعد |
| `/admin` | admin.html | المالك/المدير |
| `/book` | book.html + book.js | حجز بالموبايل من غير حساب |
| `/qr` | qr.html | باركود صفحة الحجز |
| `/catalog` | catalog.html + img/catalog/ | كتالوج القصات العام للزبائن |

## الهيكل
- `src/` — كل كود التطبيق (`core/` الحالة والتنقل، `features/` الشاشات حسب القسم، `ui/` أدوات مشتركة). الصفحات في الجذر بتحمّله.
- `sw.js` — الـ Service Worker. رقم النسخة في السطر 2 (`const V = "salon-vNN"`) لازم يزيد مع أي تعديل في ملفات التطبيق.
- `config.js` — المفاتيح العامة فقط.
- `sql/` — باتشات قاعدة البيانات (`patch_*.sql`) وملفات الإصلاح (`fix_*.sql`). بتتشغّل يدويًا في Supabase SQL Editor. مش بتتنشر على الموقع.
- `tests/` — اختبارات (`tests/db/` للداتابيز، تحتاج Postgres محلي).
- `index.ts` — Edge Function للإشعارات.
- `_archive/` — ملفات قديمة محفوظة (مش بتتنشر): `changes.diff`، `salon-apps-update.zip`، تقرير إصلاح الكتالوج.

## ترتيب النشر لتأمين دخول العميل
1. `sql/patch_customer_login_secure.sql` (على فرع تجريبي الأول).
2. انشر `app.js`.
3. بعد أسبوع–اتنين: `sql/patch_rotate_legacy_customer_passwords.sql` ثم شيل `CPW_OLD` من `app.js`.

## متغيرات Edge Function (`index.ts`)
`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `VAPID_SUBJECT`, `VAPID_PUBLIC`, `VAPID_PRIVATE`, `PUSH_SECRET`
(المفتاح العام فقط في `config.js`، والخاص/السري ما يتحطش في الفرونت أبدًا).

## معروف ومحتاج مراجعة
- صلاحيات "المدير" (منع الحذف والتصفير) في الواجهة بس: لازم تتأكد منها في RLS/الدوال.
- كتابات مالية مباشرة من المتصفح: `salary_payments`, `staff_transactions`, `supplier_payments` — الأفضل تتحول لـ RPC.
- `profiles.update` للأدوار: اتأكد إن RLS بيمنع أي مستخدم يرقّي نفسه.
- تعديل الفواتير الحر لسه مش متنفذ.

## كتالوج القصات
- صفحة مستقلة على `/catalog`، والدخول ليها من الصفحة الرئيسية في تطبيق العميل بعد تسجيل الدخول (مفيش رابط ليها في شاشة الدخول).
- صور القصات داخل `img/catalog/` (53 قصة؛ بعضها أمامي بس وبعضها أمامي/جانبي/خلفي حسب المتاح). الصور استرشادية.
- مش بيتصل بقاعدة البيانات.
