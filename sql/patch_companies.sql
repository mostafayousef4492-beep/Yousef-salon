-- خصومات الشركات (Corporate Discounts)
-- آمن للتشغيل أكتر من مرة. لا يغيّر بيانات قديمة. الخصم بيتحسب جوه pos_checkout بعد خصم الباقة.
-- لو حبيت ترجع: sql/rollback_companies.sql

-- 1) الجداول
create table if not exists companies (
  id bigserial primary key,
  name text not null unique,
  code text not null unique,
  discount_pct numeric(5,2) not null check (discount_pct > 0 and discount_pct <= 100),
  max_per_invoice numeric check (max_per_invoice is null or max_per_invoice > 0),
  starts_on date not null default ((now() at time zone 'Africa/Cairo')::date),
  ends_on date,
  active boolean not null default true,
  on_bundles boolean not null default true,
  monthly_limit int check (monthly_limit is null or monthly_limit > 0),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid
);
create table if not exists company_excluded_services (
  company_id bigint not null references companies(id) on delete cascade,
  service_id bigint not null references services(id) on delete cascade,
  primary key (company_id, service_id)
);
alter table customers add column if not exists company_id bigint references companies(id) on delete set null;
alter table customers add column if not exists company_linked_at timestamptz;
alter table customers add column if not exists company_linked_by uuid;
alter table invoices add column if not exists company_id bigint references companies(id) on delete set null;
alter table invoices add column if not exists company_discount numeric not null default 0;
alter table invoices add column if not exists company_approved_by uuid;
create index if not exists invoices_company_idx on invoices(company_id) where company_id is not null;
create index if not exists customers_company_idx on customers(company_id) where company_id is not null;

alter table companies enable row level security;
alter table company_excluded_services enable row level security;
drop policy if exists companies_mgr_read on companies;
create policy companies_mgr_read on companies for select using (is_mgr());
drop policy if exists company_excl_mgr_read on company_excluded_services;
create policy company_excl_mgr_read on company_excluded_services for select using (is_mgr());

-- 2) دوال الإدارة والكاشير
create or replace function company_save(p_id bigint, p_name text, p_code text, p_pct numeric, p_max numeric,
  p_start date, p_end date, p_active boolean, p_bundles boolean, p_limit int, p_notes text, p_excluded bigint[])
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_code text := upper(regexp_replace(coalesce(p_code,''), '\s', '', 'g'));
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'اسم الشركة مطلوب'; end if;
  if p_pct is null or p_pct <= 0 or p_pct > 100 then raise exception 'نسبة الخصم غير صحيحة'; end if;
  if p_end is not null and p_start is not null and p_end < p_start then raise exception 'تاريخ النهاية قبل البداية'; end if;
  if v_code = '' then v_code := 'C' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 5)); end if;
  if p_id is null then
    insert into companies(name, code, discount_pct, max_per_invoice, starts_on, ends_on, active, on_bundles, monthly_limit, notes, created_by)
    values (trim(p_name), v_code, p_pct, p_max, coalesce(p_start, (now() at time zone 'Africa/Cairo')::date), p_end,
            coalesce(p_active, true), coalesce(p_bundles, true), p_limit, nullif(trim(coalesce(p_notes,'')),''), auth.uid())
    returning id into v_id;
  else
    update companies set name = trim(p_name), code = v_code, discount_pct = p_pct, max_per_invoice = p_max,
      starts_on = coalesce(p_start, starts_on), ends_on = p_end, active = coalesce(p_active, active),
      on_bundles = coalesce(p_bundles, on_bundles), monthly_limit = p_limit, notes = nullif(trim(coalesce(p_notes,'')),'')
     where id = p_id returning id into v_id;
    if v_id is null then raise exception 'الشركة غير موجودة'; end if;
  end if;
  delete from company_excluded_services where company_id = v_id;
  insert into company_excluded_services(company_id, service_id)
    select v_id, s from unnest(coalesce(p_excluded, '{}')) s where exists (select 1 from services where id = s)
    on conflict do nothing;
  return v_id;
end $$;

create or replace function company_list()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'name', c.name, 'code', case when is_mgr() then c.code else null end, 'pct', c.discount_pct,
      'max', c.max_per_invoice, 'start', c.starts_on, 'end', c.ends_on, 'active', c.active,
      'bundles', c.on_bundles, 'limit', c.monthly_limit, 'notes', c.notes,
      'valid', c.active and c.starts_on <= (now() at time zone 'Africa/Cairo')::date
               and (c.ends_on is null or c.ends_on >= (now() at time zone 'Africa/Cairo')::date),
      'excluded', coalesce((select jsonb_agg(e.service_id) from company_excluded_services e where e.company_id = c.id), '[]'::jsonb),
      'members', (select count(*) from customers u where u.company_id = c.id))
    order by c.active desc, c.name) from companies c), '[]'::jsonb);
end $$;

create or replace function company_by_code(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c companies;
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  select * into c from companies where code = upper(regexp_replace(coalesce(p_code,''), '\s', '', 'g'));
  if not found then return null; end if;
  return jsonb_build_object('id', c.id, 'name', c.name, 'pct', c.discount_pct);
end $$;

create or replace function company_link_customer(p_customer bigint, p_company bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  if p_company is not null and not exists (select 1 from companies where id = p_company and active) then raise exception 'الشركة مش متاحة'; end if;
  update customers set company_id = p_company, company_linked_at = case when p_company is null then null else now() end,
         company_linked_by = case when p_company is null then null else auth.uid() end
   where id = p_customer;
  if not found then raise exception 'العميل غير موجود'; end if;
end $$;

-- 3) دوال العميل (من تطبيق العميل)
create or replace function company_join(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c companies; v_cu bigint;
begin
  if auth.uid() is null then raise exception 'سجّل دخول الأول'; end if;
  select id into v_cu from customers where user_id = auth.uid() limit 1;
  if v_cu is null then raise exception 'حساب العميل غير موجود'; end if;
  select * into c from companies where code = upper(regexp_replace(coalesce(p_code,''), '\s', '', 'g'));
  if not found or not c.active or c.starts_on > (now() at time zone 'Africa/Cairo')::date
     or (c.ends_on is not null and c.ends_on < (now() at time zone 'Africa/Cairo')::date) then
    raise exception 'الكود غير صحيح أو الاتفاق منتهي';
  end if;
  update customers set company_id = c.id, company_linked_at = now(), company_linked_by = null where id = v_cu;
  return jsonb_build_object('id', c.id, 'name', c.name, 'pct', c.discount_pct);
end $$;

create or replace function my_company()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c companies;
begin
  if auth.uid() is null then return null; end if;
  select co.* into c from customers cu join companies co on co.id = cu.company_id where cu.user_id = auth.uid() limit 1;
  if not found then return null; end if;
  return jsonb_build_object('id', c.id, 'name', c.name, 'pct', c.discount_pct, 'bundles', c.on_bundles, 'max', c.max_per_invoice,
    'valid', c.active and c.starts_on <= (now() at time zone 'Africa/Cairo')::date
             and (c.ends_on is null or c.ends_on >= (now() at time zone 'Africa/Cairo')::date),
    'end', c.ends_on,
    'excluded', coalesce((select jsonb_agg(e.service_id) from company_excluded_services e where e.company_id = c.id), '[]'::jsonb));
end $$;

create or replace function company_leave()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'سجّل دخول الأول'; end if;
  update customers set company_id = null, company_linked_at = null, company_linked_by = null where user_id = auth.uid();
end $$;

-- 4) تقرير الشركات
create or replace function company_report(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_f timestamptz := (coalesce(p_from, date '2000-01-01')::timestamp at time zone 'Africa/Cairo');
        v_t timestamptz := ((coalesce(p_to, date '2100-01-01') + 1)::timestamp at time zone 'Africa/Cairo');
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  return coalesce((select jsonb_agg(x order by (x->>'discounts')::numeric desc) from (
    select jsonb_build_object(
      'id', c.id, 'name', c.name, 'pct', c.discount_pct, 'active', c.active,
      'members', (select count(*) from customers u where u.company_id = c.id),
      'beneficiaries', (select count(distinct i.customer_id) from invoices i where i.company_id = c.id and i.created_at >= v_f and i.created_at < v_t),
      'uses', (select count(*) from invoices i where i.company_id = c.id and i.created_at >= v_f and i.created_at < v_t),
      'gross', coalesce((select sum(i.subtotal) from invoices i where i.company_id = c.id and i.created_at >= v_f and i.created_at < v_t), 0),
      'discounts', coalesce((select sum(i.company_discount) from invoices i where i.company_id = c.id and i.created_at >= v_f and i.created_at < v_t), 0),
      'net', coalesce((select sum(i.total) from invoices i where i.company_id = c.id and i.created_at >= v_f and i.created_at < v_t), 0),
      'top', coalesce((select jsonb_agg(jsonb_build_object('name', t.name, 'qty', t.q) order by t.q desc) from (
          select ii.name, sum(ii.qty) q from invoice_items ii join invoices i on i.id = ii.invoice_id
           where i.company_id = c.id and i.created_at >= v_f and i.created_at < v_t and ii.item_type = 'service'
           group by ii.name order by sum(ii.qty) desc limit 5) t), '[]'::jsonb)
    ) x from companies c) q), '[]'::jsonb);
end $$;

-- 5) pos_checkout_b: بارامتر اختياري للشركة (بيتبعت لـ pos_checkout عن طريق إعداد الجلسة زي الباقة)
drop function if exists pos_checkout_b(bigint, jsonb, bigint, uuid, jsonb, numeric, numeric, text, bigint, bigint, bigint, boolean);
create or replace function pos_checkout_b(p_bundle bigint, p_cafe jsonb, p_customer bigint, p_barber uuid, p_items jsonb,
  p_discount_pct numeric, p_discount_fixed numeric, p_method text, p_appointment bigint default null, p_redemption bigint default null,
  p_request bigint default null, p_outside boolean default false, p_company bigint default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare r bigint;
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  if p_bundle is not null and not exists (select 1 from bundles where id = p_bundle and active) then raise exception 'الباقة مش متاحة'; end if;
  perform set_config('app.pos_bundle', coalesce(p_bundle::text, ''), true);
  perform set_config('app.pos_outside', case when coalesce(p_outside, false) then '1' else '' end, true);
  perform set_config('app.pos_company', coalesce(p_company::text, ''), true);
  if p_cafe is not null and jsonb_typeof(p_cafe) = 'array' and jsonb_array_length(p_cafe) > 0 then
    r := pos_checkout_cafe(p_customer, p_barber, p_items, p_discount_pct, p_discount_fixed, p_method, p_appointment, p_redemption, p_request, p_cafe);
  else
    r := pos_checkout(p_customer, p_barber, p_items, p_discount_pct, p_discount_fixed, p_method, p_appointment, p_redemption, p_request);
  end if;
  perform set_config('app.pos_bundle', '', true);
  perform set_config('app.pos_outside', '', true);
  perform set_config('app.pos_company', '', true);
  return r;
end $$;

-- 6) تعديل pos_checkout (استبدال نصوص محددة مع التحقق؛ لو أي نص مش موجود بيفشل من غير ما يغيّر حاجة)
do $$
declare d text; n int;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'pos_checkout';
  if d like '%v_cd numeric%' then raise notice 'pos_checkout متعدّل بالفعل'; return; end if;

  d := replace(d, 'v_bd numeric := 0; v_bid bigint;',
    'v_bd numeric := 0; v_bid bigint; v_cd numeric := 0; v_cmp companies; v_cid bigint; v_elig numeric;');
  assert d like '%v_cd numeric := 0%', 'anchor 1 مش موجود';

  d := replace(d, E'  -- قواعد الخصم (بعد معرفة الإجمالي)',
$blk$  -- خصم الشركة (اتفاق معتمد: من غير موافقة مدير، بحد أقصى = نسبة الاتفاق، ويتجمّع مع خصم الباقة)
  v_cid := nullif(current_setting('app.pos_company', true), '')::bigint;
  if v_cid is not null then
    select * into v_cmp from companies where id = v_cid;
    if not found or not v_cmp.active then raise exception 'الشركة دي مش متاحة'; end if;
    if v_cmp.starts_on > (now() at time zone 'Africa/Cairo')::date or (v_cmp.ends_on is not null and v_cmp.ends_on < (now() at time zone 'Africa/Cairo')::date) then
      raise exception 'اتفاق الشركة منتهي أو لسه مبدأش'; end if;
    if v_pct > 0 or v_fx > 0 then raise exception 'خصم الشركة مش بيتجمّع مع خصم يدوي'; end if;
    if v_bd > 0 and not v_cmp.on_bundles then raise exception 'خصم الشركة مش متاح على الباقات'; end if;
    if p_redemption is not null and not p11_cfg_bool('disc_stack_coupon',true) then raise exception 'مينفعش خصم شركة مع كوبون ولاء'; end if;
    if v_cmp.monthly_limit is not null then
      if p_customer is null then raise exception 'لازم تختار العميل عشان حد الاستفادة الشهري'; end if;
      if (select count(*) from invoices x where x.company_id = v_cid and x.customer_id = p_customer
            and x.created_at >= (date_trunc('month', now() at time zone 'Africa/Cairo') at time zone 'Africa/Cairo')) >= v_cmp.monthly_limit then
        raise exception 'العميل وصل للحد الشهري للاستفادة من خصم الشركة'; end if;
    end if;
    select coalesce(sum(ii.unit_price * ii.qty), 0) into v_elig from invoice_items ii
     where ii.invoice_id = v_inv and ii.item_type = 'service' and ii.item_id <> 0
       and ii.item_id not in (select e.service_id from company_excluded_services e where e.company_id = v_cid);
    v_cd := round(greatest(v_elig - v_bd, 0) * v_cmp.discount_pct / 100, 2);
    if v_cmp.max_per_invoice is not null then v_cd := least(v_cd, v_cmp.max_per_invoice); end if;
    if v_cd <= 0 then raise exception 'مفيش في الفاتورة حاجة يطبّق عليها خصم الشركة'; end if;
  end if;
  -- قواعد الخصم (بعد معرفة الإجمالي)$blk$);
  assert d like '%v_cid := nullif(current_setting(''app.pos_company''%', 'anchor 2 مش موجود';

  d := replace(d, 'v_disc := least(v_sub, v_disc + v_rdisc + v_bd);', 'v_disc := least(v_sub, v_disc + v_rdisc + v_bd + v_cd);');
  assert d like '%v_rdisc + v_bd + v_cd)%', 'anchor 3 مش موجود';

  d := replace(d, 'update invoices set subtotal = v_sub, discount = v_disc, total = v_total where id = v_inv;',
    'update invoices set subtotal = v_sub, discount = v_disc, total = v_total, company_id = case when v_cd > 0 then v_cid end, company_discount = v_cd, company_approved_by = case when v_cd > 0 then auth.uid() end where id = v_inv;');
  assert d like '%company_discount = v_cd%', 'anchor 4 مش موجود';

  execute d;
end $$;

-- 7) الصلاحيات
do $$
declare f text;
begin
  foreach f in array array[
    'company_save(bigint,text,text,numeric,numeric,date,date,boolean,boolean,integer,text,bigint[])',
    'company_list()', 'company_by_code(text)', 'company_link_customer(bigint,bigint)', 'company_join(text)',
    'my_company()', 'company_leave()', 'company_report(date,date)',
    'pos_checkout_b(bigint,jsonb,bigint,uuid,jsonb,numeric,numeric,text,bigint,bigint,bigint,boolean,bigint)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;
