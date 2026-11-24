-- patch_bundle_swap.sql — تبديل خدمة جوه الباقة بخدمة بنفس السعر بالظبط
-- الباقة بتفضل بسعرها والخصم زي ما هو (لأن الخدمتين بنفس السعر). مفيش تغيير في pos_checkout ولا في العمولة ولا في الفواتير.
-- بيغيّر دالة bundle_eff بس (نفس الاسم والمدخلات والمخرجات): لو خدمة من الباقة ناقصة، وفي الحجز/الفاتورة خدمة تانية
-- بنفس السعر بالظبط مش من الباقة ومش من خانات الاختيار، بتتحسب بديل ليها (واحدة بواحدة بالترتيب). غير كده الدالة بتتصرف زي ما كانت بالظبط.
-- كل المستهلكين (set_ticket_bundle، pos_checkout) بيشوفوا التبديل تلقائيًا، والسيرفر هو اللي بيتحقق من تساوي السعر.
-- آمن للتشغيل أكتر من مرة. تراجع: patch_bundle_options.sql بيعيد النسخة القديمة من bundle_eff (أو الجزء الأخير من الملف ده).
create or replace function public.bundle_eff(p_bundle bigint, p_ids bigint[])
returns table(service_id bigint, base numeric)
language sql stable security definer set search_path to 'public' as $$
  with ids as (select coalesce(p_ids, '{}'::bigint[]) a),
  fx as (select bi.service_id sid, sv.price pr from bundle_items bi join services sv on sv.id = bi.service_id where bi.bundle_id = p_bundle),
  sr as (
    select c.id sid, b.base
      from bundle_slots bs
      cross join lateral (select bundle_slot_base(bs.bundle_id, bs.group_name) as bid) bb
      cross join lateral (select sv.price as base from services sv where sv.id = bb.bid) b
      left join lateral (select sv.id from services sv, ids where sv.group_name = bs.group_name and sv.active and sv.id = any(ids.a)
                          order by (sv.id = bb.bid) desc, sv.price, sv.id limit 1) c on true
     where bs.bundle_id = p_bundle),
  miss as (select fx.sid, fx.pr, row_number() over (partition by fx.pr order by fx.sid) rn from fx, ids where not (fx.sid = any(ids.a))),
  ext as (
    select sv.id sid, sv.price pr, row_number() over (partition by sv.price order by sv.id) rn
      from services sv, ids
     where sv.active and sv.id = any(ids.a)
       and sv.id not in (select sid from fx)
       and sv.id not in (select sid from sr where sid is not null)
       and (sv.group_name is null or sv.group_name not in (select bs.group_name from bundle_slots bs where bs.bundle_id = p_bundle)))
  select fx.sid, null::numeric from fx, ids where fx.sid = any(ids.a)
  union all select e.sid, null::numeric from miss m join ext e on e.pr = m.pr and e.rn = m.rn
  union all select m.sid, null::numeric from miss m where not exists (select 1 from ext e where e.pr = m.pr and e.rn = m.rn)
  union all select sid, base from sr
$$;
-- (النسخة القديمة للتراجع)
-- create or replace function public.bundle_eff(p_bundle bigint, p_ids bigint[]) returns table(service_id bigint, base numeric) language sql stable security definer set search_path to 'public' as $f$
--   select bi.service_id, null::numeric from bundle_items bi where bi.bundle_id = p_bundle
--   union all
--   select c.id, b.base from bundle_slots bs cross join lateral (select bundle_slot_base(bs.bundle_id, bs.group_name) as bid) bb
--     cross join lateral (select sv.price as base from services sv where sv.id = bb.bid) b
--     left join lateral (select sv.id from services sv where sv.group_name = bs.group_name and sv.active and sv.id = any(coalesce(p_ids, '{}'))
--                         order by (sv.id = bb.bid) desc, sv.price, sv.id limit 1) c on true where bs.bundle_id = p_bundle $f$;
