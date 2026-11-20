-- حذف حساب العميل وبياناته (طلب من العميل، والتنفيذ بقرار المالك).
-- التنفيذ = إخفاء هوية: الاسم والموبايل والصورة وتاريخ الميلاد وربط الحساب، وحذف الصور المحفوظة والرسائل والإشعارات والتفضيلات والتذكيرات.
-- الفواتير وسجل الزيارات والحركات المالية بتفضل (التزام محاسبي) لكن من غير أي بيانات تعرّف صاحبها.
-- تنبيه: سجل التدقيق (audit_log) مقفول ضد التعديل بالتصميم، فنسخ قديمة من اسم العميل قد تفضل فيه. وحساب الدخول نفسه (auth) بيتشال من لوحة Supabase يدويًا.
-- آمن لو اتشغّل أكتر من مرة، ومبيغيّر أي بيانات قديمة.

create table if not exists public.account_deletion_requests (
  id bigint generated always as identity primary key,
  customer_id bigint not null references public.customers(id) on delete cascade,
  auth_user_id uuid,
  status text not null default 'pending' check (status in ('pending', 'done', 'rejected', 'cancelled')),
  requested_at timestamptz not null default now(),
  decided_by uuid,
  decided_at timestamptz,
  note text
);
create unique index if not exists adr_one_pending on public.account_deletion_requests(customer_id) where status = 'pending';
alter table public.account_deletion_requests enable row level security;
revoke all on public.account_deletion_requests from public, anon, authenticated;

create or replace function public.my_delete_request()
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare c customers; v_id bigint;
begin
  select * into c from customers where user_id = auth.uid() limit 1;
  if not found then raise exception 'غير مصرح'; end if;
  if exists (select 1 from appointments a where a.customer_id = c.id and a.status::text in ('upcoming', 'checked_in', 'in_service')) then
    raise exception 'عندك حجز شغّال، الغيه أو استنى لما يخلص قبل طلب الحذف';
  end if;
  insert into account_deletion_requests(customer_id, auth_user_id) values (c.id, c.user_id)
    on conflict (customer_id) where status = 'pending' do nothing returning id into v_id;
  if v_id is null then raise exception 'طلب الحذف اتبعت قبل كده وبيتراجع'; end if;
  begin perform push_send(push_staff_ids(array['owner'], null, null), 'طلب حذف حساب عميل', 'عميل طلب حذف حسابه وبياناته. راجعه من شاشة الموافقات.', 'apr', 'adr_' || v_id, false);
  exception when others then null; end;
  return v_id;
end $$;

create or replace function public.my_delete_status()
returns text language sql stable security definer set search_path = public, pg_temp as $$
  select r.status from account_deletion_requests r join customers c on c.id = r.customer_id
   where c.user_id = auth.uid() and r.status = 'pending' limit 1 $$;

create or replace function public.my_delete_cancel()
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update account_deletion_requests set status = 'cancelled', decided_at = now()
   where status = 'pending' and customer_id in (select id from customers where user_id = auth.uid());
end $$;

create or replace function public.deletion_requests_list()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not is_owner() then raise exception 'غير مصرح'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'customer_id', r.customer_id, 'name', c.name, 'phone', c.phone, 'visits', c.visits,
      'points', c.points, 'at', r.requested_at, 'auth_user_id', r.auth_user_id) order by r.requested_at)
    from account_deletion_requests r join customers c on c.id = r.customer_id where r.status = 'pending'), '[]'::jsonb);
end $$;

create or replace function public.deletion_execute(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare r account_deletion_requests; c customers;
begin
  if not is_owner() then raise exception 'القرار للمالك بس'; end if;
  select * into r from account_deletion_requests where id = p_id for update;
  if not found or r.status <> 'pending' then raise exception 'الطلب اتقفل أو مش موجود'; end if;
  select * into c from customers where id = r.customer_id for update;
  if exists (select 1 from appointments a where a.customer_id = c.id and a.status::text in ('upcoming', 'checked_in', 'in_service'))
     or exists (select 1 from open_invoices o where o.customer_id = c.id) then
    raise exception 'العميل عنده حجز أو فاتورة مفتوحة. استنى لما تخلص';
  end if;
  insert into deletion_log(table_name, row_id, row_data, extra)
    values ('customers_anonymized', c.id::text, jsonb_build_object('id', c.id, 'visits', c.visits, 'request', p_id), null);
  delete from customer_looks where customer_id = c.id;
  delete from customer_notifications where customer_id = c.id;
  delete from customer_feedback where customer_id = c.id;
  delete from fixed_reminders where customer_id = c.id;
  delete from customer_prefs where customer_id = c.id;
  delete from next_visit_reminders where customer_id = c.id;
  delete from winback_log where customer_id = c.id;
  delete from tryon_log where customer_id = c.id;
  update customers set name = 'عميل محذوف', phone = null, avatar = null, birthday = null, user_id = null, points = 0,
         company_id = null, guardian_id = null, referral_code = null where id = c.id;
  update account_deletion_requests set status = 'done', decided_by = auth.uid(), decided_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'auth_user_id', r.auth_user_id);
end $$;

create or replace function public.deletion_reject(p_id bigint, p_note text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not is_owner() then raise exception 'القرار للمالك بس'; end if;
  update account_deletion_requests set status = 'rejected', decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where id = p_id and status = 'pending';
  if not found then raise exception 'الطلب اتقفل أو مش موجود'; end if;
end $$;

do $$
declare f text;
begin
  foreach f in array array['my_delete_request()', 'my_delete_status()', 'my_delete_cancel()', 'deletion_requests_list()', 'deletion_execute(bigint)', 'deletion_reject(bigint,text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  if to_regprocedure('public.p20_audit()') is not null and not exists (select 1 from pg_trigger where tgname = 'zz_audit' and tgrelid = 'public.account_deletion_requests'::regclass) then
    create trigger zz_audit after insert or update or delete on public.account_deletion_requests for each row execute function public.p20_audit();
  end if;
end $$;
notify pgrst, 'reload schema';
