-- patch_challenge_levels_reward.sql — مكافأة نقاط لمرة واحدة لما العميل يوصل مستوى جديد في التحديات
-- كل مستوى ليه خانة «نقاط المكافأة» (الافتراضي 0 = من غير مكافأة). النقاط بتتضاف لحساب ولاء العميل أول مرة بس يوصل المستوى
-- (عند تأكيد التحدي)، ومستحيل تتكرر لنفس العميل والمستوى. مفيش أثر رجعي: العملاء اللي عدّوا المستوى قبل كده بياخدوه مع أول تحدي يتأكد.
-- لازم patch_challenge_wheel.sql متشغّل. آمن للتشغيل أكتر من مرة.
alter table public.challenge_levels add column if not exists reward_points int not null default 0 check (reward_points between 0 and 5000);
create table if not exists public.challenge_level_grants(
  customer_id bigint not null,
  level_id bigint not null references public.challenge_levels(id) on delete cascade,
  points int not null,
  at timestamptz not null default now(),
  primary key (customer_id, level_id)
);
alter table public.challenge_level_grants enable row level security;
drop policy if exists "level grants mgr read" on public.challenge_level_grants;
create policy "level grants mgr read" on public.challenge_level_grants for select using (coalesce(is_mgr(),false));

create or replace function public.challenge_confirm(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare s challenge_spins; v_hours int := p_ref_cfg('challenge_expire_hours',6)::int; v_appt bigint; v_tot int; lv challenge_levels; v_gr jsonb := '[]'::jsonb;
begin
  select * into s from challenge_spins where id = p_id for update;
  if not found or s.status <> 'accepted' then raise exception 'التحدي ده اتأكّد أو اتلغى قبل كده'; end if;
  if s.accepted_at < now() - make_interval(hours => v_hours) then raise exception 'التحدي ده انتهت صلاحيته'; end if;
  select a.id into v_appt from appointments a where a.customer_id = s.customer_id and p_challenge_can(a.id) limit 1;
  if v_appt is null then raise exception 'العميل ده مش على تذكرتك دلوقتي'; end if;
  update challenge_spins set status = 'done', done_at = now(), done_by = auth.uid() where id = p_id;
  if s.points > 0 then perform add_points(s.customer_id, s.points, 'challenge', null, 'تحدي: ' || left(s.title, 80)); end if;
  select coalesce(sum(points),0) into v_tot from challenge_spins where customer_id = s.customer_id and status = 'done';
  for lv in select * from challenge_levels where reward_points > 0 and min_points <= v_tot order by min_points loop
    begin
      insert into challenge_level_grants(customer_id, level_id, points) values (s.customer_id, lv.id, lv.reward_points);
      perform add_points(s.customer_id, lv.reward_points, 'challenge_level', null, 'مكافأة مستوى: ' || left(lv.name, 60));
      v_gr := v_gr || jsonb_build_array(jsonb_build_object('level', lv.name, 'points', lv.reward_points));
    exception when unique_violation then null; end;
  end loop;
  return jsonb_build_object('points', s.points, 'level_rewards', v_gr);
end $$;
-- تراجع: شغّل challenge_confirm من patch_challenge_wheel.sql؛ drop table challenge_level_grants; alter table challenge_levels drop column reward_points;
