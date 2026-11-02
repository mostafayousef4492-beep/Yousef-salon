-- ============================================================================
-- صلاحيات الأدوار الافتراضية قابلة للتعديل من مركز التحكم (جدول الأدوار).
-- • جدول role_perms: الصلاحيات الافتراضية لكل دور (كاشير / حلاق / مساعد). اللي مفيهوش صف بيفضل على الأصل الثابت.
-- • perm_defaults(role) بقت بتقرا الجدول (لو فيه صف) وإلا الأصل — فكل دوال القاعدة اللي بتستخدم has_perm بتتأثر لوحدها.
-- • استثناء الموظف (perms في profiles) بيفضل أقوى من افتراضي الدور، زي ما هو.
-- • set_role_perms: المالك بس. clean_perm_overrides: بيشيل من الموظفين الاستثناءات المطابقة لافتراضي الدور
--   عشان تسمع تغيير الدور (بيسجّل في settings_history).
-- آمن للتكرار. مفيش تغيير في سلوك أي حد النهارده: الجدول بيتزرع بنفس القيم الحالية.
-- ============================================================================
create table if not exists public.role_perms (
  role user_role primary key,
  perms jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table public.role_perms enable row level security;   -- الوصول بالدوال بس
revoke all on public.role_perms from anon, authenticated;

-- الأصل الثابت (نفس القيم القديمة بالظبط)
create or replace function public.perm_defaults_builtin(r user_role) returns jsonb
language sql immutable set search_path to 'public', 'pg_temp' as $$
  select case r
    when 'cashier' then '{"use_pos":true,"view_stock":true,"view_invoices":true,"manage_appts":true,"view_customers":true,"view_customer_phone":true,"use_attendance":true}'::jsonb
    when 'barber'  then '{"view_own_sales":true,"view_own_commission":true,"view_own_finance":true,"view_own_reviews":true,"view_own_schedule":true,"use_attendance":true}'::jsonb
    when 'assistant' then '{"use_attendance":true,"view_own_finance":true}'::jsonb
    else '{}'::jsonb end $$;

-- زرع القيم الحالية الفعلية (اللي الواجهة والقاعدة بيطبّقوها دلوقتي): الكاشير ليه cash_ops والكوفي، والحلاق ليه التارجت
insert into public.role_perms(role, perms) values
  ('cashier',   perm_defaults_builtin('cashier')   || '{"cash_ops":true,"use_cafe":true}'::jsonb),
  ('barber',    perm_defaults_builtin('barber')    || '{"view_own_target":true}'::jsonb),
  ('assistant', perm_defaults_builtin('assistant'))
on conflict (role) do nothing;

create or replace function public.perm_defaults(r user_role) returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select coalesce((select rp.perms from role_perms rp where rp.role = r), perm_defaults_builtin(r)) $$;

-- الخزنة: الافتراضي من الدور (الكاشير true زي الأول)
create or replace function public.p16_cash_ops() returns boolean
language sql stable security definer set search_path to 'public' as $$
  select coalesce((select case when p.role::text in ('owner','manager') then true
                               when p.perms ? 'cash_ops' then coalesce((p.perms->>'cash_ops')::boolean, false)
                               else coalesce((perm_defaults(p.role)->>'cash_ops')::boolean, false) end
                     from profiles p where p.id = auth.uid()), false) $$;

-- الكوفي: استثناء الموظف، وإلا افتراضي الدور لو متحدد، وإلا بيتبع الكاشير (السلوك القديم)
create or replace function public.can_use_cafe() returns boolean
language plpgsql stable security definer set search_path to 'public' as $$
declare r text; pm jsonb; d jsonb;
begin
  select p.role::text, p.perms into r, pm from profiles p where p.id = auth.uid();
  if r is null then return false; end if;
  if r in ('owner','manager') then return true; end if;
  if pm is not null and pm ? 'use_cafe' then return coalesce((pm->>'use_cafe')::boolean, false); end if;
  d := perm_defaults(r::user_role);
  if d ? 'use_cafe' then return coalesce((d->>'use_cafe')::boolean, false); end if;
  return coalesce(can_use_pos(), false);
end $$;

-- الواجهة بتقرا الافتراضي من هنا
create or replace function public.role_perm_defaults() returns jsonb
language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object('cashier', perm_defaults('cashier'), 'barber', perm_defaults('barber'), 'assistant', perm_defaults('assistant')) $$;
revoke all on function public.role_perm_defaults() from public, anon;
grant execute on function public.role_perm_defaults() to authenticated;

create or replace function public.p33_perm_keys() returns text[] language sql immutable as $$
  select array['use_pos','cash_ops','use_cafe','view_stock','restock','view_invoices','manage_appts','view_customers','view_customer_phone',
               'view_reports','use_attendance','view_own_schedule','view_own_sales','view_own_commission','view_own_finance','view_own_reviews',
               'manage_announcements','view_own_target','approve_discount'] $$;

create or replace function public.set_role_perms(p_role text, p_perms jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare k text; old jsonb; v jsonb := '{}'::jsonb;
begin
  if not is_owner() then raise exception 'للمالك فقط'; end if;
  if p_role not in ('cashier','barber','assistant') then raise exception 'دور غير صحيح'; end if;
  if p_perms is null or jsonb_typeof(p_perms) <> 'object' then raise exception 'صلاحيات غير صحيحة'; end if;
  for k in select jsonb_object_keys(p_perms) loop
    if not (k = any (p33_perm_keys())) then raise exception 'صلاحية مش معروفة: %', k; end if;
    if jsonb_typeof(p_perms->k) <> 'boolean' then raise exception 'قيمة غير صحيحة لـ %', k; end if;
    if (p_perms->k)::boolean or k = 'use_cafe' then v := v || jsonb_build_object(k, (p_perms->k)::boolean); end if;   -- use_cafe بيتخزّن true/false صراحة (غيابه = يتبع الكاشير)
  end loop;
  old := perm_defaults(p_role::user_role);
  insert into role_perms(role, perms, updated_at, updated_by) values (p_role::user_role, v, now(), auth.uid())
    on conflict (role) do update set perms = excluded.perms, updated_at = now(), updated_by = auth.uid();
  insert into settings_history(key, old_value, new_value, reason, changed_by) values ('role_perms:' || p_role, old, v, 'تعديل صلاحيات الدور من مركز التحكم', auth.uid());
  return v;
end $$;
revoke all on function public.set_role_perms(text, jsonb) from public, anon;
grant execute on function public.set_role_perms(text, jsonb) to authenticated;

-- بيشيل من الموظفين الاستثناءات اللي بتساوي افتراضي الدور (القيمة الفعلية واحدة). ما بيلمسش use_cafe / cafe_only / mg_*.
create or replace function public.clean_perm_overrides() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare p record; d jsonb; k text; np jsonb; n int := 0; keys int := 0; removed int;
begin
  if not is_owner() then raise exception 'للمالك فقط'; end if;
  for p in select id, role, perms from profiles where role in ('cashier','barber','assistant') and perms is not null and perms <> '{}'::jsonb loop
    d := perm_defaults(p.role); np := p.perms; removed := 0;
    for k in select jsonb_object_keys(p.perms) loop
      continue when k in ('use_cafe','cafe_only') or k like 'mg\_%';
      continue when jsonb_typeof(p.perms->k) <> 'boolean';
      if (p.perms->k)::boolean = coalesce((d->>k)::boolean, false) then np := np - k; removed := removed + 1; end if;
    end loop;
    if removed > 0 then
      update profiles set perms = np where id = p.id;
      n := n + 1; keys := keys + removed;
    end if;
  end loop;
  insert into settings_history(key, old_value, new_value, reason, changed_by)
    values ('clean_perm_overrides', null, jsonb_build_object('staff', n, 'keys', keys), 'شيل استثناءات مطابقة لافتراضي الدور', auth.uid());
  return jsonb_build_object('staff', n, 'keys', keys);
end $$;
revoke all on function public.clean_perm_overrides() from public, anon;
grant execute on function public.clean_perm_overrides() to authenticated;
