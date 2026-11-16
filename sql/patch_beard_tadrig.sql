-- ============================================================
-- «تدريج» مكان «عادي» في حلاقة الذقن
-- خدمة 2 («حلاقة ذقن» الأصلية، 50ج، مربوطة بالحجوزات والباقات) بتبقى هي خيار «تدريج» (مدته 30 دقيقة زي خيار التدريج).
-- خدمة 37 (خيار «تدريج» المكرر، نفس السعر) بتتوقف وتاخد اسم «(مكرر)» — مفيش حاجة بتتمسح.
-- الرجوع: خدمة 2: option_label='عادي' و duration_min=20 ، خدمة 37: option_label='تدريج' و active=true.
-- شغّل الملف كله مرة واحدة (Ctrl+A ثم Run). آمن للتكرار.
-- ============================================================
create table if not exists public.service_menu_backup as
  select id, name, group_name, option_label, active, now() as saved_at from public.services where false;
insert into public.service_menu_backup(id, name, group_name, option_label, active)
  select s.id, s.name, s.group_name, s.option_label, s.active from public.services s
  where s.id in (2, 37) and not exists (select 1 from public.service_menu_backup b where b.id = s.id);

-- الخطوة 1 (أمر منفصل لأن قيد «مجموعة + اسم خيار» بيتشيك صف صف): المكرر الأول
update public.services set option_label = 'تدريج (مكرر)', active = false
 where id = 37 and name = 'حلاقة ذقن — تدريج' and group_name = 'حلاقة ذقن' and option_label = 'تدريج';

-- الخطوة 2: الخدمة الأصلية تبقى «تدريج»
update public.services set option_label = 'تدريج', duration_min = 30
 where id = 2 and name = 'حلاقة ذقن' and group_name = 'حلاقة ذقن' and option_label = 'عادي';
