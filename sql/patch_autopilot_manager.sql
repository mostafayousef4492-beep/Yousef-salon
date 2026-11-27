-- التشغيل الذاتي في دور المدير: السيستم بينفّذ فعلًا (مش اقتراح) شغل المدير الروتيني في حدود أرقام المالك.
-- بيحتاج patch_autopilot.sql و patch_autopilot_areas.sql متشغّلين قبله. مقفول افتراضيًا (mgr_on=false) ولازم المفتاح الرئيسي enabled يكون شغّال كمان.
-- اللي بينفّذه (كل واحد له مفتاح وحد يومي):
--   1) طلبات استبدال نقاط العملاء: بينفّذ الاستبدال بنفس دالة التطبيق (بتتحقق من رصيد العميل) لحد عدد في اليوم.
--   2) تحديات الموظفين اللي مستنية تأكيد (بعد 10 دقايق): بيأكّدها لحد عدد في اليوم.
--   3) طلبات استبدال نقاط الموظفين: بيوافق لو تكلفتها ≤ الحد ولحد عدد في اليوم.
--   4) فتح يوم العمل: بيفتحه بعد الساعة اللي المالك يحددها، لو مفيش يوم مفتوح. لو يوم امبارح ماتقفلش (بالجرد) بيتوقف ويرفعلك اقتراح.
-- اللي مبينفّذوش أبدًا: أي حركة فلوس (سحب، مصروف، راتب، سلفة)، قفل اليوم (محتاج جرد فعلي للدرج)، تأكيد مدفوعات العملاء، تغيير الصلاحيات.
-- كل قرار بيتسجّل في «سجل التشغيل الذاتي» وبيوصل للمالك إشعار. آمن لو اتشغّل أكتر من مرة.

alter table public.autopilot_policy
  add column if not exists mgr_on boolean not null default false,
  add column if not exists mgr_redeem boolean not null default true,
  add column if not exists mgr_redeem_daily_max int not null default 5 check (mgr_redeem_daily_max between 0 and 50),
  add column if not exists mgr_ch boolean not null default true,
  add column if not exists mgr_ch_daily_max int not null default 5 check (mgr_ch_daily_max between 0 and 50),
  add column if not exists mgr_sredeem boolean not null default true,
  add column if not exists mgr_sredeem_max_cost int not null default 200 check (mgr_sredeem_max_cost >= 0),
  add column if not exists mgr_sredeem_daily_max int not null default 3 check (mgr_sredeem_daily_max between 0 and 50),
  add column if not exists mgr_openday boolean not null default true,
  add column if not exists mgr_open_hour int not null default 10 check (mgr_open_hour between 0 and 23);

-- السماح لقرار النظام بفتح اليوم (بنفس دالة التطبيق وكل حمايتها). مرة واحدة بس.
do $$
declare v_def text; v_new text;
begin
  select pg_get_functiondef('public.open_business_day(date)'::regprocedure) into v_def;
  if v_def like '%app.autopilot%' then return; end if;
  v_new := replace(v_def, 'if not is_mgr() then raise exception ''غير مصرح''; end if;',
                   'if not (coalesce(is_mgr(), false) or coalesce(current_setting(''app.autopilot'', true), '''') = ''1'') then raise exception ''غير مصرح''; end if;');
  assert v_new <> v_def, 'open_business_day: anchor not found';
  execute v_new;
end $$;

create or replace function public.autopilot_manager_run()
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare pol autopilot_policy; v_tz text := my_tz(); v_today date; v_hr int; n int := 0; q int; r record; v_code text;
begin
  select * into pol from autopilot_policy where id = 1;
  if not found or not pol.enabled or not pol.mgr_on then return 0; end if;
  v_today := (now() at time zone v_tz)::date;
  v_hr := extract(hour from (now() at time zone v_tz))::int;

  -- 1) استبدال نقاط العملاء
  if pol.mgr_redeem then
    select pol.mgr_redeem_daily_max - count(*) into q from autopilot_log
     where kind = 'mgr_redeem' and decision = 'approved' and (at at time zone v_tz)::date = v_today;
    for r in select id, customer_id, reward_id from redeem_requests
              where status = 'pending' and created_at < now() - interval '5 minutes'
                and not exists (select 1 from autopilot_log l where l.kind = 'mgr_redeem' and l.decision = 'error' and l.ref = redeem_requests.id::text)
              order by created_at limit greatest(q, 0) loop
      begin
        v_code := p17_core_redeem(r.customer_id, r.reward_id);
        update redeem_requests set status = 'approved', code = v_code, decided_at = now(), decided_by = null where id = r.id and status = 'pending';
        insert into autopilot_log(kind, ref, decision, detail) values ('mgr_redeem', r.id::text, 'approved', jsonb_build_object('customer', r.customer_id, 'reward', r.reward_id, 'code', v_code));
        n := n + 1;
      exception when others then
        insert into autopilot_log(kind, ref, decision, detail) values ('mgr_redeem', r.id::text, 'error', jsonb_build_object('err', sqlerrm));
      end;
    end loop;
  end if;

  -- 2) تحديات الموظفين
  if pol.mgr_ch then
    select pol.mgr_ch_daily_max - count(*) into q from autopilot_log
     where kind = 'mgr_ch' and decision = 'approved' and (at at time zone v_tz)::date = v_today;
    for r in select id, staff_id, title from staff_ch_log where status = 'claimed' and created_at < now() - interval '10 minutes' order by created_at limit greatest(q, 0) loop
      update staff_ch_log set status = 'confirmed', decided_by = null, decided_at = now() where id = r.id and status = 'claimed';
      insert into autopilot_log(kind, ref, decision, detail) values ('mgr_ch', r.id::text, 'approved', jsonb_build_object('staff', r.staff_id, 'title', r.title));
      n := n + 1;
    end loop;
  end if;

  -- 3) استبدال نقاط الموظفين
  if pol.mgr_sredeem then
    select pol.mgr_sredeem_daily_max - count(*) into q from autopilot_log
     where kind = 'mgr_sredeem' and decision = 'approved' and (at at time zone v_tz)::date = v_today;
    for r in select id, staff_id, label, cost from staff_redeems where status = 'pending' and cost <= pol.mgr_sredeem_max_cost and created_at < now() - interval '10 minutes' order by created_at limit greatest(q, 0) loop
      update staff_redeems set status = 'done', resolved_by = null, resolved_at = now() where id = r.id and status = 'pending';
      insert into autopilot_log(kind, ref, decision, detail) values ('mgr_sredeem', r.id::text, 'approved', jsonb_build_object('staff', r.staff_id, 'label', r.label, 'cost', r.cost));
      n := n + 1;
    end loop;
  end if;

  -- 4) فتح يوم العمل
  if pol.mgr_openday and v_hr >= pol.mgr_open_hour
     and not exists (select 1 from business_days where closed_at is null)
     and not exists (select 1 from autopilot_log l where l.kind = 'mgr_openday' and l.ref = v_today::text) then
    begin
      perform set_config('app.autopilot', '1', true);
      perform open_business_day(null);
      perform set_config('app.autopilot', '0', true);
      insert into autopilot_log(kind, ref, decision, detail) values ('mgr_openday', v_today::text, 'approved', jsonb_build_object('day', v_today));
      n := n + 1;
    exception when others then
      perform set_config('app.autopilot', '0', true);
      insert into autopilot_log(kind, ref, decision, detail) values ('mgr_openday', v_today::text, 'escalated', jsonb_build_object('why', left(sqlerrm, 200)));
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('cash', 'open_day_failed', v_today::text, 'السيستم مقدرش يفتح اليوم', left(sqlerrm, 200), 'cash')
        on conflict (kind, ref) do nothing;
      n := n + 1;
    end;
  end if;

  if n > 0 then
    begin
      perform push_send(push_staff_ids(array['owner'], null, null), 'التشغيل الذاتي (دور المدير)', 'نفّذ ' || n || ' قرار. شوف السجل في «التشغيل الذاتي».', 'auto',
                        'ap_mgr_' || to_char(now() at time zone v_tz, 'YYYYMMDDHH24MI'), false);
    exception when others then null;
    end;
  end if;
  return n;
end $$;

create or replace function public.autopilot_save_mgr(p_policy jsonb)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not is_owner() then raise exception 'السياسة للمالك بس'; end if;
  update autopilot_policy set
    mgr_on = coalesce((p_policy->>'mgr_on')::boolean, mgr_on),
    mgr_redeem = coalesce((p_policy->>'mgr_redeem')::boolean, mgr_redeem),
    mgr_redeem_daily_max = coalesce((p_policy->>'mgr_redeem_daily_max')::int, mgr_redeem_daily_max),
    mgr_ch = coalesce((p_policy->>'mgr_ch')::boolean, mgr_ch),
    mgr_ch_daily_max = coalesce((p_policy->>'mgr_ch_daily_max')::int, mgr_ch_daily_max),
    mgr_sredeem = coalesce((p_policy->>'mgr_sredeem')::boolean, mgr_sredeem),
    mgr_sredeem_max_cost = coalesce((p_policy->>'mgr_sredeem_max_cost')::int, mgr_sredeem_max_cost),
    mgr_sredeem_daily_max = coalesce((p_policy->>'mgr_sredeem_daily_max')::int, mgr_sredeem_daily_max),
    mgr_openday = coalesce((p_policy->>'mgr_openday')::boolean, mgr_openday),
    mgr_open_hour = coalesce((p_policy->>'mgr_open_hour')::int, mgr_open_hour),
    updated_by = auth.uid(), updated_at = now()
   where id = 1;
  insert into autopilot_log(kind, ref, decision, detail) values ('policy', null, 'changed', p_policy);
end $$;

do $$
begin
  revoke all on function public.autopilot_manager_run() from public, anon, authenticated;
  grant execute on function public.autopilot_manager_run() to service_role;
  revoke all on function public.autopilot_save_mgr(jsonb) from public, anon;
  grant execute on function public.autopilot_save_mgr(jsonb) to authenticated, service_role;
  if exists (select 1 from cron.job where jobname = 'autopilot-manager') then perform cron.unschedule('autopilot-manager'); end if;
  perform cron.schedule('autopilot-manager', '*/5 * * * *', 'select public.autopilot_manager_run()');
end $$;

notify pgrst, 'reload schema';
