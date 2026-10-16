-- patch_referrals.sql — برنامج "ادعي صاحبك"
-- الصاحب بيدخل كود/رقم اللي رشّحه، ولما يدفع أول فاتورة الاتنين ياخدوا نقاط.
-- النقاط بتتظبط من الإعدادات: referral_points (الافتراضي 50 لكل طرف).
-- شغّل patch_overnight_and_nameonly.sql الأول. آمن للتشغيل أكتر من مرة.

alter table public.customers
  add column if not exists referral_code text,
  add column if not exists referred_by bigint references public.customers(id) on delete set null,
  add column if not exists referral_rewarded_at timestamptz;
create unique index if not exists customers_referral_code_uq on public.customers(referral_code) where referral_code is not null;

create or replace function public.p_ref_find(p_key text, p_self bigint default null)
returns bigint language plpgsql stable security definer set search_path to 'public' as $$
declare k text := btrim(coalesce(p_key,'')); d text := regexp_replace(k,'\D','','g'); v bigint;
begin
  if k = '' then return null; end if;
  if d ~ '^01[0-9]{9}$' then select id into v from customers where phone = d;
  else select id into v from customers where referral_code = upper(k); end if;
  if v is not null and v is not distinct from p_self then return null; end if;
  return v;
end $$;
revoke all on function public.p_ref_find(text,bigint) from public, anon, authenticated;

create or replace function public.p_ref_code(p_customer bigint)
returns text language plpgsql security definer set search_path to 'public' as $$
declare v text; i int := 0; chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  select referral_code into v from customers where id = p_customer;
  if v is not null then return v; end if;
  loop
    v := ''; for n in 1..6 loop v := v || substr(chars, 1 + floor(random()*length(chars))::int, 1); end loop;
    begin
      update customers set referral_code = v where id = p_customer and referral_code is null;
      select referral_code into v from customers where id = p_customer; return v;
    exception when unique_violation then i := i + 1; if i > 20 then raise; end if; end;
  end loop;
end $$;
revoke all on function public.p_ref_code(bigint) from public, anon, authenticated;

-- بيانات العميل لصفحة "ادعي صاحبك"
create or replace function public.my_referral()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare c customers; v_pts int := (setting('referral_points','50'::jsonb))::text::int;
begin
  select * into c from customers where user_id = auth.uid();
  if c.id is null then raise exception 'مفيش حساب عميل'; end if;
  return jsonb_build_object(
    'code', p_ref_code(c.id), 'points', v_pts,
    'invited', (select count(*) from customers x where x.referred_by = c.id),
    'rewarded', (select count(*) from customers x where x.referred_by = c.id and x.referral_rewarded_at is not null),
    'earned', coalesce((select sum(points) from loyalty_ledger l where l.customer_id = c.id and l.reason = 'referral'),0),
    'referrer', (select name from customers r where r.id = c.referred_by),
    'can_apply', c.referred_by is null and c.visits = 0 and not exists (select 1 from invoices i where i.customer_id = c.id));
end $$;

-- العميل الجديد بيدخل كود/رقم اللي رشّحه
create or replace function public.apply_referral(p_key text)
returns text language plpgsql security definer set search_path to 'public' as $$
declare c customers; v_r bigint; v_n text;
begin
  select * into c from customers where user_id = auth.uid() for update;
  if c.id is null then raise exception 'مفيش حساب عميل'; end if;
  if c.referred_by is not null then raise exception 'انت مسجّل إنك جاي عن طريق حد قبل كده'; end if;
  if c.visits > 0 or exists (select 1 from invoices i where i.customer_id = c.id) then raise exception 'الدعوة متاحة للعملاء الجداد بس (قبل أول زيارة)'; end if;
  v_r := p_ref_find(p_key, c.id);
  if v_r is null then raise exception 'الكود أو الرقم ده مش صحيح'; end if;
  if exists (select 1 from customers r where r.id = v_r and r.referred_by = c.id) then raise exception 'مينفعش'; end if;
  update customers set referred_by = v_r where id = c.id;
  select name into v_n from customers where id = v_r;
  return v_n;
end $$;

-- الكاشير بيسجل "جاي عن طريق مين"
create or replace function public.staff_set_referrer(p_customer bigint, p_key text)
returns text language plpgsql security definer set search_path to 'public' as $$
declare c customers; v_r bigint; v_n text;
begin
  if not (is_mgr() or has_perm('use_pos')) then raise exception 'غير مصرح'; end if;
  select * into c from customers where id = p_customer for update;
  if c.id is null then raise exception 'العميل مش موجود'; end if;
  if c.referral_rewarded_at is not null then raise exception 'مكافأة الدعوة اتصرفت قبل كده'; end if;
  v_r := p_ref_find(p_key, c.id);
  if v_r is null then raise exception 'الكود أو الرقم ده مش صحيح'; end if;
  if exists (select 1 from customers r where r.id = v_r and r.referred_by = c.id) then raise exception 'مينفعش'; end if;
  update customers set referred_by = v_r where id = c.id;
  select name into v_n from customers where id = v_r;
  return v_n;
end $$;

-- مكافأة الاتنين عند أول فاتورة مدفوعة للعميل المدعو
create or replace function public.trg_referral_award()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare c customers; v_pts int := (setting('referral_points','50'::jsonb))::text::int;
begin
  begin
    if new.customer_id is null or coalesce(new.total,0) <= 0 or coalesce(old.total,0) > 0 or v_pts <= 0 then return new; end if;
    if not p11_cfg_bool('ff_loyalty', true) then return new; end if;
    select * into c from customers where id = new.customer_id for update;
    if c.referred_by is null or c.referral_rewarded_at is not null then return new; end if;
    if not exists (select 1 from customers where id = c.referred_by) then return new; end if;
    update customers set referral_rewarded_at = now() where id = c.id;
    perform add_points(c.id, v_pts, 'referral', new.id, 'هدية دعوة');
    perform add_points(c.referred_by, v_pts, 'referral', new.id, 'مكافأة دعوة ' || c.name);
  exception when others then
    raise warning 'referral award: %', sqlerrm;
  end;
  return new;
end $$;
drop trigger if exists referral_award on public.invoices;
create trigger referral_award after update of total on public.invoices
  for each row execute function public.trg_referral_award();

-- الدمج (ربط الرقم) لازم ينقل الدعوات كمان
create or replace function public.attach_customer_phone(p_customer bigint, p_phone text)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare v_ph text := regexp_replace(coalesce(p_phone,''), '\D', '', 'g'); s customers; t customers;
begin
  if not (is_mgr() or has_perm('use_pos')) then raise exception 'غير مصرح'; end if;
  if v_ph !~ '^01[0-9]{9}$' then raise exception 'رقم الموبايل غير صحيح (11 رقم ويبدأ بـ 01)'; end if;
  select * into s from customers where id = p_customer for update;
  if s.id is null then raise exception 'العميل مش موجود'; end if;
  if coalesce(s.phone,'') <> '' then raise exception 'العميل ده عنده رقم بالفعل'; end if;
  select * into t from customers where phone = v_ph for update;
  if t.id is null then
    update customers set phone = v_ph where id = s.id;
    return s.id;
  end if;
  if s.user_id is not null and t.user_id is not null then raise exception 'الاتنين عندهم حسابات مختلفة - مينفعش دمج'; end if;
  update appointments set customer_id = t.id where customer_id = s.id;
  update invoices set customer_id = t.id where customer_id = s.id;
  update reviews set customer_id = t.id where customer_id = s.id;
  update loyalty_redemptions set customer_id = t.id where customer_id = s.id;
  update open_invoices set customer_id = t.id where customer_id = s.id;
  update loyalty_ledger set customer_id = t.id where customer_id = s.id;
  update customer_notifications set customer_id = t.id where customer_id = s.id;
  delete from claim_requests where customer_id = s.id;
  update customers set referred_by = t.id where referred_by = s.id and t.id <> id;
  update customers set referred_by = null where id = t.id and referred_by = s.id;
  update customers set points = points + s.points, lifetime_points = lifetime_points + s.lifetime_points,
         visits = visits + s.visits, user_id = coalesce(user_id, s.user_id),
         referred_by = coalesce(referred_by, s.referred_by),
         referral_rewarded_at = coalesce(referral_rewarded_at, s.referral_rewarded_at) where id = t.id;
  delete from customers where id = s.id;
  return t.id;
end $$;

revoke all on function public.my_referral() from public, anon;
revoke all on function public.apply_referral(text) from public, anon;
revoke all on function public.staff_set_referrer(bigint,text) from public, anon;
grant execute on function public.my_referral() to authenticated;
grant execute on function public.apply_referral(text) to authenticated;
grant execute on function public.staff_set_referrer(bigint,text) to authenticated;
