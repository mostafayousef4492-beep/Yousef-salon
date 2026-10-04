-- صالون أبو يوسف | patch_owner_control: مركز تحكم المالك + خصومات بحدود وموافقات + سجل تغييرات
-- شغّله بعد patch9 وpatch11 وpatch_open_invoices. إضافة فقط (جداول ودوال جدد) + قفل checkout_invoice عشان الكاشير يعدّي من pos_checkout.
-- مهم: انشر ملفات التطبيق الجديدة (app.js) مع تشغيل الباتش ده، لأن checkout_invoice بيتقفل عن التطبيق مباشرة.
do $$ begin
  if not exists (select 1 from pg_proc where proname='is_owner') or not exists (select 1 from pg_proc where proname='can_use_pos')
     or not exists (select 1 from pg_proc where proname='checkout_invoice') then
    raise exception 'patch_owner_control توقف: لازم patch9 وpatch_open_invoices يتشغلوا الأول';
  end if;
end $$;

-- ===== تعريف القواعد (الواجهة بتتبني منه، والسيرفر بيتحقق منه) =====
create table if not exists rule_defs (
  key text primary key, grp text not null, label text not null, hint text,
  kind text not null check (kind in ('int','num','bool','list')),
  min numeric, max numeric, def jsonb not null, danger boolean not null default false, kw text default '', sort int default 0);
alter table rule_defs enable row level security;
drop policy if exists "owner read" on rule_defs;
create policy "owner read" on rule_defs for select to authenticated using (is_owner());
revoke insert, update, delete on rule_defs from anon, authenticated;

insert into rule_defs(key,grp,label,hint,kind,min,max,def,danger,kw,sort) values
 ('disc_global_max_pct','الخصومات','أقصى خصم مسموح في النظام (%)','مفيش حد يعدّيه حتى المالك','num',0,100,'20',true,'خصم discount حد أقصى',10),
 ('disc_manager_max_pct','الخصومات','أقصى خصم للي معاه صلاحية الموافقة (%)','الكاشير اللي اتديله "يوافق على الخصومات"','num',0,100,'30',false,'خصم مدير manager موافقة approval',20),
 ('disc_cashier_max_pct','الخصومات','أقصى خصم للكاشير من غير موافقة (%)','فوق الرقم ده لازم موافقة','num',0,100,'10',false,'خصم كاشير cashier موافقة approval',30),
 ('disc_options','الخصومات','أزرار الخصم الظاهرة في الكاشير','أرقام بفاصلة، مثال: 0,5,10,20','list',null,null,'"0,5,10,20"',false,'خصم نسب أزرار discount',40),
 ('pay_card_enabled','المدفوعات','الدفع بالكارت','لو اتقفل مش هيتقبل في الكاشير ولا السيرفر','bool',null,null,'true',false,'دفع كارت card payment',50),
 ('pay_wallet_enabled','المدفوعات','الدفع بالمحفظة','لو اتقفل مش هيتقبل في الكاشير ولا السيرفر','bool',null,null,'true',false,'دفع محفظة wallet payment',60),
 ('chairs','الكاشير','عدد الكراسي (الفواتير المفتوحة)','من 1 لـ 12','int',1,12,'4',false,'كراسي chairs cashier فواتير مفتوحة',70),
 ('booking_open','الحجز','الحجز الأونلاين شغال','لو اتقفل العملاء مش هيقدروا يحجزوا','bool',null,null,'true',true,'حجز booking online',80),
 ('cancel_before_hours','الحجز','أقل مدة قبل الموعد للإلغاء (ساعات)','','int',0,72,'2',false,'إلغاء cancel حجز',90),
 ('points_per_currency','الولاء','كل كام جنيه = نقطة','','num',1,10000,'10',true,'ولاء نقاط loyalty points commission',100)
on conflict (key) do update set grp=excluded.grp,label=excluded.label,hint=excluded.hint,kind=excluded.kind,min=excluded.min,max=excluded.max,def=excluded.def,danger=excluded.danger,kw=excluded.kw,sort=excluded.sort;

-- قيم افتراضية للجديد بس (القديم زي max_discount_pct بيتورّث)
insert into app_settings(key,value) select d.key, case when d.key='disc_global_max_pct' then coalesce((select value from app_settings where key='max_discount_pct'), d.def) else d.def end from rule_defs d where d.key in ('disc_global_max_pct','disc_manager_max_pct','disc_cashier_max_pct','disc_options','pay_card_enabled','pay_wallet_enabled')
  and not exists (select 1 from app_settings a where a.key=d.key);

-- ===== سجل التغييرات (تلقائي من السيرفر، حتى لو التعديل من شاشة الإعدادات القديمة) =====
create table if not exists settings_history (
  id bigint generated always as identity primary key, key text not null, old_value jsonb, new_value jsonb,
  reason text, changed_by uuid default auth.uid(), changed_at timestamptz not null default now());
alter table settings_history enable row level security;
drop policy if exists "owner read" on settings_history;
create policy "owner read" on settings_history for select to authenticated using (is_owner());
revoke insert, update, delete, truncate on settings_history from anon, authenticated;

create or replace function trg_settings_log() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' or new.value is distinct from old.value then
    insert into settings_history(key,old_value,new_value,reason)
    values (new.key, case when tg_op='UPDATE' then old.value end, new.value, nullif(current_setting('app.reason', true), ''));
  end if;
  return new;
end $$;
drop trigger if exists settings_log on app_settings;
create trigger settings_log after insert or update on app_settings for each row execute function trg_settings_log();

-- ===== تعديل قاعدة (مالك بس + تحقق من الحدود) =====
create or replace function owner_set_rule(p_key text, p_value jsonb, p_reason text default null) returns void
language plpgsql security definer set search_path=public as $$
declare d rule_defs; n numeric; g numeric; m numeric; c numeric;
begin
  if not is_owner() then raise exception 'غير مصرح'; end if;
  select * into d from rule_defs where key=p_key; if not found then raise exception 'قاعدة غير معروفة'; end if;
  if d.kind='bool' and jsonb_typeof(p_value)<>'boolean' then raise exception 'القيمة لازم تكون تشغيل/إيقاف'; end if;
  if d.kind in ('int','num') then
    if jsonb_typeof(p_value)<>'number' then raise exception 'القيمة لازم تكون رقم'; end if;
    n := (p_value #>> '{}')::numeric;
    if n < d.min or n > d.max then raise exception 'القيمة لازم بين % و%', d.min, d.max; end if;
    if d.kind='int' and n<>trunc(n) then raise exception 'لازم رقم صحيح'; end if;
  end if;
  if d.kind='list' and (jsonb_typeof(p_value)<>'string' or (p_value #>> '{}') !~ '^[0-9]{1,3}(,[0-9]{1,3})*$') then raise exception 'اكتب أرقام بفاصلة مثل 0,5,10'; end if;
  if p_key in ('disc_global_max_pct','disc_manager_max_pct','disc_cashier_max_pct') then
    g := case when p_key='disc_global_max_pct' then n else p11_cfg_num('disc_global_max_pct',20) end;
    m := case when p_key='disc_manager_max_pct' then n else p11_cfg_num('disc_manager_max_pct',30) end;
    c := case when p_key='disc_cashier_max_pct' then n else p11_cfg_num('disc_cashier_max_pct',10) end;
    if not (c <= m and m <= g) then raise exception 'الترتيب لازم: كاشير ≤ موافقة ≤ أقصى حد في النظام (% ≤ % ≤ %)', c, m, g; end if;
  end if;
  perform set_config('app.reason', coalesce(p_reason,''), true);
  insert into app_settings(key,value) values (p_key,p_value) on conflict (key) do update set value=excluded.value;
end $$;
grant execute on function owner_set_rule(text,jsonb,text) to authenticated;

-- ===== الخصومات: حدود + طلبات موافقة =====
create or replace function can_approve_disc() returns boolean language sql stable security definer set search_path=public as $$
  select is_owner() or exists (select 1 from profiles p where p.id=auth.uid() and coalesce((p.perms->>'approve_discount')::boolean,false)); $$;
create or replace function my_disc_limit() returns numeric language sql stable security definer set search_path=public as $$
  select least(p11_cfg_num('disc_global_max_pct',20),
    case when is_owner() then 100 when can_approve_disc() then p11_cfg_num('disc_manager_max_pct',30) else p11_cfg_num('disc_cashier_max_pct',10) end); $$;
grant execute on function can_approve_disc(), my_disc_limit() to authenticated;

create table if not exists discount_requests (
  id bigint generated always as identity primary key, chair int, pct numeric not null check (pct>0 and pct<=100),
  subtotal numeric, reason text, status text not null default 'pending' check (status in ('pending','approved','rejected','used')),
  requested_by uuid not null default auth.uid() references profiles(id) on delete cascade,
  decided_by uuid, created_at timestamptz not null default now(), decided_at timestamptz);
alter table discount_requests enable row level security;
drop policy if exists "pos read" on discount_requests;
create policy "pos read" on discount_requests for select to authenticated using (can_use_pos() or is_owner());
revoke insert, update, delete, truncate on discount_requests from anon, authenticated;
grant select on discount_requests to authenticated;

create or replace function request_discount(p_chair int, p_pct numeric, p_subtotal numeric, p_reason text) returns bigint
language plpgsql security definer set search_path=public as $$
declare v bigint;
begin
  if not can_use_pos() then raise exception 'غير مصرح'; end if;
  if p_pct <= 0 or p_pct > p11_cfg_num('disc_global_max_pct',20) then raise exception 'الخصم ده فوق الحد الأقصى في النظام'; end if;
  insert into discount_requests(chair,pct,subtotal,reason) values (p_chair,p_pct,p_subtotal,left(coalesce(p_reason,''),200)) returning id into v;
  return v;
end $$;
create or replace function decide_discount(p_id bigint, p_ok boolean) returns void
language plpgsql security definer set search_path=public as $$
declare r discount_requests;
begin
  if not can_approve_disc() then raise exception 'مش معاك صلاحية الموافقة'; end if;
  select * into r from discount_requests where id=p_id for update;
  if not found or r.status<>'pending' then raise exception 'الطلب ده اتقفل أو مش موجود'; end if;
  if p_ok then
    if r.requested_by=auth.uid() and not is_owner() then raise exception 'مينفعش توافق على طلبك بنفسك'; end if;
    if r.pct > my_disc_limit() then raise exception 'الخصم ده فوق حدّك'; end if;
  end if;
  update discount_requests set status=case when p_ok then 'approved' else 'rejected' end, decided_by=auth.uid(), decided_at=now() where id=p_id;
end $$;
grant execute on function request_discount(int,numeric,numeric,text), decide_discount(bigint,boolean) to authenticated;

-- ===== الدفع/إغلاق الفاتورة: نفس checkout_invoice بس بعد فرض القواعد =====
create or replace function pos_checkout(p_customer bigint, p_barber uuid, p_items jsonb, p_discount_pct numeric, p_method text,
                                        p_appointment bigint default null, p_redemption bigint default null, p_request bigint default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_pct numeric := coalesce(p_discount_pct,0); r discount_requests; res jsonb;
begin
  if not can_use_pos() then raise exception 'غير مصرح'; end if;
  if v_pct < 0 or v_pct > 100 then raise exception 'نسبة خصم غير صحيحة'; end if;
  if p_method not in ('cash','card','wallet') then raise exception 'طريقة دفع غير مدعومة'; end if;
  if p_method='card' and not p11_cfg_bool('pay_card_enabled',true) then raise exception 'الدفع بالكارت متوقف'; end if;
  if p_method='wallet' and not p11_cfg_bool('pay_wallet_enabled',true) then raise exception 'الدفع بالمحفظة متوقف'; end if;
  if v_pct > p11_cfg_num('disc_global_max_pct',20) then raise exception 'الخصم فوق الحد الأقصى في النظام'; end if;
  if v_pct > my_disc_limit() then
    select * into r from discount_requests where id=p_request for update;
    if not found or r.status<>'approved' or r.requested_by<>auth.uid() or r.pct < v_pct or r.created_at < now()-interval '3 hours' then
      raise exception 'الخصم ده محتاج موافقة المدير';
    end if;
    update discount_requests set status='used' where id=r.id;
  end if;
  execute format('select to_jsonb(checkout_invoice(p_customer=>%L, p_barber=>%L, p_items=>%L, p_discount_pct=>%L, p_method=>%L, p_appointment=>%L, p_redemption=>%L))',
                 p_customer, p_barber, p_items, v_pct, p_method, p_appointment, p_redemption) into res;
  return res;
end $$;
grant execute on function pos_checkout(bigint,uuid,jsonb,numeric,text,bigint,bigint,bigint) to authenticated;

-- قفل الباب القديم: أي بيع لازم يعدّي من pos_checkout (لو احتجت تتراجع: grant execute on function checkout_invoice(...) to authenticated)
do $$ declare f record; begin
  for f in select oid::regprocedure as sig from pg_proc where proname='checkout_invoice' and pronamespace='public'::regnamespace loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
notify pgrst, 'reload schema';
