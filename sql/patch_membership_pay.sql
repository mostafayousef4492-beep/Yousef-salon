-- patch_membership_pay.sql — ABO YOUSEF MEMBERSHIP (المرحلة ٢): الدفع من رصيد الاشتراك عند الكاشير
-- لازم patch_membership.sql يكون متشغّل قبله.
-- التغيير الوحيد في الجداول الموجودة: قيد طريقة الدفع في الفواتير بيقبل قيمة جديدة 'member' (توسيع بس، مفيش فاتورة قديمة بتتغير).
-- pos_checkout و pos_checkout_b ماتلمسوش: member_checkout بينادي pos_checkout_b نفسها (بنفس كل قواعد الخصم والباقة والعمولة)
-- وبعدين في نفس العملية بيخصم من الرصيد وبيعلّم الفاتورة «رصيد اشتراك». لو أي خطوة فشلت كل حاجة بترجع (مفيش فاتورة نص نص).
-- قواعد الخصم: الزيارة الأولى في الأسبوع من الرصيد الأساسي، التانية وما بعدها من رصيد الهدية. اللي مايكفيش من الرصيد الأول بيكمّل من التاني.
-- لو الرصيدين مايكفوش: الفرق كاش (p_cash_diff=true)، وبيتسجّل إيداع في الدرج بقيمة الفرق. الفاتورة نفسها «رصيد اشتراك» فمابتدخلش الدرج.
-- الفاتورة بتتحسب كاملة في المبيعات والعمولة زي أي فاتورة. مش متاح مع منتجات الكوفي كورنر. آمن للتكرار.

begin;
alter table public.invoices drop constraint if exists invoices_payment_method_check;
alter table public.invoices add constraint invoices_payment_method_check check (payment_method = any (array['cash'::text, 'card'::text, 'wallet'::text, 'member'::text]));

create unique index if not exists member_ledger_rev_once on public.member_ledger(invoice_id, bucket) where kind = 'adjust' and invoice_id is not null;

-- تقسيم مبلغ على الرصيدين حسب ترتيب الزيارة (دالة حساب بس، مابتغيّر حاجة)
create or replace function public.p_mb_split(p_paid numeric, p_bonus numeric, p_total numeric, p_visit int)
returns jsonb language sql immutable as $$
  select case when p_visit <= 1
    then jsonb_build_object('paid', least(p_paid, p_total), 'bonus', least(p_bonus, greatest(p_total - least(p_paid, p_total), 0)))
    else jsonb_build_object('bonus', least(p_bonus, p_total), 'paid', least(p_paid, greatest(p_total - least(p_bonus, p_total), 0))) end $$;

-- معاينة للكاشير: لو الإجمالي كذا، هيتخصم منين وكام الفرق
create or replace function public.member_quote(p_customer bigint, p_total numeric) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare a member_accounts; v_today date := p_mb_today(); v_cur int; v_s date; v_vis int; v_n int; sp jsonb; v_use numeric; v_has boolean;
begin
  if not (coalesce(is_mgr(),false) or coalesce(can_use_pos(),false)) then raise exception 'غير مصرح'; end if;
  select * into a from member_accounts where customer_id = p_customer;
  if not found then return null; end if;
  perform p_mb_settle(a.id);
  select * into a from member_accounts where id = a.id;
  v_cur := ((v_today - a.started_on) / 7) + 1; v_s := a.started_on + 7 * (v_cur - 1);
  v_vis := p_mb_visits(a.customer_id, v_s, v_s + 7);
  v_has := exists (select 1 from invoices i where i.customer_id = a.customer_id and i.settles_invoice is null and coalesce(i.total,0) > 0 and (i.created_at at time zone my_tz())::date = v_today
                    and exists (select 1 from invoice_items x where x.invoice_id = i.id and x.item_type = 'service'));
  v_n := v_vis + case when v_has then 0 else 1 end;
  sp := p_mb_split(a.paid_bal, a.bonus_bal, coalesce(p_total,0), v_n);
  v_use := (sp->>'paid')::numeric + (sp->>'bonus')::numeric;
  return jsonb_build_object('status', a.status, 'paid_bal', a.paid_bal, 'bonus_bal', a.bonus_bal, 'visit_no', v_n,
    'use_paid', (sp->>'paid')::numeric, 'use_bonus', (sp->>'bonus')::numeric, 'cash_due', greatest(coalesce(p_total,0) - v_use, 0), 'usable', a.status in ('active','expired'));
end $$;

create or replace function public.member_checkout(
  p_customer bigint, p_barber uuid, p_items jsonb, p_discount_pct numeric, p_discount_fixed numeric,
  p_appointment bigint default null, p_redemption bigint default null, p_request bigint default null,
  p_bundle bigint default null, p_cafe jsonb default null, p_outside boolean default false, p_company bigint default null,
  p_cash_diff boolean default false) returns bigint
language plpgsql security definer set search_path to 'public' as $$
declare v_inv bigint; i invoices; a member_accounts; v_today date := p_mb_today(); v_cur int; v_s date; v_n int; sp jsonb; v_p numeric; v_b numeric; v_r numeric; v_name text; v_cust bigint := p_customer;
begin
  if not can_use_pos() then raise exception 'غير مصرح'; end if;
  if p_cafe is not null and jsonb_typeof(p_cafe) = 'array' and jsonb_array_length(p_cafe) > 0 then raise exception 'الدفع من الرصيد مش متاح مع منتجات الكوفي كورنر'; end if;
  if v_cust is null and p_appointment is not null then select customer_id into v_cust from appointments where id = p_appointment; end if;
  if v_cust is null then raise exception 'الدفع من الرصيد لعميل مسجّل بس'; end if;
  perform pg_advisory_xact_lock(hashtext('mb' || v_cust::text));
  select * into a from member_accounts where customer_id = v_cust for update;
  if not found then raise exception 'العميل ده مالوش اشتراك'; end if;
  if a.status = 'frozen' then raise exception 'الاشتراك مجمّد'; end if;
  if a.status = 'closed' then raise exception 'الاشتراك مقفول'; end if;
  perform p_mb_settle(a.id);
  select * into a from member_accounts where id = a.id;
  v_inv := pos_checkout_b(p_bundle, null, v_cust, p_barber, p_items, p_discount_pct, p_discount_fixed, 'cash', p_appointment, p_redemption, p_request, coalesce(p_outside,false), p_company);
  select * into i from invoices where id = v_inv;
  if coalesce(i.total,0) <= 0 then raise exception 'الفاتورة إجماليها صفر، مفيش حاجة تتخصم من الرصيد'; end if;
  v_cur := ((v_today - a.started_on) / 7) + 1; v_s := a.started_on + 7 * (v_cur - 1);
  v_n := p_mb_visits(v_cust, v_s, v_s + 7);   -- بيشمل الفاتورة دي (فيها خدمة وإجماليها > 0)
  if v_n < 1 then v_n := 1; end if;
  sp := p_mb_split(a.paid_bal, a.bonus_bal, i.total, v_n);
  v_p := (sp->>'paid')::numeric; v_b := (sp->>'bonus')::numeric; v_r := i.total - v_p - v_b;
  if v_p + v_b <= 0 then raise exception 'مفيش رصيد كفاية في حساب العميل'; end if;
  if v_r > 0.004 then
    if not coalesce(p_cash_diff, false) then raise exception 'الرصيد مايكفيش: الفرق % جنيه. أكّد دفع الفرق كاش', v_r; end if;
    if exists (select 1 from cash_closings c where c.day = v_today) then raise exception 'اليوم اتقفل — مينفعش تسجل عمليات جديدة'; end if;
  end if;
  if v_p > 0 then perform p_mb_move(a.id, 'spend', 'paid', -v_p, v_inv, null, null, 'فاتورة #' || i.no || ' (زيارة ' || v_n || ' في الأسبوع)'); end if;
  if v_b > 0 then perform p_mb_move(a.id, 'spend', 'bonus', -v_b, v_inv, null, null, 'فاتورة #' || i.no || ' (زيارة ' || v_n || ' في الأسبوع)'); end if;
  update invoices set payment_method = 'member' where id = v_inv;
  if v_r > 0.004 then
    select name into v_name from customers where id = v_cust;
    insert into cash_moves(day, kind, amount, note) values (v_today, 'deposit', round(v_r, 2), '[رصيد اشتراك] فرق فاتورة #' || i.no || ' — ' || coalesce(v_name, ''));
  end if;
  return v_inv;
end $$;

-- عكس دفع فاتورة من الرصيد (مثلًا بعد إلغاء الفاتورة): بيرجّع المبالغ لنفس الرصيدين بحركة عكسية. المدير بس. مرة واحدة لكل فاتورة.
-- لو العميل دفع فرق كاش، رجّعه من الدرج بنفسك (سحب) لأن العملية دي بترجّع الرصيد بس.
create or replace function public.member_reverse_invoice(p_invoice bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare r record; n int := 0; v_tot numeric := 0;
begin
  if not coalesce(is_mgr(), false) then raise exception 'غير مصرح'; end if;
  if not exists (select 1 from member_ledger where invoice_id = p_invoice and kind = 'spend') then raise exception 'الفاتورة دي ماتدفعتش من رصيد'; end if;
  if exists (select 1 from member_ledger where invoice_id = p_invoice and kind = 'adjust') then raise exception 'الفاتورة دي اتعكست قبل كده'; end if;
  for r in select account_id, bucket, -amount amt from member_ledger where invoice_id = p_invoice and kind = 'spend' loop
    perform p_mb_move(r.account_id, 'adjust', r.bucket, r.amt, p_invoice, null, null, 'عكس دفع فاتورة' || coalesce(' — ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
    n := n + 1; v_tot := v_tot + r.amt;
  end loop;
  return jsonb_build_object('reversed', n, 'amount', v_tot);
end $$;

do $$ declare f text; begin
  foreach f in array array['member_quote(bigint,numeric)','member_checkout(bigint,uuid,jsonb,numeric,numeric,bigint,bigint,bigint,bigint,jsonb,boolean,bigint,boolean)','member_reverse_invoice(bigint,text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
commit;
-- تراجع: drop function member_quote(bigint,numeric), member_checkout(bigint,uuid,jsonb,numeric,numeric,bigint,bigint,bigint,bigint,jsonb,boolean,bigint,boolean), member_reverse_invoice(bigint,text), p_mb_split(numeric,numeric,numeric,int);
--        (قيد طريقة الدفع: لو مفيش فاتورة 'member' ممكن ترجعه لـ cash/card/wallet بس)
