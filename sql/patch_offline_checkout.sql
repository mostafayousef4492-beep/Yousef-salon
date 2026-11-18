-- Offline cashier sales: idempotent server-side replay for the local device queue.
-- Apply only after reviewing on a staging database, then refresh the PostgREST schema cache.
create table if not exists public.offline_checkout_receipts (
  request_id uuid primary key,
  created_by uuid not null references auth.users(id) on delete cascade,
  response jsonb not null,
  sold_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.offline_checkout_receipts add column if not exists sold_at timestamptz;
alter table public.offline_checkout_receipts enable row level security;
revoke all on public.offline_checkout_receipts from public, anon, authenticated;

create or replace function public.pos_checkout_offline(
  p_request_id uuid,
  p_barber uuid,
  p_items jsonb,
  p_local_total numeric,
  p_sold_at timestamptz default null
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_response jsonb;
  v_total numeric;
begin
  if v_user is null or not can_use_pos() then raise exception 'غير مصرح'; end if;
  if p_request_id is null or p_local_total is null or p_local_total <= 0 then raise exception 'بيانات الفاتورة غير مكتملة'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'الفاتورة لازم تحتوي خدمة'; end if;
  if exists (select 1 from jsonb_array_elements(p_items) x where x->>'type' <> 'service' or coalesce((x->>'qty')::int,0) <> 1) then
    raise exception 'المزامنة الأوفلاين تدعم الخدمات فقط حاليًا';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_user::text || ':' || p_request_id::text, 0));
  select response into v_response from offline_checkout_receipts where request_id=p_request_id and created_by=v_user;
  if found then return v_response; end if;
  if exists (select 1 from offline_checkout_receipts where request_id=p_request_id) then raise exception 'معرّف الفاتورة مستخدم بحساب آخر'; end if;

  select coalesce(sum(s.price),0) into v_total
  from jsonb_array_elements(p_items) x
  join services s on s.id=(x->>'id')::bigint and s.active=true;
  if v_total <= 0 or round(v_total,2) <> round(p_local_total,2) then
    raise exception 'سعر الخدمة تغيّر أو لم تعد متاحة؛ راجع الفاتورة قبل المزامنة';
  end if;

  v_response := to_jsonb(pos_checkout(p_customer=>null,p_barber=>p_barber,p_items=>p_items,p_discount_pct=>0,p_discount_fixed=>0,p_method=>'cash'));
  insert into offline_checkout_receipts(request_id,created_by,response,sold_at) values(p_request_id,v_user,v_response,case when p_sold_at <= now() then p_sold_at end);
  return v_response;
end $$;
revoke all on function public.pos_checkout_offline(uuid,uuid,jsonb,numeric,timestamptz) from public, anon;
grant execute on function public.pos_checkout_offline(uuid,uuid,jsonb,numeric,timestamptz) to authenticated;
notify pgrst, 'reload schema';
