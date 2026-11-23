-- patch_wheel_prizes.sql — ربط قطاعات عجلة الحظ اللي مالهاش جايزة (كانت بتطلع «حظ أوفر» رغم اسمها)
-- القطاعات: خصم 30% · جلسة تنضيف بشرة 3 مراحل · جلسة تنضيف بشرة 7 مراحل · جلسة علاج القشرة.
-- بيضيف 4 جوايز في كتالوج المكافآت (تكلفة النقاط = سعر الخدمة تقريبًا) وبيربط كل قطاع بجايزته.
-- بيربط القطاعات اللي reward_id بتاعها فاضي بس (مايلمسش أي قطاع متظبط). آمن للتكرار.
begin;
insert into public.loyalty_rewards(name, kind, value, cost, active, service_id)
select v.name, v.kind, v.value, v.cost, true, v.sid
from (values
  ('خصم 30% على الفاتورة', 'pct',     30::numeric, 150, null::bigint),
  ('جلسة تنضيف بشرة 3 مراحل', 'service', 0::numeric, 150, 27::bigint),
  ('جلسة تنضيف بشرة 7 مراحل', 'service', 0::numeric, 300, 15::bigint),
  ('جلسة علاج القشرة', 'service', 0::numeric, 100, 21::bigint)
) v(name, kind, value, cost, sid)
where not exists (select 1 from public.loyalty_rewards r where r.name = v.name);

update public.wheel_slices s set reward_id = r.id
from public.loyalty_rewards r
where s.reward_id is null and (
     (s.label = 'خصم 30%' and r.name = 'خصم 30% على الفاتورة')
  or (s.label = 'جلسة تنضيف بشرة 3 مراحل' and r.name = 'جلسة تنضيف بشرة 3 مراحل')
  or (s.label = 'جلسة تنضيف بشرة 7 مراحل' and r.name = 'جلسة تنضيف بشرة 7 مراحل')
  or (s.label = 'جلسة علاج القشرة' and r.name = 'جلسة علاج القشرة'));
commit;
-- للتأكد بعد التشغيل: select s.label, r.name, r.kind from wheel_slices s left join loyalty_rewards r on r.id = s.reward_id order by s.sort, s.id;
-- تراجع: update wheel_slices set reward_id = null where label in ('خصم 30%','جلسة تنضيف بشرة 3 مراحل','جلسة تنضيف بشرة 7 مراحل','جلسة علاج القشرة');
