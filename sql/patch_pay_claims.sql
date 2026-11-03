-- الزبون يبلّغ من تطبيقه إنه حوّل فودافون كاش (يدوي): الرقم + المبلغ بيظهروا للكاشير عند فاتورة التذكرة،
-- والكاشير هو اللي يتأكد من موبايل المحل ويقفل الفاتورة (الطلب مش بيقفل فاتورة ولا بيدخّل فلوس لوحده).
-- يتطلب patch_tablet_barber.sql (ticket_bill). آمن للتشغيل أكتر من مرة.
create table if not exists public.pay_claims (
  id bigserial primary key,
  appointment_id bigint not null references public.appointments(id) on delete cascade,
  customer_id bigint,
  amount numeric not null,
  ref text not null,
  status text not null default 'pending' check (status in ('pending','rejected')),
  created_at timestamptz not null default now()
);
alter table public.pay_claims enable row level security;   -- مفيش سياسات: الوصول من الدوال بس
create unique index if not exists pay_claims_one_pending on public.pay_claims (appointment_id) where status = 'pending';
create unique index if not exists pay_claims_ref_pending on public.pay_claims (lower(btrim(ref))) where status = 'pending';

create or replace function public.submit_pay_claim(p_appt bigint, p_ref text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a appointments; r text := nullif(btrim(coalesce(p_ref,'')), ''); b jsonb; v_amt numeric;
begin
  if auth.uid() is null then raise exception 'سجّل دخول الأول'; end if;
  select * into a from appointments where id = p_appt;
  if not found or not exists (select 1 from customers c where c.id = a.customer_id and c.user_id = auth.uid()) then
    raise exception 'التذكرة مش بتاعتك'; end if;
  if a.status::text not in ('checked_in','in_service','done') then raise exception 'الدفع بعد بدء الخدمة'; end if;
  if exists (select 1 from invoices where appointment_id = p_appt) then raise exception 'التذكرة دي اتدفعت بالفعل'; end if;
  if r is null or char_length(r) < 4 or char_length(r) > 40 then raise exception 'اكتب رقم العملية من رسالة فودافون كاش (4 خانات على الأقل)'; end if;
  if exists (select 1 from invoices where pay_channel = 'vodafone_cash' and lower(btrim(pay_ref)) = lower(r)) then
    raise exception 'رقم العملية ده اتسجّل قبل كده'; end if;
  b := ticket_bill(p_appt); v_amt := coalesce((b->>'total')::numeric, 0);
  if v_amt <= 0 then raise exception 'مفيش مبلغ مطلوب على التذكرة'; end if;
  delete from pay_claims where appointment_id = p_appt and status = 'rejected';
  begin
    insert into pay_claims(appointment_id, customer_id, amount, ref) values (p_appt, a.customer_id, v_amt, r)
    on conflict (appointment_id) where status = 'pending' do update set ref = excluded.ref, amount = excluded.amount, created_at = now();
  exception when unique_violation then
    raise exception 'رقم العملية ده مبلّغ عنه قبل كده';
  end;
  return jsonb_build_object('status','pending','ref',r,'amount',v_amt);
end $$;

-- حالة طلب الزبون: none / pending / rejected / paid
create or replace function public.my_pay_claim(p_appt bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a appointments; c pay_claims;
begin
  select * into a from appointments where id = p_appt;
  if not found or not exists (select 1 from customers x where x.id = a.customer_id and x.user_id = auth.uid()) then return null; end if;
  if exists (select 1 from invoices where appointment_id = p_appt) then return jsonb_build_object('status','paid'); end if;
  select * into c from pay_claims where appointment_id = p_appt order by id desc limit 1;
  if not found then return jsonb_build_object('status','none'); end if;
  return jsonb_build_object('status', c.status, 'ref', c.ref, 'amount', c.amount);
end $$;

-- للكاشير/المدير: طلب الدفع المعلّق على التذكرة (بيختفي لما الفاتورة تتقفل)
create or replace function public.pay_claim_for(p_appt bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c pay_claims;
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  select * into c from pay_claims where appointment_id = p_appt and status = 'pending'
    and not exists (select 1 from invoices i where i.appointment_id = p_appt) limit 1;
  if not found then return null; end if;
  return jsonb_build_object('id', c.id, 'ref', c.ref, 'amount', c.amount, 'at', c.created_at);
end $$;

create or replace function public.reject_pay_claim(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  update pay_claims set status = 'rejected' where id = p_id and status = 'pending';
end $$;

revoke all on function public.submit_pay_claim(bigint, text), public.my_pay_claim(bigint), public.pay_claim_for(bigint), public.reject_pay_claim(bigint) from public, anon;
grant execute on function public.submit_pay_claim(bigint, text), public.my_pay_claim(bigint), public.pay_claim_for(bigint), public.reject_pay_claim(bigint) to authenticated;
