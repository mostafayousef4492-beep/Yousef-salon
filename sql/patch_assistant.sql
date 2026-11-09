-- المساعد الذكي: عدّاد استخدام يومي لكل مستخدم (يمنع التكلفة الزايدة) + مفتاح تشغيل/إيقاف.
-- الدالة assistant_hit بتتنادى من الـ Edge Function (بصلاحية المستخدم نفسه) قبل كل سؤال:
--   • assistant_enabled   (app_settings، افتراضي true)  — false بيوقف المساعد للكل
--   • assistant_limit_customer (افتراضي 20 سؤال/يوم)، assistant_limit_staff (افتراضي 40 سؤال/يوم)
-- مفيش بيانات بتتمسح. آمن للتكرار.
create table if not exists public.assistant_usage (
  user_id uuid not null,
  day date not null,
  n integer not null default 0,
  primary key (user_id, day)
);
alter table public.assistant_usage enable row level security;   -- مفيش policies: الوصول بالدالة بس

create or replace function public.assistant_hit()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_uid uuid := auth.uid(); v_role text; v_staff boolean; v_lim int; v_n int; v_on text; v_day date;
  v_tz text := coalesce(nullif(trim(both '"' from (select value::text from app_settings where key = 'timezone')), ''), 'Africa/Cairo');
begin
  if v_uid is null then raise exception 'سجّل دخولك الأول'; end if;
  select coalesce(trim(both '"' from (select value::text from app_settings where key = 'assistant_enabled')), 'true') into v_on;
  if v_on in ('false', '0', 'off') then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  select p.role::text into v_role from profiles p where p.id = v_uid;
  v_staff := v_role in ('owner', 'manager', 'cashier', 'barber', 'assistant');
  v_lim := coalesce(nullif(trim(both '"' from (select value::text from app_settings
             where key = case when v_staff then 'assistant_limit_staff' else 'assistant_limit_customer' end)), '')::int,
             case when v_staff then 40 else 20 end);
  v_day := (now() at time zone v_tz)::date;
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
