# صالون أبو يوسف — Barber Pro

واجهة ثابتة (HTML/JS) + Supabase. من غير build: `app.js` هو الملف الحي الوحيد.

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
- `app.js` — كل المنطق (الأدوار، الكاشير، الحجوزات، العملاء، التذكير، المالية...). عدّل هنا بس.
- `sql/` — باتشات الداتابيز (ملحوظة: باتشات 4–11 و `patch_open_invoices` و `booking_queue_upgrade` مش في الأرشيف ده، لازم تتحط هنا).
- `tests/` — اختبارات (شغّل `node tests/book_client.test.mjs`؛ اختبارات الداتابيز لازم مشروع تجريبي).
- `index.ts` — Edge Function للإشعارات.
- `_archive/` — نسخ قديمة (ملفات `.js` المنفصلة ومجلد `src/` اللي ما كانوش متوصلين). مش بتتنشر (`.vercelignore`).

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
- صفحة عامة مستقلة على `/catalog`، مرتبطة من واجهة العميل.
- صور أمامية وجانبية وخلفية للقصات داخل `img/catalog/` (27 قصة × 3 زوايا).
- مش محتاج تسجيل دخول ومش بيتصل بقاعدة البيانات.
