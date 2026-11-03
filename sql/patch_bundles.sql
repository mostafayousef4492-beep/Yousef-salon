-- الباقات: مجموعة خدمات بسعر أقل من مجموعها لوحدها.
-- الحجز بيفضل بالخدمات الفردية (المدة والطابور زي ما هما) + appointments.bundle_id، والخصم بيتحسب في pos_checkout على السيرفر.
-- آمن للتشغيل أكتر من مرة. التراجع: drop table bundle_items, bundles cascade; alter table appointments drop column bundle_id; (وإعادة تعريف pos_checkout من نسخة احتياطية).

create table if not exists public.bundles (
  id bigserial primary key,
  name text not null check (char_length(btrim(name)) >= 2),
  description text,
  price numeric(10,2) not null check (price >= 0),
  active boolean not null default true,
  sort int not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.bundle_items (
  bundle_id bigint not null references public.bundles(id) on delete cascade,
  service_id bigint not null references public.services(id) on delete restrict,
  primary key (bundle_id, service_id)
);
alter table public.appointments add column if not exists bundle_id bigint references public.bundles(id) on delete set null;

alter table public.bundles enable row level security;
alter table public.bundle_items enable row level security;
-- القراءة المباشرة للإدارة بس؛ الباقي بيقرأ من bundles_list(). الكتابة عن طريق الدوال بس.
revoke all on public.bundles, public.bundle_items from anon, authenticated;
grant select on public.bundles, public.bundle_items to authenticated;
grant usage, select on sequence public.bundles_id_seq to authenticated;
drop policy if exists bundles_mgr_read on public.bundles;
create policy bundles_mgr_read on public.bundles for select to authenticated using (is_mgr());
drop policy if exists bundle_items_mgr_read on public.bundle_items;
create policy bundle_items_mgr_read on public.bundle_items for select to authenticated using (is_mgr());

-- قائمة الباقات (للعميل: النشطة وكل خدماتها نشطة. للإدارة مع p_all: الكل)
create or replace function public.bundles_list(p_all boolean default false)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x.sort, x.id), '[]'::jsonb) from (
    select b.id, b.name, b.description, b.price, b.active, b.sort,
           s.full, greatest(s.full - b.price, 0) as saving, s.dur, s.items as services
      from bundles b
      cross join lateral (
        select coalesce(sum(sv.price), 0) as full, coalesce(sum(sv.duration_min), 0) as dur,
               jsonb_agg(jsonb_build_object('id', sv.id, 'name', sv.name, 'price', sv.price) order by sv.id) as items,
               bool_and(sv.active) as all_active
          from bundle_items bi join services sv on sv.id = bi.service_id where bi.bundle_id = b.id) s
     where (p_all and is_mgr()) or (b.active and s.all_active)
  ) x
$$;
revoke all on function public.bundles_list(boolean) from public;
grant execute on function public.bundles_list(boolean) to anon, authenticated;

-- حفظ باقة (إضافة/تعديل) — المدير/المالك
create or replace function public.admin_save_bundle(p_id bigint, p_name text, p_desc text, p_price numeric, p_active boolean, p_services bigint[])
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint := p_id; v_full numeric; v_n int; v_ids bigint[];
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  select array_agg(distinct x) into v_ids from unnest(coalesce(p_services, '{}')) x;
  v_n := coalesce(array_length(v_ids, 1), 0);
  if v_n < 2 then raise exception 'الباقة لازم فيها خدمتين على الأقل'; end if;
  if char_length(btrim(coalesce(p_name, ''))) < 2 then raise exception 'اكتب اسم الباقة'; end if;
  select sum(price), count(*) into v_full, v_n from services where id = any(v_ids) and active;
  if v_n <> array_length(v_ids, 1) then raise exception 'فيه خدمة مش موجودة أو موقوفة'; end if;
  if p_price is null or p_price < 0 then raise exception 'سعر غير صحيح'; end if;
  if p_price >= v_full then raise exception 'سعر الباقة لازم يبقى أقل من مجموع الخدمات (%)', v_full; end if;
  if v_id is null then
    insert into bundles(name, description, price, active) values (btrim(p_name), nullif(btrim(coalesce(p_desc, '')), ''), p_price, coalesce(p_active, true)) returning id into v_id;
  else
    update bundles set name = btrim(p_name), description = nullif(btrim(coalesce(p_desc, '')), ''), price = p_price, active = coalesce(p_active, true) where id = v_id;
    if not found then raise exception 'الباقة مش موجودة'; end if;
    delete from bundle_items where bundle_id = v_id;
  end if;
  insert into bundle_items(bundle_id, service_id) select v_id, unnest(v_ids);
  return v_id;
end $$;
revoke all on function public.admin_save_bundle(bigint, text, text, numeric, boolean, bigint[]) from public, anon;
grant execute on function public.admin_save_bundle(bigint, text, text, numeric, boolean, bigint[]) to authenticated;

create or replace function public.admin_delete_bundle(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  delete from bundles where id = p_id;
end $$;
revoke all on function public.admin_delete_bundle(bigint) from public, anon;
grant execute on function public.admin_delete_bundle(bigint) to authenticated;

-- ربط/فك باقة بتذكرة: العميل صاحب التذكرة (بحسابه أو برقم موبايله) أو الموظف. الخدمات لازم تحتوي كل خدمات الباقة.
create or replace function public.set_ticket_bundle(p_id bigint, p_bundle bigint, p_phone text default null)
returns void language plpgsql security definer set search_path = public as $$
declare a appointments; ok boolean; b bundles;
begin
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  ok := is_mgr() or has_perm('manage_appts') or can_use_pos()
     or exists (select 1 from customers c where c.id = a.customer_id and (c.user_id = auth.uid()
                or (p_phone is not null and c.phone = regexp_replace(p_phone, '\D', '', 'g'))));
  if not ok then raise exception 'غير مصرح'; end if;
  if a.status::text not in ('upcoming', 'checked_in') then raise exception 'مينفعش تغيّر الباقة دلوقتي'; end if;
  if p_bundle is null then update appointments set bundle_id = null where id = p_id; return; end if;
  select * into b from bundles where id = p_bundle and active;
  if not found then raise exception 'الباقة مش متاحة'; end if;
  if exists (select 1 from bundle_items bi where bi.bundle_id = p_bundle
              and not exists (select 1 from appointment_services s where s.appointment_id = p_id and s.service_id = bi.service_id)) then
    raise exception 'خدمات الحجز مش مطابقة للباقة'; end if;
  update appointments set bundle_id = p_bundle where id = p_id;
end $$;
revoke all on function public.set_ticket_bundle(bigint, bigint, text) from public;
grant execute on function public.set_ticket_bundle(bigint, bigint, text) to anon, authenticated;

-- ملخص الباقة لتذكرة (للعرض: الاسم، سعر الخدمات لوحدها، سعر الباقة، الخصم) — نفس صلاحيات set_ticket_bundle
create or replace function public.ticket_bundle(p_id bigint, p_phone text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a appointments; ok boolean; j jsonb;
begin
  select * into a from appointments where id = p_id;
  if not found or a.bundle_id is null then return null; end if;
  ok := is_mgr() or has_perm('manage_appts') or can_use_pos()
     or exists (select 1 from customers c where c.id = a.customer_id and (c.user_id = auth.uid()
                or (p_phone is not null and c.phone = regexp_replace(p_phone, '\D', '', 'g'))));
  if not ok then return null; end if;
  select jsonb_build_object('id', b.id, 'name', b.name, 'price', b.price, 'full', s.full, 'saving', greatest(s.full - b.price, 0), 'service_ids', s.ids)
    into j from bundles b cross join lateral (select coalesce(sum(sv.price), 0) as full, coalesce(jsonb_agg(sv.id order by sv.id), '[]'::jsonb) as ids from bundle_items bi join services sv on sv.id = bi.service_id where bi.bundle_id = b.id) s
   where b.id = a.bundle_id;
  return j;
end $$;
revoke all on function public.ticket_bundle(bigint, text) from public;
grant execute on function public.ticket_bundle(bigint, text) to anon, authenticated;

-- خصم الباقة في pos_checkout: لو التذكرة عليها باقة وكل خدماتها موجودة في الفاتورة، الخصم = (سعر خدماتها في الفاتورة) − سعر الباقة.
-- بيتحسب على السيرفر (مش بيتصدّق من الواجهة)، ومش بيتجمّع مع خصم يدوي (% أو مبلغ) ولا مع كوبون لو التجميع مقفول.
do $$
declare d text; n text;
begin
  select pg_get_functiondef('public.pos_checkout(bigint,uuid,jsonb,numeric,numeric,text,bigint,bigint,bigint)'::regprocedure) into d;
  if position('v_bd numeric' in d) > 0 then return; end if;   -- اتطبّق قبل كده
  n := d;
  if position('v_base numeric;' in n) = 0 then raise exception 'pos_checkout مختلفة عن المتوقع (المتغيرات)'; end if;
  n := replace(n, 'v_base numeric;', 'v_base numeric; v_bd numeric := 0;');
  if position('-- قواعد الخصم (بعد معرفة الإجمالي)' in n) = 0 then raise exception 'pos_checkout مختلفة عن المتوقع (قواعد الخصم)'; end if;
  n := replace(n, '-- قواعد الخصم (بعد معرفة الإجمالي)',
$b$-- خصم الباقة
  if p_appointment is not null then
    select greatest(sum(ii.unit_price) - bb.price, 0) into v_bd
      from appointments ap join bundles bb on bb.id = ap.bundle_id
      join bundle_items bi on bi.bundle_id = bb.id
      join invoice_items ii on ii.invoice_id = v_inv and ii.item_type = 'service' and ii.item_id = bi.service_id
     where ap.id = p_appointment
       and not exists (select 1 from bundle_items b2 where b2.bundle_id = bb.id and not exists (select 1 from invoice_items i2 where i2.invoice_id = v_inv and i2.item_type = 'service' and i2.item_id = b2.service_id))
     group by bb.price;
    v_bd := coalesce(v_bd, 0);
    if v_bd > 0 and (v_pct > 0 or v_fx > 0) then raise exception 'الباقة مش بتتجمّع مع خصم تاني'; end if;
    if v_bd > 0 and p_redemption is not null and not p11_cfg_bool('disc_stack_coupon',true) then raise exception 'مينفعش باقة مع كوبون ولاء'; end if;
  end if;
  -- قواعد الخصم (بعد معرفة الإجمالي)$b$);
  if position('v_disc := least(v_sub, v_disc + v_rdisc); v_total := v_sub - v_disc;' in n) = 0 then raise exception 'pos_checkout مختلفة عن المتوقع (الإجمالي)'; end if;
  n := replace(n, 'v_disc := least(v_sub, v_disc + v_rdisc); v_total := v_sub - v_disc;', 'v_disc := least(v_sub, v_disc + v_rdisc + v_bd); v_total := v_sub - v_disc;');
  execute n;
end $$;
