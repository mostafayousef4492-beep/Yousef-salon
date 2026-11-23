-- patch_challenge_wheel.sql — ABO YOUSEF CHALLENGE: عجلة التحديات (مستقلة عن عجلة الحظ)
-- العجلة بتتلف من تابلت الصنايعي أو من حساب الموظف (مش من تطبيق العميل) على عميل حاضر عنده تذكرة (وصل أو على الكرسي).
-- الموظف بيعرض التحدي ونقاطه على العميل: لو وافق بيتسجّل "مقبول"، وبعد التنفيذ الموظف بيأكّد والنقاط بتتضاف (نقاط ولاء، مرة واحدة لكل لفة).
-- التحديات والنقاط والمستويات والحدود كلها بتتحدد من الإعدادات. موقوفة (challenge_on=false) لحد ما تشغّلها. آمن للتشغيل أكتر من مرة.
-- (لو كنت شغّلت نسخة أقدم منه: بيشيل دوال لفّ العميل القديمة ويشيل إعدادَي التكلفة والحضور اللي مبقاش ليهم لازمة.)

create table if not exists public.challenge_defs(
  id bigserial primary key,
  title text not null,
  kind text not null default 'fun' check (kind in ('fun','barber','surprise')),
  rarity text not null default 'common' check (rarity in ('common','rare','legend')),
  points int not null default 10 check (points >= 0),
  weight int not null default 1 check (weight >= 0),
  active boolean not null default true,
  sort int not null default 0
);
create table if not exists public.challenge_levels(
  id bigserial primary key,
  name text not null,
  min_points int not null default 0 check (min_points >= 0),
  sort int not null default 0
);
create table if not exists public.challenge_spins(
  id bigserial primary key,
  customer_id bigint not null references public.customers(id) on delete cascade,
  def_id bigint references public.challenge_defs(id) on delete set null,
  title text not null,
  rarity text not null,
  points int not null,
  status text not null default 'offered' check (status in ('offered','accepted','declined','cancelled','done')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  done_at timestamptz,
  done_by uuid
);
create index if not exists challenge_spins_cust_idx on public.challenge_spins(customer_id, created_at desc);
create index if not exists challenge_spins_status_idx on public.challenge_spins(status, accepted_at);

alter table public.challenge_defs enable row level security;
alter table public.challenge_levels enable row level security;
alter table public.challenge_spins enable row level security;
drop policy if exists "challenge defs mgr" on public.challenge_defs;
create policy "challenge defs mgr" on public.challenge_defs for all using (is_mgr()) with check (is_mgr());
drop policy if exists "challenge levels mgr" on public.challenge_levels;
create policy "challenge levels mgr" on public.challenge_levels for all using (is_mgr()) with check (is_mgr());
drop policy if exists "challenge spins mgr read" on public.challenge_spins;
create policy "challenge spins mgr read" on public.challenge_spins for select using (is_mgr());
-- العميل والصنايعي بيتعاملوا من الدوال بس (security definer)

insert into public.rule_defs(key, grp, label, hint, kind, min, max, def, danger, kw, sort) values
 ('challenge_on','الولاء','عجلة التحدي شغّالة','موقوفة افتراضيًا. بتتلف من التابلت أو حساب الموظف. التحديات والنقاط من شاشة عجلة التحدي','bool',null,null,'false',false,'تحدي تحديات challenge عجلة',130),
 ('challenge_daily_max','الولاء','أقصى لفات تحدي في اليوم للعميل','بيشمل اللي رفضه','num',1,20,'1',false,'تحدي challenge حد يومي',131),
 ('challenge_month_points','الولاء','أقصى نقاط تتوزّع من التحديات في الشهر (للصالون كله)','لما يخلص الرقم العجلة بتقفل لحد الشهر الجاي. صفر = من غير حد (مش مفضّل)','num',0,1000000,'1000',true,'تحدي challenge سقف نقاط',132),
 ('challenge_expire_hours','الولاء','التحدي المقبول بيفضل صالح كام ساعة','بعدها بيتلغي ومفيش نقاط','num',1,72,'6',false,'تحدي challenge مدة صلاحية',133)

on conflict (key) do nothing;

-- مستويات مبدئية (بقيم مخفّضة) وتحديات مبدئية من خطة ABO YOUSEF CHALLENGE بنقاط مخفّضة. عدّلها من شاشة الإدارة.
insert into public.challenge_levels(name, min_points, sort)
select * from (values ('مبتدئ',0,1),('شجاع',50,2),('محترف',150,3),('أسطورة',300,4),('ملك التحديات',600,5)) v(n,m,s)
where not exists (select 1 from public.challenge_levels);

insert into public.challenge_defs(title, kind, rarity, points, weight, sort)
select * from (values
 ('يغنّي مقطع أغنية قدام الموجودين','fun','common',15,10,1),
 ('يقلّد صوت شخصية مشهورة','fun','common',15,10,2),
 ('يقول نكتة ويضحّك الحلاق','fun','common',10,10,3),
 ('يتكلم بلهجة مختلفة لمدة 5 دقايق','fun','common',15,10,4),
 ('يعمل إعلان تمثيلي عن الصالون','fun','rare',25,4,5),
 ('يعمل مقابلة صحفية مع الحلاق','fun','rare',20,4,6),
 ('يمثّل إنه حلاق لمدة دقيقة','fun','rare',20,4,7),
 ('تحدي الضحك مع الحلاق','fun','common',15,10,8),
 ('الحلاق يختارله لقب مضحك','fun','common',10,10,9),
 ('تعبير وجه مضحك (تصوير بموافقتك بس)','fun','common',15,10,10),
 ('الحلاق يختار أغنية والعميل يغنيها','surprise','common',15,10,11),
 ('إعلان عن الصالون في 30 ثانية','surprise','rare',25,4,12),
 ('تحدي تمثيل مع الحلاق اللي يختاره','surprise','rare',20,4,13),
 ('يشرح قصة شعر كأنه خبير عالمي','surprise','common',15,10,14),
 ('يختار اسم مضحك لنفسه داخل اللعبة','surprise','common',10,10,15),
 ('تحدي عدم الضحك لمدة دقيقة','surprise','common',15,10,16),
 ('يقدّم نشرة أخبار الصالون','surprise','rare',25,4,17),
 ('اختيار قصة عشوائية من الكتالوج','barber','rare',40,1,18),
 ('الحلاق يختار القصة بالكامل','barber','legend',50,1,19),
 ('تغيير شكل الشنب','barber','rare',30,4,20),
 ('تجربة قصة غير معتادة','barber','legend',45,1,21),
 ('نص الدقن للتصوير فقط (بموافقتك)','barber','rare',30,4,22),
 ('تغيير اللوك بالكامل','barber','legend',60,1,23),
 ('تحويل اللوك لشخصية مشهورة','barber','legend',60,1,24),
 ('Old Man Transformation','barber','legend',70,1,25)
) v(t,k,r,p,w,s)
where not exists (select 1 from public.challenge_defs);

delete from public.rule_defs where key in ('challenge_need_visit','challenge_cost');
drop function if exists public.challenge_status();
drop function if exists public.challenge_spin();
drop function if exists public.challenge_accept(bigint);
drop function if exists public.challenge_decline(bigint);

-- مستوى العميل من نقاط تحدياته المؤكدة
create or replace function public.p_challenge_level(p_pts int)
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'name', (select name from challenge_levels where min_points <= p_pts order by min_points desc, sort desc limit 1),
    'next_name', (select name from challenge_levels where min_points > p_pts order by min_points limit 1),
    'next_at', (select min_points from challenge_levels where min_points > p_pts order by min_points limit 1))
$$;
revoke all on function public.p_challenge_level(int) from public, anon;

-- مين يقدر يشغّل عجلة التحدي على تذكرة: الصنايعي على تذكرته، والمدير/الكاشير على أي تذكرة حاضرة
create or replace function public.p_challenge_can(p_appt bigint)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from appointments a where a.id = p_appt and a.status::text in ('checked_in','in_service')
     and ((exists (select 1 from profiles p where p.id = auth.uid() and p.role::text = 'barber') and a.barber_id = auth.uid())
          or coalesce(is_mgr(), false) or coalesce(can_use_pos(), false)))
$$;
revoke all on function public.p_challenge_can(bigint) from public, anon;

-- العملاء الحاضرين دلوقتي (للعجلة) + التحدي المفتوح لكل واحد
create or replace function public.challenge_present()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_hours int := p_ref_cfg('challenge_expire_hours',6)::int; v_on boolean := p11_cfg_bool('challenge_on', false); v_max int := p_ref_cfg('challenge_daily_max',1)::int;
begin
  if not (coalesce(is_mgr(), false) or coalesce(can_use_pos(), false) or exists (select 1 from profiles where id = auth.uid() and role::text = 'barber')) then raise exception 'غير مصرح'; end if;
  return jsonb_build_object('on', v_on, 'list', case when not v_on then '[]'::jsonb else coalesce((
    select jsonb_agg(jsonb_build_object('appt', a.id, 'ticket', a.ticket_code, 'customer', c.name, 'status', a.status::text,
       'earned', e.pts, 'level', p_challenge_level(e.pts),
       'left_today', greatest(v_max - (select count(*) from challenge_spins x where x.customer_id = c.id and x.created_at > now() - interval '1 day'), 0),
       'current', (select jsonb_build_object('id', s.id, 'title', s.title, 'rarity', s.rarity, 'points', s.points, 'status', s.status)
                     from challenge_spins s where s.customer_id = c.id
                      and ((s.status = 'offered' and s.created_at > now() - interval '1 hour') or (s.status = 'accepted' and s.accepted_at > now() - make_interval(hours => v_hours)))
                     order by s.id desc limit 1)) order by a.status::text desc, a.id)
    from appointments a join customers c on c.id = a.customer_id
    cross join lateral (select coalesce(sum(points),0)::int pts from challenge_spins y where y.customer_id = c.id and y.status = 'done') e
   where p_challenge_can(a.id)), '[]'::jsonb) end);
end $$;

create or replace function public.challenge_spin(p_appt bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a appointments; c customers; v_today int; v_max int := p_ref_cfg('challenge_daily_max',1)::int; v_cap int := p_ref_cfg('challenge_month_points',1000)::int;
        v_hours int := p_ref_cfg('challenge_expire_hours',6)::int; v_tot int; v_pick int; v_acc int := 0; d challenge_defs; v_ch challenge_defs; v_month int; v_id bigint; v_open int; v_room int;
begin
  if not p11_cfg_bool('challenge_on', false) then raise exception 'عجلة التحدي مش شغّالة دلوقتي'; end if;
  if not p_challenge_can(p_appt) then raise exception 'العميل ده مش حاضر على تذكرتك'; end if;
  select * into a from appointments where id = p_appt;
  select * into c from customers where id = a.customer_id for update;
  select count(*) into v_open from challenge_spins where customer_id = c.id
     and ((status = 'offered' and created_at > now() - interval '1 hour') or (status = 'accepted' and accepted_at > now() - make_interval(hours => v_hours)));
  if v_open > 0 then raise exception 'العميل ده عنده تحدي لسه مخلصش'; end if;
  select count(*) into v_today from challenge_spins where customer_id = c.id and created_at > now() - interval '1 day';
  if v_today >= v_max then raise exception 'العميل ده وصل للحد الأقصى من لفات التحدي النهارده'; end if;
  select coalesce(sum(points),0) into v_month from challenge_spins where created_at >= date_trunc('month', now()) and status in ('done','accepted');
  v_room := case when v_cap > 0 then greatest(v_cap - v_month, 0) else 2147483647 end;
  select coalesce(sum(weight),0) into v_tot from challenge_defs where active and points <= v_room;
  if v_tot <= 0 then raise exception 'عجلة التحدي مقفولة لحد الشهر الجاي'; end if;
  v_pick := floor(random() * v_tot)::int;
  for d in select * from challenge_defs where active and points <= v_room order by sort, id loop
    v_acc := v_acc + d.weight;
    if v_pick < v_acc then v_ch := d; exit; end if;
  end loop;
  insert into challenge_spins(customer_id, def_id, title, rarity, points) values (c.id, v_ch.id, v_ch.title, v_ch.rarity, v_ch.points) returning id into v_id;
  return jsonb_build_object('id', v_id, 'customer', c.name, 'title', v_ch.title, 'rarity', v_ch.rarity, 'points', v_ch.points);
end $$;

-- الموظف بيسجّل رد العميل (وافق/رفض) بعد ما يعرض عليه التحدي ونقاطه
create or replace function public.challenge_answer(p_id bigint, p_accept boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare s challenge_spins; v_appt bigint;
begin
  select * into s from challenge_spins where id = p_id for update;
  if not found or s.status <> 'offered' or s.created_at < now() - interval '1 hour' then raise exception 'التحدي ده مش متاح'; end if;
  select a.id into v_appt from appointments a where a.customer_id = s.customer_id and p_challenge_can(a.id) limit 1;
  if v_appt is null then raise exception 'العميل ده مش على تذكرتك'; end if;
  update challenge_spins set status = case when p_accept then 'accepted' else 'declined' end, accepted_at = case when p_accept then now() end where id = p_id;
end $$;

create or replace function public.challenge_confirm(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare s challenge_spins; v_hours int := p_ref_cfg('challenge_expire_hours',6)::int; v_appt bigint;
begin
  select * into s from challenge_spins where id = p_id for update;
  if not found or s.status <> 'accepted' then raise exception 'التحدي ده اتأكّد أو اتلغى قبل كده'; end if;
  if s.accepted_at < now() - make_interval(hours => v_hours) then raise exception 'التحدي ده انتهت صلاحيته'; end if;
  select a.id into v_appt from appointments a where a.customer_id = s.customer_id and p_challenge_can(a.id) limit 1;
  if v_appt is null then raise exception 'العميل ده مش على تذكرتك دلوقتي'; end if;
  update challenge_spins set status = 'done', done_at = now(), done_by = auth.uid() where id = p_id;
  if s.points > 0 then perform add_points(s.customer_id, s.points, 'challenge', null, 'تحدي: ' || left(s.title, 80)); end if;
  return jsonb_build_object('points', s.points);
end $$;

create or replace function public.challenge_cancel(p_id bigint)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare s challenge_spins;
begin
  select * into s from challenge_spins where id = p_id and status in ('offered','accepted') for update;
  if not found then raise exception 'التحدي ده مش متاح'; end if;
  if not exists (select 1 from appointments a where a.customer_id = s.customer_id and p_challenge_can(a.id)) then raise exception 'العميل ده مش على تذكرتك'; end if;
  update challenge_spins set status = 'cancelled' where id = p_id;
end $$;

-- تابلت الصنايعي: التحديات المقبولة لعملاء الصنايعي الحاضرين (للتأكيد بعد التنفيذ)
create or replace function public.barber_challenges()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_hours int := p_ref_cfg('challenge_expire_hours',6)::int;
begin
  if not exists (select 1 from profiles where id = auth.uid() and role::text = 'barber') then raise exception 'غير مصرح'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'customer', c.name, 'title', s.title, 'rarity', s.rarity, 'points', s.points) order by s.accepted_at)
    from challenge_spins s join customers c on c.id = s.customer_id
   where s.status = 'accepted' and s.accepted_at > now() - make_interval(hours => v_hours)
     and exists (select 1 from appointments a where a.customer_id = s.customer_id and p_challenge_can(a.id))), '[]'::jsonb);
end $$;

create or replace function public.challenge_report(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not coalesce(is_mgr(), false) then raise exception 'غير مصرح'; end if;
  return jsonb_build_object(
    'spins', (select count(*) from challenge_spins where created_at > now() - make_interval(days => p_days)),
    'accepted', (select count(*) from challenge_spins where status in ('accepted','done') and created_at > now() - make_interval(days => p_days)),
    'done', (select count(*) from challenge_spins where status = 'done' and created_at > now() - make_interval(days => p_days)),
    'points_given', (select coalesce(sum(points),0) from challenge_spins where status = 'done' and created_at > now() - make_interval(days => p_days)),
    'pending', (select count(*) from challenge_spins where status = 'accepted'),
    'by_title', (select coalesce(jsonb_agg(jsonb_build_object('title', title, 'n', n, 'done', d) order by n desc), '[]'::jsonb) from (select title, count(*) n, count(*) filter (where status='done') d from challenge_spins where created_at > now() - make_interval(days => p_days) group by title limit 20) q));
end $$;

revoke all on function public.challenge_present(), public.challenge_spin(bigint), public.challenge_answer(bigint, boolean), public.challenge_confirm(bigint), public.challenge_cancel(bigint), public.barber_challenges(), public.challenge_report(int) from public, anon;
grant execute on function public.challenge_present(), public.challenge_spin(bigint), public.challenge_answer(bigint, boolean), public.challenge_confirm(bigint), public.challenge_cancel(bigint), public.barber_challenges(), public.challenge_report(int) to authenticated;
-- تراجع: drop function challenge_present(), challenge_spin(bigint), challenge_answer(bigint,boolean), challenge_confirm(bigint), challenge_cancel(bigint), barber_challenges(), challenge_report(int), p_challenge_can(bigint), p_challenge_level(int); drop table challenge_spins, challenge_defs, challenge_levels; delete from rule_defs where key like 'challenge_%';
