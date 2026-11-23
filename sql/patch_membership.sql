-- patch_membership.sql — ABO YOUSEF MEMBERSHIP (المرحلة ١): اشتراكات ورصيد العملاء
-- المرحلة دي مابتلمسش الفواتير ولا pos_checkout ولا العمولة. الدفع من الرصيد عند الكاشير = المرحلة ٢ (بعد موافقتك).
-- القواعد:
--   • الشحن: الرصيد الأساسي = السعر، والإضافي = الهدية. بيتسجّلوا منفصلين. الشحن الكاش بيتسجّل إيداع في الدرج (cash_moves) مش مبيعات.
--   • الأسبوع بيبدأ من يوم أول شحن (وبيتكرر كل ٧ أيام). الشحن الجديد جوه الاشتراك مابيعيدش العدّاد.
--   • الزيارة = يوم فيه فاتورة فيها خدمة (total > 0، مش فاتورة سداد). أكتر من فاتورة في نفس اليوم = زيارة واحدة.
--   • آخر الأسبوع: لو الزيارات أقل من المطلوب بيتخصم % من الرصيد الإضافي المتبقي بس (الأساسي ماتلمسوش خالص). الأسبوع الأول زي غيره.
--   • انتهاء الصلاحية: الإضافي بيتصفّر والأساسي بيفضل. التجميد: مفيش خصم أسبوعي وقت التجميد.
--   • دفتر الحركات member_ledger مابيتعدّلش ولا بيتمسح (trigger بيمنع). التصحيح بحركة عكسية من المدير بسبب مكتوب.
-- التسوية الأسبوعية آلية: بتتنفّذ تلقائيًا عند أي حركة أو فتح حساب العميل، وممكن تتجدول كمان (آخر الملف). آمن للتشغيل أكتر من مرة.

create table if not exists public.member_plans(
  id bigserial primary key,
  name text not null,
  price numeric(10,2) not null check (price > 0),
  bonus numeric(10,2) not null default 0 check (bonus >= 0),
  weekly_visits int not null default 2 check (weekly_visits between 1 and 14),
  penalty_pct numeric(5,2) not null default 25 check (penalty_pct between 0 and 100),
  valid_days int not null default 90 check (valid_days between 1 and 1095),
  active boolean not null default true,
  sort int not null default 0
);
create table if not exists public.member_accounts(
  id bigserial primary key,
  customer_id bigint not null unique references public.customers(id),
  plan_id bigint references public.member_plans(id) on delete set null,
  plan_name text not null,
  weekly_visits int not null,
  penalty_pct numeric(5,2) not null,
  cycle int not null default 1,
  started_on date not null,
  expires_on date not null,
  status text not null default 'active' check (status in ('active','frozen','expired','closed')),
  paid_bal numeric(10,2) not null default 0 check (paid_bal >= 0),
  bonus_bal numeric(10,2) not null default 0 check (bonus_bal >= 0),
  weeks_settled int not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.member_ledger(
  id bigserial primary key,
  account_id bigint not null references public.member_accounts(id),
  customer_id bigint not null,
  kind text not null check (kind in ('topup','bonus_grant','spend','weekly_penalty','expire','adjust')),
  bucket text not null check (bucket in ('paid','bonus')),
  amount numeric(10,2) not null,
  paid_after numeric(10,2) not null,
  bonus_after numeric(10,2) not null,
  invoice_id bigint,
  week_no int,
  method text,
  note text,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists member_ledger_acct on public.member_ledger(account_id, id desc);
-- منع خصم نفس الفاتورة مرتين من نفس الرصيد (للمرحلة ٢)
create unique index if not exists member_ledger_spend_once on public.member_ledger(invoice_id, bucket) where kind = 'spend';
create table if not exists public.member_weeks(
  account_id bigint not null references public.member_accounts(id),
  cycle int not null,
  week_no int not null,
  week_start date not null,
  week_end date not null,
  visits int not null,
  required int not null,
  penalty numeric(10,2) not null default 0,
  note text,
  settled_at timestamptz not null default now(),
  primary key (account_id, cycle, week_no)
);

create or replace function public.p_mb_lock() returns trigger language plpgsql as $$
begin raise exception 'دفتر الرصيد مابيتعدّلش ولا بيتمسح. التصحيح بحركة عكسية'; end $$;
drop trigger if exists member_ledger_lock on public.member_ledger;
create trigger member_ledger_lock before update or delete on public.member_ledger for each row execute function public.p_mb_lock();
drop trigger if exists member_weeks_lock on public.member_weeks;
create trigger member_weeks_lock before update or delete on public.member_weeks for each row execute function public.p_mb_lock();

alter table public.member_plans enable row level security;
alter table public.member_accounts enable row level security;
alter table public.member_ledger enable row level security;
alter table public.member_weeks enable row level security;
drop policy if exists "member plans mgr" on public.member_plans;
create policy "member plans mgr" on public.member_plans for all using (coalesce(is_mgr(),false)) with check (coalesce(is_mgr(),false));
drop policy if exists "member accounts mgr read" on public.member_accounts;
create policy "member accounts mgr read" on public.member_accounts for select using (coalesce(is_mgr(),false));
drop policy if exists "member ledger mgr read" on public.member_ledger;
create policy "member ledger mgr read" on public.member_ledger for select using (coalesce(is_mgr(),false));
drop policy if exists "member weeks mgr read" on public.member_weeks;
create policy "member weeks mgr read" on public.member_weeks for select using (coalesce(is_mgr(),false));
-- العميل والكاشير بيتعاملوا من الدوال بس (security definer)

-- عدد الزيارات (أيام فيها فاتورة خدمة) في فترة [from, to)
create or replace function public.p_mb_visits(p_customer bigint, p_from date, p_to date) returns int
language sql stable security definer set search_path to 'public' as $$
  select count(distinct (i.created_at at time zone my_tz())::date)::int from invoices i
   where i.customer_id = p_customer and i.settles_invoice is null and coalesce(i.total,0) > 0
     and (i.created_at at time zone my_tz())::date >= p_from and (i.created_at at time zone my_tz())::date < p_to
     and exists (select 1 from invoice_items x where x.invoice_id = i.id and x.item_type = 'service') $$;
revoke all on function public.p_mb_visits(bigint,date,date) from public, anon, authenticated;

create or replace function public.p_mb_today() returns date language sql stable security definer set search_path to 'public' as $$
  select (now() at time zone my_tz())::date $$;
revoke all on function public.p_mb_today() from public, anon, authenticated;

-- حركة في الدفتر + تحديث الرصيد (جوه نفس القفل)
create or replace function public.p_mb_move(p_acct bigint, p_kind text, p_bucket text, p_amount numeric, p_invoice bigint, p_week int, p_method text, p_note text) returns void
language plpgsql security definer set search_path to 'public' as $$
declare a member_accounts;
begin
  select * into a from member_accounts where id = p_acct for update;
  if p_bucket = 'paid' then a.paid_bal := a.paid_bal + p_amount; else a.bonus_bal := a.bonus_bal + p_amount; end if;
  if a.paid_bal < 0 or a.bonus_bal < 0 then raise exception 'الرصيد مايكفيش للحركة دي'; end if;
  update member_accounts set paid_bal = a.paid_bal, bonus_bal = a.bonus_bal where id = p_acct;
  insert into member_ledger(account_id, customer_id, kind, bucket, amount, paid_after, bonus_after, invoice_id, week_no, method, note, created_by)
    values (p_acct, a.customer_id, p_kind, p_bucket, round(p_amount,2), a.paid_bal, a.bonus_bal, p_invoice, p_week, p_method, p_note, auth.uid());
end $$;
revoke all on function public.p_mb_move(bigint,text,text,numeric,bigint,int,text,text) from public, anon, authenticated;

-- التسوية: الصلاحية + الأسابيع اللي خلصت ولسه ماتحسبتش
create or replace function public.p_mb_settle(p_acct bigint) returns void
language plpgsql security definer set search_path to 'public' as $$
declare a member_accounts; v_today date := p_mb_today(); v_cur int; n int; v_s date; v_e date; v_vis int; v_pen numeric;
begin
  select * into a from member_accounts where id = p_acct for update;
  if not found or a.status in ('closed') then return; end if;
  if a.status in ('active','frozen') and v_today > a.expires_on then
    if a.bonus_bal > 0 then perform p_mb_move(a.id, 'expire', 'bonus', -a.bonus_bal, null, null, null, 'انتهت صلاحية الاشتراك: الهدية اتصفّرت والرصيد الأساسي محفوظ'); end if;
    update member_accounts set status = 'expired' where id = a.id; return;
  end if;
  if a.status = 'expired' then return; end if;
  v_cur := ((v_today - a.started_on) / 7) + 1;
  for n in (a.weeks_settled + 1) .. least(v_cur - 1, a.weeks_settled + 60) loop
    v_s := a.started_on + 7 * (n - 1); v_e := v_s + 7;
    exit when v_e > v_today or v_s > a.expires_on;
    select * into a from member_accounts where id = p_acct;
    v_vis := p_mb_visits(a.customer_id, v_s, v_e); v_pen := 0;
    if a.status = 'active' and v_vis < a.weekly_visits and a.bonus_bal > 0 then
      v_pen := round(a.bonus_bal * a.penalty_pct / 100, 2);
      if v_pen > 0 then perform p_mb_move(a.id, 'weekly_penalty', 'bonus', -v_pen, null, n, null,
        'الأسبوع ' || n || ': زيارات ' || v_vis || ' من ' || a.weekly_visits || ' — خصم ' || a.penalty_pct || '% من الهدية'); end if;
    end if;
    insert into member_weeks(account_id, cycle, week_no, week_start, week_end, visits, required, penalty, note)
      values (a.id, a.cycle, n, v_s, v_e - 1, v_vis, a.weekly_visits, v_pen, case when a.status = 'frozen' then 'مجمّد: من غير خصم' end)
      on conflict do nothing;
    update member_accounts set weeks_settled = n where id = a.id;
  end loop;
end $$;
revoke all on function public.p_mb_settle(bigint) from public, anon, authenticated;

-- شحن / تجديد اشتراك (كاشير أو مدير)
create or replace function public.member_topup(p_customer bigint, p_plan bigint, p_method text default 'cash') returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare pl member_plans; a member_accounts; v_today date := p_mb_today(); v_name text;
begin
  if not (coalesce(is_mgr(),false) or coalesce(can_use_pos(),false)) then raise exception 'غير مصرح'; end if;
  if p_method not in ('cash','card','wallet') then raise exception 'طريقة دفع غير مدعومة'; end if;
  select * into pl from member_plans where id = p_plan and active;
  if not found then raise exception 'الباقة مش متاحة'; end if;
  select name into v_name from customers where id = p_customer;
  if not found then raise exception 'العميل مش موجود'; end if;
  if p_method = 'cash' and exists (select 1 from cash_closings c where c.day = v_today) then raise exception 'اليوم اتقفل — مينفعش تسجل عمليات جديدة'; end if;
  perform pg_advisory_xact_lock(hashtext('mb' || p_customer::text));
  select * into a from member_accounts where customer_id = p_customer for update;
  if not found then
    insert into member_accounts(customer_id, plan_id, plan_name, weekly_visits, penalty_pct, started_on, expires_on)
      values (p_customer, pl.id, pl.name, pl.weekly_visits, pl.penalty_pct, v_today, v_today + pl.valid_days) returning * into a;
  else
    if a.status = 'frozen' then raise exception 'الاشتراك مجمّد، فكّه الأول'; end if;
    if a.status = 'closed' then raise exception 'الاشتراك مقفول'; end if;
    perform p_mb_settle(a.id);
    select * into a from member_accounts where id = a.id;
    if a.status = 'expired' then
      update member_accounts set status = 'active', cycle = cycle + 1, started_on = v_today, weeks_settled = 0 where id = a.id;
    end if;
    update member_accounts set plan_id = pl.id, plan_name = pl.name, weekly_visits = pl.weekly_visits, penalty_pct = pl.penalty_pct,
      expires_on = greatest(expires_on, v_today + pl.valid_days) where id = a.id;
  end if;
  perform p_mb_move(a.id, 'topup', 'paid', pl.price, null, null, p_method, 'شحن باقة ' || pl.name);
  if pl.bonus > 0 then perform p_mb_move(a.id, 'bonus_grant', 'bonus', pl.bonus, null, null, null, 'هدية باقة ' || pl.name); end if;
  if p_method = 'cash' then insert into cash_moves(day, kind, amount, note) values (v_today, 'deposit', pl.price, '[رصيد اشتراك] شحن — ' || v_name); end if;
  select * into a from member_accounts where id = a.id;
  return jsonb_build_object('account', a.id, 'paid', a.paid_bal, 'bonus', a.bonus_bal, 'expires_on', a.expires_on);
end $$;

-- تصحيح يدوي (المدير بس): حركة عكسية أو إضافة بسبب مكتوب
create or replace function public.member_adjust(p_customer bigint, p_bucket text, p_amount numeric, p_note text) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare a member_accounts;
begin
  if not coalesce(is_mgr(),false) then raise exception 'غير مصرح'; end if;
  if p_bucket not in ('paid','bonus') then raise exception 'نوع الرصيد غلط'; end if;
  if p_amount is null or p_amount = 0 then raise exception 'اكتب مبلغ صحيح'; end if;
  if length(btrim(coalesce(p_note,''))) < 3 then raise exception 'اكتب سبب التصحيح'; end if;
  select * into a from member_accounts where customer_id = p_customer for update;
  if not found then raise exception 'مفيش اشتراك للعميل ده'; end if;
  perform p_mb_move(a.id, 'adjust', p_bucket, p_amount, null, null, null, 'تصحيح: ' || btrim(p_note));
  select * into a from member_accounts where id = a.id;
  return jsonb_build_object('paid', a.paid_bal, 'bonus', a.bonus_bal);
end $$;

-- تجميد / فك / قفل الاشتراك (المدير بس)
create or replace function public.member_set_status(p_customer bigint, p_status text) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if not coalesce(is_mgr(),false) then raise exception 'غير مصرح'; end if;
  if p_status not in ('active','frozen','closed') then raise exception 'حالة غلط'; end if;
  perform p_mb_settle((select id from member_accounts where customer_id = p_customer));
  update member_accounts set status = p_status where customer_id = p_customer and (status <> 'expired' or p_status = 'closed');
  if not found then raise exception 'مفيش اشتراك للعميل ده'; end if;
end $$;

-- ملخص حساب (جوه الدالة بيحسب الأسبوع الحالي والتنبيه)
create or replace function public.p_mb_summary(p_acct bigint, p_full boolean) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare a member_accounts; v_today date := p_mb_today(); v_cur int; v_s date; v_e date; v_vis int; v_due boolean := false; v_pen numeric := 0;
begin
  perform p_mb_settle(p_acct);
  select * into a from member_accounts where id = p_acct;
  v_cur := ((v_today - a.started_on) / 7) + 1; v_s := a.started_on + 7 * (v_cur - 1); v_e := v_s + 7;
  v_vis := p_mb_visits(a.customer_id, v_s, v_e);
  if a.status = 'active' and v_vis < a.weekly_visits and a.bonus_bal > 0 and v_e - v_today <= 2 then
    v_due := true; v_pen := round(a.bonus_bal * a.penalty_pct / 100, 2); end if;
  return jsonb_build_object('account', a.id, 'status', a.status, 'plan', a.plan_name, 'paid', a.paid_bal, 'bonus', a.bonus_bal, 'total', a.paid_bal + a.bonus_bal,
    'required', a.weekly_visits, 'visits', v_vis, 'remaining', greatest(0, a.weekly_visits - v_vis), 'week_no', v_cur, 'week_start', v_s, 'week_end', v_e - 1,
    'penalty_pct', a.penalty_pct, 'started_on', a.started_on, 'expires_on', a.expires_on,
    'notice', case when v_due then jsonb_build_object('ends_on', v_e - 1, 'missing', a.weekly_visits - v_vis, 'penalty', v_pen) end,
    'ledger', case when p_full then coalesce((select jsonb_agg(jsonb_build_object('at', l.created_at, 'kind', l.kind, 'bucket', l.bucket, 'amount', l.amount, 'paid', l.paid_after, 'bonus', l.bonus_after, 'note', l.note) order by l.id desc)
        from (select * from member_ledger where account_id = a.id order by id desc limit 60) l), '[]'::jsonb) end);
end $$;
revoke all on function public.p_mb_summary(bigint,boolean) from public, anon, authenticated;

-- العميل: رصيدي
create or replace function public.member_me() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare c customers; v_id bigint;
begin
  select * into c from customers where user_id = auth.uid();
  if not found then return null; end if;
  select id into v_id from member_accounts where customer_id = c.id;
  if v_id is null then return null; end if;
  return p_mb_summary(v_id, true);
end $$;

-- الكاشير/المدير: رصيد عميل
create or replace function public.member_get(p_customer bigint) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_id bigint;
begin
  if not (coalesce(is_mgr(),false) or coalesce(can_use_pos(),false)) then raise exception 'غير مصرح'; end if;
  select id into v_id from member_accounts where customer_id = p_customer;
  if v_id is null then return null; end if;
  return p_mb_summary(v_id, true);
end $$;

-- المدير: كل الاشتراكات
create or replace function public.member_list() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare r record;
begin
  if not coalesce(is_mgr(),false) then raise exception 'غير مصرح'; end if;
  for r in select id from member_accounts loop perform p_mb_settle(r.id); end loop;
  return jsonb_build_object(
    'totals', (select jsonb_build_object('accounts', count(*), 'paid', coalesce(sum(paid_bal),0), 'bonus', coalesce(sum(bonus_bal),0)) from member_accounts where status in ('active','frozen','expired')),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('customer_id', a.customer_id, 'name', coalesce(c.name,'عميل'), 'phone', c.phone, 'plan', a.plan_name, 'status', a.status, 'paid', a.paid_bal, 'bonus', a.bonus_bal, 'expires_on', a.expires_on) order by a.paid_bal + a.bonus_bal desc)
        from member_accounts a left join customers c on c.id = a.customer_id), '[]'::jsonb),
    'penalties_30d', (select coalesce(sum(-amount),0) from member_ledger where kind = 'weekly_penalty' and created_at > now() - interval '30 days'));
end $$;

-- تسوية كل الحسابات (للجدولة)
create or replace function public.member_settle_all() returns int
language plpgsql security definer set search_path to 'public' as $$
declare r record; n int := 0;
begin
  if auth.uid() is not null and not coalesce(is_mgr(),false) then raise exception 'غير مصرح'; end if;
  for r in select id from member_accounts where status in ('active','frozen') loop perform p_mb_settle(r.id); n := n + 1; end loop;
  return n;
end $$;

do $$ declare f text; begin
  foreach f in array array['member_topup(bigint,bigint,text)','member_adjust(bigint,text,numeric,text)','member_set_status(bigint,text)','member_me()','member_get(bigint)','member_list()','member_settle_all()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

insert into public.member_plans(name, price, bonus, weekly_visits, penalty_pct, valid_days, sort)
select * from (values ('باقة 1000', 1000, 200, 2, 25, 90, 1)) v(n,p,b,w,pc,d,s) where not exists (select 1 from public.member_plans);

-- اختياري (جدولة التسوية كل يوم الساعة 3 فجرًا بتوقيت القاهرة تقريبًا = 01:00 UTC). شغّله لو pg_cron متاح:
-- select cron.schedule('member-settle-daily', '0 1 * * *', $$select public.member_settle_all()$$);
-- تراجع: drop function member_topup(bigint,bigint,text), member_adjust(bigint,text,numeric,text), member_set_status(bigint,text), member_me(), member_get(bigint), member_list(), member_settle_all(), p_mb_summary(bigint,boolean), p_mb_settle(bigint), p_mb_move(bigint,text,text,numeric,bigint,int,text,text), p_mb_visits(bigint,date,date), p_mb_today(); drop table member_weeks, member_ledger, member_accounts, member_plans;
