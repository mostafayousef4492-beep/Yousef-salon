-- patch_gift_cards.sql — كروت الهدايا (ABO YOUSEF MEMBERSHIP)
-- لازم patch_membership.sql متشغّل. الكارت = كود من 10 حروف بمبلغ. الكاشير بيبيعه، والعميل يدخل الكود في تطبيقه
-- فالمبلغ بيضاف لـ«رصيدي» (الرصيد الأساسي) وبيتصرف بنفس قواعد الاشتراك. الكود بيتحرق من أول استخدام.
-- الفلوس: بيع الكارت كاش = إيداع في الدرج (مش مبيعات) وبيتحسب التزام لحد ما العميل يستخدمه. مفيش خصم ولا تغيير في الفواتير.
-- الأمان: الكود مش بيتخزن في أي حتة قدام العميل، ومحاولات الكود الغلط محدودة (5 غلط في الساعة للعميل)، والكارت مايتستخدمش مرتين،
-- وكل استخدام بيتسجّل في دفتر الرصيد اللي مابيتعدّلش. آمن للتشغيل أكتر من مرة.
create table if not exists public.gift_cards(
  id bigserial primary key,
  code text not null unique,
  amount numeric(10,2) not null check (amount > 0),
  status text not null default 'active' check (status in ('active','redeemed','void')),
  buyer_customer_id bigint references public.customers(id),
  method text not null check (method in ('cash','card','wallet')),
  note text,
  created_by uuid,
  created_at timestamptz not null default now(),
  redeemed_customer_id bigint references public.customers(id),
  redeemed_at timestamptz,
  void_reason text,
  voided_at timestamptz
);
create table if not exists public.gift_redeem_log(
  id bigserial primary key,
  user_id uuid not null,
  ok boolean not null,
  at timestamptz not null default now()
);
create index if not exists gift_redeem_log_user on public.gift_redeem_log(user_id, at desc);
alter table public.gift_cards enable row level security;
alter table public.gift_redeem_log enable row level security;
drop policy if exists "gift cards mgr read" on public.gift_cards;
create policy "gift cards mgr read" on public.gift_cards for select using (coalesce(is_mgr(),false));
-- gift_redeem_log: مفيش policy = مفيش وصول مباشر (الدوال بس)

create or replace function public.p_gift_code() returns text language plpgsql volatile as $$
declare v_a text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; v_c text := ''; i int;
begin
  for i in 1..10 loop v_c := v_c || substr(v_a, 1 + floor(random() * length(v_a))::int, 1); end loop;
  return v_c;
end $$;
revoke all on function public.p_gift_code() from public, anon, authenticated;

-- بيع كارت (كاشير/مدير). بيرجّع الكود مرة واحدة هنا بس عشان الكاشير يسلّمه.
create or replace function public.gift_card_sell(p_amount numeric, p_method text default 'cash', p_buyer bigint default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_code text; v_id bigint; v_today date := p_mb_today(); v_try int := 0;
begin
  if not (coalesce(is_mgr(),false) or coalesce(can_use_pos(),false)) then raise exception 'غير مصرح'; end if;
  if p_amount is null or p_amount < 50 or p_amount > 10000 then raise exception 'مبلغ الكارت من 50 لـ 10000 جنيه'; end if;
  if p_method not in ('cash','card','wallet') then raise exception 'طريقة دفع غير مدعومة'; end if;
  if p_buyer is not null and not exists (select 1 from customers where id = p_buyer) then raise exception 'العميل مش موجود'; end if;
  if p_method = 'cash' and exists (select 1 from cash_closings c where c.day = v_today) then raise exception 'اليوم اتقفل — مينفعش تسجل عمليات جديدة'; end if;
  loop
    v_code := p_gift_code(); v_try := v_try + 1;
    begin
      insert into gift_cards(code, amount, buyer_customer_id, method, note, created_by) values (v_code, round(p_amount,2), p_buyer, p_method, nullif(btrim(coalesce(p_note,'')),''), auth.uid()) returning id into v_id;
      exit;
    exception when unique_violation then
      if v_try > 8 then raise exception 'تعذّر إنشاء كود، حاول تاني'; end if;
    end;
  end loop;
  if p_method = 'cash' then insert into cash_moves(day, kind, amount, note) values (v_today, 'deposit', round(p_amount,2), '[كارت هدية] بيع كارت #' || v_id); end if;
  return jsonb_build_object('id', v_id, 'code', v_code, 'amount', round(p_amount,2));
end $$;

-- استخدام كارت (العميل نفسه)
create or replace function public.gift_card_redeem(p_code text) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare c customers; g gift_cards; a member_accounts; v_code text := upper(regexp_replace(coalesce(p_code,''), '[^A-Za-z0-9]', '', 'g')); v_today date := p_mb_today();
begin
  if auth.uid() is null then raise exception 'غير مصرح'; end if;
  select * into c from customers where user_id = auth.uid();
  if not found then raise exception 'سجّل دخولك الأول'; end if;
  if (select count(*) from gift_redeem_log where user_id = auth.uid() and not ok and at > now() - interval '1 hour') >= 5 then
    raise exception 'محاولات غلط كتير. جرّب بعد ساعة'; end if;
  perform pg_advisory_xact_lock(hashtext('mb' || c.id::text));
  select * into g from gift_cards where code = v_code for update;
  if not found or g.status <> 'active' then
    insert into gift_redeem_log(user_id, ok) values (auth.uid(), false);
    -- الإدخال ده لازم يفضل حتى لو الدالة رجعت خطأ: بنرجّع نتيجة بدل exception
    return jsonb_build_object('ok', false, 'error', case when found and g.status = 'redeemed' then 'الكارت ده اتستخدم قبل كده' else 'الكود غلط أو الكارت مش متاح' end);
  end if;
  select * into a from member_accounts where customer_id = c.id for update;
  if not found then
    insert into member_accounts(customer_id, plan_name, weekly_visits, penalty_pct, started_on, expires_on)
      values (c.id, 'رصيد هدية', 1, 0, v_today, v_today + 365) returning * into a;
  elsif a.status in ('frozen','closed') then
    return jsonb_build_object('ok', false, 'error', 'اشتراكك مجمّد أو مقفول، كلّم الصالون');
  end if;
  perform p_mb_move(a.id, 'topup', 'paid', g.amount, null, null, 'gift', 'كارت هدية ' || substr(g.code, 1, 2) || '••••••' || substr(g.code, 9));
  update gift_cards set status = 'redeemed', redeemed_customer_id = c.id, redeemed_at = now() where id = g.id;
  insert into gift_redeem_log(user_id, ok) values (auth.uid(), true);
  select * into a from member_accounts where id = a.id;
  return jsonb_build_object('ok', true, 'amount', g.amount, 'paid', a.paid_bal, 'bonus', a.bonus_bal);
end $$;

-- المدير: قايمة الكروت + الالتزام القائم
create or replace function public.gift_card_list() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
begin
  if not coalesce(is_mgr(),false) then raise exception 'غير مصرح'; end if;
  return jsonb_build_object(
    'outstanding', (select coalesce(sum(amount),0) from gift_cards where status = 'active'),
    'count_active', (select count(*) from gift_cards where status = 'active'),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'code', g.code, 'amount', g.amount, 'status', g.status, 'method', g.method, 'created_at', g.created_at, 'buyer', b.name, 'redeemed_by', r.name, 'redeemed_at', g.redeemed_at, 'note', g.note) order by g.id desc)
       from (select * from gift_cards order by id desc limit 100) g left join customers b on b.id = g.buyer_customer_id left join customers r on r.id = g.redeemed_customer_id), '[]'::jsonb));
end $$;

-- المدير: إلغاء كارت لسه ماتستخدمش (لو الكاش اترجع للعميل، اسحبه من الدرج بنفسك)
create or replace function public.gift_card_void(p_id bigint, p_reason text) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if not coalesce(is_mgr(),false) then raise exception 'غير مصرح'; end if;
  if length(btrim(coalesce(p_reason,''))) < 3 then raise exception 'اكتب سبب الإلغاء'; end if;
  update gift_cards set status = 'void', void_reason = btrim(p_reason), voided_at = now() where id = p_id and status = 'active';
  if not found then raise exception 'الكارت مش موجود أو اتستخدم قبل كده'; end if;
end $$;

do $$ declare f text; begin
  foreach f in array array['gift_card_sell(numeric,text,bigint,text)','gift_card_redeem(text)','gift_card_list()','gift_card_void(bigint,text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
-- تراجع: drop function gift_card_sell(numeric,text,bigint,text), gift_card_redeem(text), gift_card_list(), gift_card_void(bigint,text), p_gift_code(); drop table gift_redeem_log, gift_cards;
