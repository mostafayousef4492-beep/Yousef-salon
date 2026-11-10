-- تنفيذ المساعد (مالك/مدير): سجل عمليات + بدون حد يومي للأسئلة + إرسال إشعار لعميل.
-- • assistant_actions: كل عملية بينفّذها المساعد (بعد تأكيدك بزرار) بتتسجل: مين، إيه، بأي بيانات، نجحت ولا فشلت. المالك بس يقراه.
--   كلمة سر الموظف الجديد مابتتسجلش أبدًا. مفيش حد بيكتب في الجدول مباشرة، بس عن طريق assistant_log_action.
-- • assistant_hit: المالك والمدير بدون حد يومي (بيتعدّوا للإحصاء بس). العميل والموظف لسه بحدودهم.
--   assistant_enabled=false لسه بيوقف المساعد للكل.
-- • ai_notify_customer: رسالة من الإدارة لعميل (بتظهر في تطبيقه لحظيًا + إشعار لو مسجّل). بتفحص ai_mgr_ok().
-- المساعد بينفّذ بنفس صلاحياتك بالظبط (نفس دوال التطبيق وسياسات الأمان) — مفيش صلاحية زيادة.
-- شغّله بعد patch_manager_assistant.sql. آمن للتكرار. مفيش بيانات بتتغير.
create table if not exists public.assistant_actions (
  id bigserial primary key,
  user_id uuid not null,
  role text,
  action text not null,
  params jsonb not null default '{}'::jsonb,
  status text not null check (status in ('done', 'failed')),
  result jsonb,
  error text,
  created_at timestamptz not null default now()
);
alter table public.assistant_actions enable row level security;
drop policy if exists assistant_actions_owner_read on public.assistant_actions;
create policy assistant_actions_owner_read on public.assistant_actions for select to authenticated
  using (exists (select 1 from profiles p where p.id = auth.uid() and p.role::text = 'owner'));
revoke all on public.assistant_actions from anon;
grant select on public.assistant_actions to authenticated;
revoke insert, update, delete on public.assistant_actions from authenticated;
create index if not exists assistant_actions_created_idx on public.assistant_actions (created_at desc);

create or replace function public.assistant_log_action(p_action text, p_params jsonb, p_status text, p_result jsonb default null, p_error text default null)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare v_id bigint; v_role text;
begin
  if not ai_mgr_ok() then raise exception 'غير مصرح'; end if;
  if p_status not in ('done', 'failed') then raise exception 'حالة غير صحيحة'; end if;
  select role::text into v_role from profiles where id = auth.uid();
  insert into assistant_actions(user_id, role, action, params, status, result, error)
    values (auth.uid(), v_role, left(coalesce(p_action, '?'), 60), coalesce(p_params, '{}'::jsonb) - 'password' - 'pw', p_status, p_result, left(p_error, 500))
    returning id into v_id;
  return v_id;
end $$;
revoke all on function public.assistant_log_action(text, jsonb, text, jsonb, text) from public, anon;
grant execute on function public.assistant_log_action(text, jsonb, text, jsonb, text) to authenticated;

create or replace function public.ai_notify_customer(p_customer bigint, p_title text, p_body text default null)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare v_id bigint; v_uid uuid; t text := nullif(trim(coalesce(p_title, '')), ''); b text := nullif(trim(coalesce(p_body, '')), '');
begin
  if not ai_mgr_ok() then raise exception 'غير مصرح'; end if;
  if t is null then raise exception 'اكتب عنوان الرسالة'; end if;
  if length(t) > 80 then raise exception 'العنوان أطول من 80 حرف'; end if;
  if b is not null and length(b) > 300 then raise exception 'الرسالة أطول من 300 حرف'; end if;
  select user_id into v_uid from customers where id = p_customer;
  if not found then raise exception 'العميل غير موجود'; end if;
  insert into customer_notifications(customer_id, kind, title, body) values (p_customer, 'staff_message', t, b) returning id into v_id;
  if v_uid is not null then
    begin perform push_send(array[v_uid], t, coalesce(b, ''), null, 'staff_msg', false); exception when others then null; end;
  end if;
  return v_id;
end $$;
revoke all on function public.ai_notify_customer(bigint, text, text) from public, anon;
grant execute on function public.ai_notify_customer(bigint, text, text) to authenticated;

-- الحد اليومي: مالك/مدير بدون حد، الباقي زي ما هو
create or replace function public.assistant_hit()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_uid uuid := auth.uid(); v_role text; v_staff boolean; v_lim int; v_n int; v_on text; v_day date; v_key text;
  v_tz text := coalesce(nullif(trim(both '"' from (select value::text from app_settings where key = 'timezone')), ''), 'Africa/Cairo');
begin
  if v_uid is null then raise exception 'سجّل دخولك الأول'; end if;
  select coalesce(trim(both '"' from (select value::text from app_settings where key = 'assistant_enabled')), 'true') into v_on;
  if v_on in ('false', '0', 'off') then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  select p.role::text into v_role from profiles p where p.id = v_uid;
  v_staff := v_role in ('owner', 'manager', 'cashier', 'barber', 'assistant');
  v_day := (now() at time zone v_tz)::date;
  if v_role in ('owner', 'manager') then
    insert into assistant_usage(user_id, day, n) values (v_uid, v_day, 1)
      on conflict (user_id, day) do update set n = assistant_usage.n + 1;
    return jsonb_build_object('ok', true, 'left', null, 'role', v_role);
  end if;
  v_key := case when v_staff then 'assistant_limit_staff' else 'assistant_limit_customer' end;
  v_lim := coalesce(nullif(trim(both '"' from (select value::text from app_settings where key = v_key)), '')::int, case when v_staff then 40 else 20 end);
  insert into assistant_usage(user_id, day, n) values (v_uid, v_day, 1)
    on conflict (user_id, day) do update set n = assistant_usage.n + 1
    returning n into v_n;
  if v_n > v_lim then
    update assistant_usage set n = v_lim where user_id = v_uid and day = v_day;
    return jsonb_build_object('ok', false, 'reason', 'limit', 'limit', v_lim);
  end if;
  return jsonb_build_object('ok', true, 'left', v_lim - v_n, 'role', coalesce(v_role, 'customer'));
end $$;
revoke all on function public.assistant_hit() from public, anon;
grant execute on function public.assistant_hit() to authenticated;
