-- دمج عميلين (نفس الشخص برقمين) في حساب واحد + الرقم التاني يفضل شغّال كاسم تاني للحساب.
-- 1) customer_merge(الأساسي, المكرر): بينقل كل تاريخ المكرر (فواتير، حجوزات، نقاط، سجل نقاط، تقييمات، إشعارات...) للأساسي،
--    بيجمع النقاط والزيارات، وبيسجّل رقم المكرر كرقم تاني للأساسي. المكرر بيتأرشف كاملًا في أرشيف المحذوفات.
--    للمالك أو المدير بس. لو الاتنين عندهم حساب تطبيق (تسجيل دخول) مينفعش الدمج.
-- 2) customer_phones: الأرقام الإضافية. أي بحث/حجز/تسجيل بالرقم التاني بيوصل لنفس الحساب (الكاشير، الحجز، الدور، تسجيل العميل).
-- 3) customer_phone_add / customer_phone_remove: إضافة/شيل رقم تاني من غير دمج.
-- آمن لو اتشغّل أكتر من مرة، ومبيغيّرش أي بيانات قديمة لحد ما تستخدم الدمج.
-- لو احتجت تتراجع عن ربط الأرقام فقط: delete from customer_phones; (الدمج نفسه مبيترجعش — راجع أرشيف المحذوفات).

create table if not exists public.customer_phones (
  phone text primary key check (phone ~ '^01[0-9]{9}$'),
  customer_id bigint not null references public.customers(id) on delete cascade,
  note text,
  added_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists customer_phones_cust_idx on public.customer_phones(customer_id);
alter table public.customer_phones enable row level security;
drop policy if exists cph_read on public.customer_phones;
create policy cph_read on public.customer_phones for select to authenticated using (is_mgr() or can_use_pos());
revoke all on public.customer_phones from public, anon, authenticated;
grant select on public.customer_phones to authenticated;

create or replace function public.phone_alias_customer(p_phone text)
returns bigint language sql stable security definer set search_path = public, pg_temp as $$
  select customer_id from customer_phones where phone = p_phone
$$;
revoke all on function public.phone_alias_customer(text) from public, anon;
grant execute on function public.phone_alias_customer(text) to authenticated, service_role;

-- مفيش رقم يتسجل كعميل لو هو رقم تاني لحساب
create or replace function public.trg_customers_alias_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_n text;
begin
  if new.phone is not null and new.phone <> '' and exists (select 1 from customer_phones p where p.phone = new.phone and p.customer_id is distinct from new.id) then
    select c.name into v_n from customers c join customer_phones p on p.customer_id = c.id where p.phone = new.phone;
    raise exception 'الرقم ده رقم تاني للعميل %. استخدمه من حسابه', v_n;
  end if;
  return new;
end $$;
drop trigger if exists customers_alias_guard on public.customers;
create trigger customers_alias_guard before insert or update of phone on public.customers for each row execute function public.trg_customers_alias_guard();

create or replace function public.trg_cphones_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if exists (select 1 from customers c where c.phone = new.phone and c.id <> new.customer_id) then
    raise exception 'الرقم ده مسجل كعميل مستقل. ادمجه الأول';
  end if;
  return new;
end $$;
drop trigger if exists cphones_guard on public.customer_phones;
create trigger cphones_guard before insert or update on public.customer_phones for each row execute function public.trg_cphones_guard();

create or replace function public.customer_phone_add(p_customer bigint, p_phone text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_ph text := regexp_replace(translate(coalesce(p_phone, ''), '٠١٢٣٤٥٦٧٨٩', '0123456789'), '\D', '', 'g');
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  if v_ph !~ '^01[0-9]{9}$' then raise exception 'رقم الموبايل غير صحيح (11 رقم ويبدأ بـ 01)'; end if;
  if not exists (select 1 from customers where id = p_customer) then raise exception 'العميل مش موجود'; end if;
  if exists (select 1 from customers where phone = v_ph and id = p_customer) then raise exception 'ده الرقم الأساسي للعميل'; end if;
  if exists (select 1 from customer_phones where phone = v_ph) then raise exception 'الرقم ده مسجل كرقم تاني لعميل'; end if;
  insert into customer_phones(phone, customer_id) values (v_ph, p_customer);
end $$;

create or replace function public.customer_phone_remove(p_phone text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not is_mgr() then raise exception 'للمالك أو المدير بس'; end if;
  delete from customer_phones where phone = p_phone;
end $$;

-- الدمج
create or replace function public.customer_merge(p_keep bigint, p_drop bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare k customers; d customers; f record; v_n int; v_moved jsonb := '{}'::jsonb;
  v_fin text[] := array['invoices', 'appointments', 'loyalty_ledger', 'loyalty_redemptions', 'reviews', 'open_invoices', 'late_requests'];
begin
  if not is_mgr() then raise exception 'الدمج للمالك أو المدير بس'; end if;
  if p_keep is null or p_drop is null or p_keep = p_drop then raise exception 'اختار عميلين مختلفين'; end if;
  perform 1 from customers where id in (p_keep, p_drop) order by id for update;
  select * into k from customers where id = p_keep;
  select * into d from customers where id = p_drop;
  if k.id is null or d.id is null then raise exception 'العميل مش موجود'; end if;
  if k.user_id is not null and d.user_id is not null then raise exception 'الاتنين عندهم حساب تطبيق مختلف — مينفعش دمج'; end if;
  if exists (select 1 from customers where id = p_keep and guardian_id = p_drop) or exists (select 1 from customers where id = p_drop and guardian_id = p_keep) then
    raise exception 'العميلين مرتبطين كولي أمر وتابع — مينفعش دمج'; end if;
  if exists (select 1 from open_invoices where customer_id = p_drop) then raise exception 'المكرر عنده فاتورة مفتوحة. اقفلها الأول'; end if;

  -- أرشيف كامل للمكرر قبل أي تغيير
  insert into deletion_log(table_name, row_id, row_data, extra, deleted_by)
    values ('customers_merged', p_drop::text, to_jsonb(d), jsonb_build_object('merged_into', p_keep, 'keep_before', to_jsonb(k)), auth.uid());

  -- فك ربط حساب التطبيق من المكرر (الفريد على user_id) قبل ما ننقله
  if d.user_id is not null then update customers set user_id = null where id = p_drop; end if;

  -- نقل كل الجداول المرتبطة بالعميل (ديناميكي، يشمل أي جدول يتضاف بعدين)
  for f in
    select c.conrelid::regclass::text as tbl, a.attname::text as col, c.conrelid::regclass::oid as oid
      from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f' and c.confrelid = 'public.customers'::regclass and c.conrelid <> 'public.customers'::regclass
       and c.conrelid <> 'public.customer_phones'::regclass
  loop
    begin
      execute format('update %s set %I = $1 where %I = $2', f.tbl, f.col, f.col) using p_keep, p_drop;
      get diagnostics v_n = row_count;
    exception when unique_violation then
      if split_part(f.tbl, '.', 2) = any (v_fin) or f.tbl = any (v_fin) then raise; end if;
      -- جدول غير مالي فيه تعارض (إعدادات/تذكيرات مكررة): نسيب بيانات الأساسي ونشيل بتاعة المكرر
      execute format('delete from %s where %I = $1', f.tbl, f.col) using p_drop;
      get diagnostics v_n = row_count;
      v_n := -v_n;
    end;
    if v_n <> 0 then v_moved := v_moved || jsonb_build_object(f.tbl, v_n); end if;
  end loop;

  update customers set referred_by = p_keep where referred_by = p_drop and id <> p_keep;
  update customers set referred_by = null where id = p_keep and referred_by = p_drop;
  update customers set guardian_id = p_keep where guardian_id = p_drop and id <> p_keep;

  update customers set points = coalesce(points, 0) + coalesce(d.points, 0),
         lifetime_points = coalesce(lifetime_points, 0) + coalesce(d.lifetime_points, 0),
         visits = coalesce(visits, 0) + coalesce(d.visits, 0),
         user_id = coalesce(user_id, d.user_id),
         avatar = coalesce(avatar, d.avatar), birthday = coalesce(birthday, d.birthday),
         guardian_id = coalesce(guardian_id, d.guardian_id), company_id = coalesce(company_id, d.company_id),
         referred_by = coalesce(referred_by, d.referred_by), referral_rewarded_at = coalesce(referral_rewarded_at, d.referral_rewarded_at)
   where id = p_keep;

  delete from customers where id = p_drop;
  -- رقم المكرر بقى رقم تاني للأساسي (+ أي أرقام تانية كانت للمكرر)
  update customer_phones set customer_id = p_keep where customer_id = p_drop;
  if d.phone is not null and d.phone <> '' and d.phone is distinct from k.phone then
    insert into customer_phones(phone, customer_id, note) values (d.phone, p_keep, 'دمج عميل مكرر') on conflict (phone) do nothing;
  end if;
  return jsonb_build_object('ok', true, 'keep', p_keep, 'moved', v_moved, 'points_added', coalesce(d.points, 0), 'visits_added', coalesce(d.visits, 0), 'alias', d.phone);
end $$;
revoke all on function public.customer_merge(bigint, bigint) from public, anon;
grant execute on function public.customer_merge(bigint, bigint) to authenticated, service_role;
revoke all on function public.customer_phone_add(bigint, text) from public, anon;
grant execute on function public.customer_phone_add(bigint, text) to authenticated, service_role;
revoke all on function public.customer_phone_remove(text) from public, anon;
grant execute on function public.customer_phone_remove(text) to authenticated, service_role;

-- التدقيق على الجدول الجديد
do $$
begin
  if to_regprocedure('public.p20_audit()') is not null and not exists (select 1 from pg_trigger where tgname = 'zz_audit' and tgrelid = 'public.customer_phones'::regclass) then
    create trigger zz_audit after insert or update or delete on public.customer_phones for each row execute function public.p20_audit();
  end if;
end $$;

-- خلّي الدوال اللي بتدوّر على العميل بالرقم تشوف الرقم التاني كمان (تعديل نصي آمن: لو الشكل مختلف بيتخطّى من غير ما يكسر حاجة)
do $$
declare f text; v_def text; v_new text; v_cnt int;
begin
  foreach f in array array['add_customer', 'register_customer', 'p14_book_core', 'walk_in_ticket_v2']
  loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f limit 1;
    if v_def is null or v_def like '%phone_alias_customer%' then continue; end if;
    v_cnt := (length(v_def) - length(replace(v_def, 'c.phone = v_ph', ''))) / length('c.phone = v_ph');
    if v_cnt = 0 then raise notice 'تخطّي %: مفيش مكان بحث بالرقم', f; continue; end if;
    v_new := replace(v_def, 'c.phone = v_ph', '(c.phone = v_ph or c.id = public.phone_alias_customer(v_ph))');
    execute v_new;
    raise notice 'اتعدّلت % (% مكان)', f, v_cnt;
  end loop;
end $$;

notify pgrst, 'reload schema';
