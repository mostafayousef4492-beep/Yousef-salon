-- patch_store.sql — المتجر: العميل يحجز منتج من الصالون ويستلمه ويدفع عند الكاشير
-- مفيش دفع أونلاين ومفيش خصم من المخزون وقت الحجز: الحجز بيظهر للكاشير بس، والبيع الفعلي بيتم من نقطة البيع زي أي منتج
-- (فالمخزون والفلوس والتقارير ماتتلمسش). الحجز مايضمنش الكمية، بس بيتحدد بالمتاح وقت الحجز.
-- حدود: ٣ حجوزات معلّقة للعميل، وكمية الحجز لحد ٥. آمن للتشغيل أكتر من مرة.
create table if not exists public.product_reserves(
  id bigserial primary key,
  customer_id bigint not null references public.customers(id),
  product_id bigint not null references public.products(id),
  qty int not null check (qty between 1 and 5),
  status text not null default 'pending' check (status in ('pending','ready','picked','cancelled')),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid
);
create index if not exists product_reserves_cust on public.product_reserves(customer_id, id desc);
create index if not exists product_reserves_open on public.product_reserves(status) where status in ('pending','ready');
alter table public.product_reserves enable row level security;
-- مفيش policy: الوصول من الدوال بس

create or replace function public.store_list() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.uid() is null then raise exception 'غير مصرح'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'price', price, 'stock', stock) order by name)
    from products where active and not coalesce(archived,false) and stock > 0 and price > 0), '[]'::jsonb);
end $$;

create or replace function public.store_reserve(p_product bigint, p_qty int default 1, p_note text default null) returns bigint
language plpgsql security definer set search_path to 'public' as $$
declare c customers; p products; v_id bigint;
begin
  if auth.uid() is null then raise exception 'غير مصرح'; end if;
  select * into c from customers where user_id = auth.uid();
  if not found then raise exception 'سجّل دخولك الأول'; end if;
  perform pg_advisory_xact_lock(hashtext('pr' || c.id::text));
  select * into p from products where id = p_product and active and not coalesce(archived,false);
  if not found then raise exception 'المنتج مش متاح'; end if;
  if p_qty is null or p_qty < 1 or p_qty > 5 then raise exception 'الكمية من 1 لـ 5'; end if;
  if p.stock < p_qty then raise exception 'المتاح % بس', p.stock; end if;
  if (select count(*) from product_reserves where customer_id = c.id and status in ('pending','ready')) >= 3 then
    raise exception 'عندك 3 حجوزات مفتوحة. استلمهم أو الغي واحد الأول'; end if;
  insert into product_reserves(customer_id, product_id, qty, note) values (c.id, p.id, p_qty, nullif(left(btrim(coalesce(p_note,'')),120),'')) returning id into v_id;
  begin
    perform push_send(coalesce((select array_agg(pr.id) from profiles pr where pr.role in ('owner','manager','cashier')), '{}'::uuid[]), 'حجز منتج جديد', c.name || ' حجز ' || p.name || ' × ' || p_qty, null, 'store-' || v_id, false);
  exception when others then null; end;
  return v_id;
end $$;

create or replace function public.store_my() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare c customers;
begin
  select * into c from customers where user_id = auth.uid();
  if not found then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', p.name, 'price', p.price, 'qty', r.qty, 'status', r.status, 'at', r.created_at) order by r.id desc)
    from (select * from product_reserves where customer_id = c.id order by id desc limit 20) r join products p on p.id = r.product_id), '[]'::jsonb);
end $$;

create or replace function public.store_cancel(p_id bigint) returns void
language plpgsql security definer set search_path to 'public' as $$
declare c customers;
begin
  select * into c from customers where user_id = auth.uid();
  if not found then raise exception 'غير مصرح'; end if;
  update product_reserves set status = 'cancelled', updated_at = now() where id = p_id and customer_id = c.id and status in ('pending','ready');
  if not found then raise exception 'الحجز مش موجود أو اتقفل'; end if;
end $$;

-- الكاشير/المدير
create or replace function public.store_reserves_open() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
begin
  if not (coalesce(is_mgr(),false) or coalesce(can_use_pos(),false)) then raise exception 'غير مصرح'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'customer', c.name, 'phone', c.phone, 'product', p.name, 'price', p.price, 'stock', p.stock, 'qty', r.qty, 'status', r.status, 'note', r.note, 'at', r.created_at) order by r.id)
    from product_reserves r join customers c on c.id = r.customer_id join products p on p.id = r.product_id where r.status in ('pending','ready')), '[]'::jsonb);
end $$;

create or replace function public.store_reserve_set(p_id bigint, p_status text) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if not (coalesce(is_mgr(),false) or coalesce(can_use_pos(),false)) then raise exception 'غير مصرح'; end if;
  if p_status not in ('ready','picked','cancelled') then raise exception 'حالة غير صحيحة'; end if;
  update product_reserves set status = p_status, updated_at = now(), updated_by = auth.uid() where id = p_id and status in ('pending','ready');
  if not found then raise exception 'الحجز مش موجود أو اتقفل'; end if;
end $$;

do $$ declare f text; begin
  foreach f in array array['store_list()','store_reserve(bigint,int,text)','store_my()','store_cancel(bigint)','store_reserves_open()','store_reserve_set(bigint,text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
-- تراجع: drop function store_list(), store_reserve(bigint,int,text), store_my(), store_cancel(bigint), store_reserves_open(), store_reserve_set(bigint,text); drop table product_reserves;
