-- patch_wheel_prizes_masks.sql — إضافة 3 جوايز لعجلة الحظ: حمام كريم · ماسك صنفرة · ماسك طمي
-- كل جايزة = خدمة مجانية (نفس نظام باقي الجوايز: العميل بياخد كود والكاشير بيطبّقه من نقطة البيع).
-- الخدمات الموجودة: 4 حمام كريم · 9 مسك صنفرة · 10 مسك طمي (10 جنيه لكل واحدة).
-- الوزن 6 لكل قطاع (الأوزان الحالية بتوصل لـ 124، فالتلاتة مع بعض حوالي 13% من اللفات). عدّل الأوزان من شاشة إدارة العجلة.
-- بيضيف اللي مش موجود بس. آمن للتكرار.
begin;
insert into public.loyalty_rewards(name, kind, value, cost, active, service_id)
select v.name, 'service', 0, 10, true, v.sid
from (values
  ('حمام كريم مجاني', 4::bigint),
  ('ماسك صنفرة مجاني', 9::bigint),
  ('ماسك طمي مجاني', 10::bigint)
) v(name, sid)
where exists (select 1 from public.services s where s.id = v.sid)
  and not exists (select 1 from public.loyalty_rewards r where r.name = v.name);

insert into public.wheel_slices(label, reward_id, weight, active, sort)
select v.label, r.id, 6, true, 99
from (values
  ('حمام كريم', 'حمام كريم مجاني'),
  ('ماسك صنفرة', 'ماسك صنفرة مجاني'),
  ('ماسك طمي', 'ماسك طمي مجاني')
) v(label, rname)
join public.loyalty_rewards r on r.name = v.rname
where not exists (select 1 from public.wheel_slices s where s.label = v.label);
commit;
-- للتأكد: select s.label, s.weight, r.name, r.kind, r.service_id from wheel_slices s left join loyalty_rewards r on r.id = s.reward_id order by s.sort, s.id;
-- تراجع: delete from wheel_slices where label in ('حمام كريم','ماسك صنفرة','ماسك طمي'); (الجوايز في loyalty_rewards ممكن تفضل أو تتعطّل: update loyalty_rewards set active=false where name like '%مجاني' and service_id in (4,9,10);)
