-- ============================================================================
-- patch_tryon.sql — تجربة القصة بالذكاء الاصطناعي (تجريبي)
--   • tryon_log: سجل الاستخدام فقط (مفيش صور بتتخزّن) — للحد اليومي والمتابعة
--   • tryon_reserve / tryon_finish: بتشتغل من الـ Edge Function بمفتاح الخدمة بس
--   • الحدود: لكل عميل (tryon_daily_customer، الافتراضي 2) وعامة للصالون (tryon_daily_global، الافتراضي 150)
--   • tryon_enabled=false في app_settings بيوقف الخدمة
--   • wish_style في ملف اللوك: الشكل اللي العميل عجبه، الحلاق بيشوفه
-- ============================================================================

create table if not exists public.tryon_log (
  id          bigserial primary key,
  customer_id bigint not null references public.customers(id) on delete cascade,
  created_at  timestamptz not null default now(),
  style       text,
  ok          boolean,
  err         text
);
create index if not exists tryon_log_day_idx on public.tryon_log (created_at);
alter table public.tryon_log enable row level security;
drop policy if exists "mgr tryon_log" on public.tryon_log;
create policy "mgr tryon_log" on public.tryon_log for select using (is_mgr());

create or replace function public.tryon_reserve(p_customer bigint, p_style text)
returns bigint
language plpgsql security definer
set search_path to 'public'
as $fn$
declare c customers; v_tz text := my_tz(); v_today date; v_lim_c int; v_lim_g int; v_nc int; v_ng int; v_id bigint;
begin
  select * into c from customers where id = p_customer;
  if not found then raise exception 'مفيش حساب عميل'; end if;
  if coalesce((select value #>> '{}' from app_settings where key = 'tryon_enabled'), 'true') = 'false' then raise exception 'تجربة القصة متوقفة دلوقتي'; end if;
  if c.guardian_id is not null or (c.birthday is not null and c.birthday > (current_date - interval '18 years')::date) then
    raise exception 'الخدمة دي للكبار (18+) بس';
  end if;
  v_lim_c := coalesce(nullif((select value #>> '{}' from app_settings where key = 'tryon_daily_customer'), '')::int, 2);
  v_lim_g := coalesce(nullif((select value #>> '{}' from app_settings where key = 'tryon_daily_global'), '')::int, 150);
  v_today := (now() at time zone v_tz)::date;
  perform pg_advisory_xact_lock(hashtext('tryon_reserve'));
  select count(*) filter (where customer_id = p_customer), count(*) into v_nc, v_ng
    from tryon_log where (created_at at time zone v_tz)::date = v_today and ok is distinct from false;
  if v_nc >= v_lim_c then raise exception 'وصلت للحد اليومي للتجربة (% مرات). جرّب بكرة', v_lim_c; end if;
  if v_ng >= v_lim_g then raise exception 'الخدمة وصلت للحد اليومي، جرّب بكرة'; end if;
  insert into tryon_log(customer_id, style) values (p_customer, left(coalesce(p_style, ''), 60)) returning id into v_id;
  return v_id;
end $fn$;

create or replace function public.tryon_finish(p_id bigint, p_ok boolean, p_err text default null)
returns void language sql security definer set search_path to 'public' as $fn$
  update tryon_log set ok = p_ok, err = left(p_err, 300) where id = p_id $fn$;

revoke all on function public.tryon_reserve(bigint, text), public.tryon_finish(bigint, boolean, text) from public, anon, authenticated;
grant execute on function public.tryon_reserve(bigint, text), public.tryon_finish(bigint, boolean, text) to service_role;

-- الشكل اللي العميل عجبه (بيظهر للحلاق في ملف اللوك)
alter table public.customer_looks add column if not exists wish_style text;

create or replace function public.p_look_json(p_customer bigint)
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select coalesce((select jsonb_build_object('last_cut', l.last_cut, 'clipper', l.clipper, 'grade', l.grade, 'beard_style', l.beard_style, 'notes', l.notes, 'wish_style', l.wish_style, 'updated_at', l.updated_at)
                   from customer_looks l where l.customer_id = p_customer), '{}'::jsonb) $fn$;

create or replace function public.my_look_wish(p_style text)
returns void language plpgsql security definer set search_path to 'public' as $fn$
declare cid bigint; s text := nullif(left(btrim(coalesce(p_style, '')), 80), '');
begin
  select id into cid from customers where user_id = auth.uid();
  if cid is null then raise exception 'مفيش حساب عميل'; end if;
  insert into customer_looks(customer_id, wish_style, updated_at) values (cid, s, now())
  on conflict (customer_id) do update set wish_style = excluded.wish_style;
end $fn$;

revoke all on function public.my_look_wish(text) from public, anon;
grant execute on function public.my_look_wish(text) to authenticated;
