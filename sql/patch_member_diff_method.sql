-- patch_member_diff_method.sql — فرق الدفع من الرصيد يتدفع كاش أو كارت أو محفظة (كان كاش بس)
-- لما رصيد العميل مايكفيش، الفرق بيتحصّل بالطريقة اللي الكاشير يختارها. الكاش بس هو اللي بيدخل الدرج (إيداع)؛ الكارت والمحفظة
-- مابيدخلوش الدرج لكن بيتسجّلوا في جدول member_diff_pay عشان تعرف المبلغ ده اتحصّل إزاي. الفاتورة نفسها بتفضل «رصيد اشتراك».
-- لازم patch_membership_pay.sql متشغّل. آمن للتشغيل أكتر من مرة (بيستبدل الدالة القديمة).
create table if not exists public.member_diff_pay(
  invoice_id bigint primary key,
  method text not null check (method in ('cash','card','wallet')),
  amount numeric(10,2) not null check (amount > 0),
  at timestamptz not null default now()
);
alter table public.member_diff_pay enable row level security;
drop policy if exists "member diff mgr read" on public.member_diff_pay;
create policy "member diff mgr read" on public.member_diff_pay for select using (coalesce(is_mgr(),false));
-- مسح النسخة القديمة (ناقصها عامل) عشان مايحصلش لبس بين نسختين بنفس الاسم
drop function if exists public.member_checkout(bigint, uuid, jsonb, numeric, numeric, bigint, bigint, bigint, bigint, jsonb, boolean, bigint, boolean);
create or replace function public.member_checkout(
  p_customer bigint, p_barber uuid, p_items jsonb, p_discount_pct numeric, p_discount_fixed numeric,
  p_appointment bigint default null, p_redemption bigint default null, p_request bigint default null,
  p_bundle bigint default null, p_cafe jsonb default null, p_outside boolean default false, p_company bigint default null,
  p_cash_diff boolean default false, p_diff_method text default 'cash') returns bigint
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
    if not coalesce(p_cash_diff, false) then raise exception 'الرصيد مايكفيش: الفرق % جنيه. أكّد دفع الفرق', v_r; end if;
    if coalesce(p_diff_method,'cash') not in ('cash','card','wallet') then raise exception 'طريقة دفع الفرق غير مدعومة'; end if;
    if coalesce(p_diff_method,'cash') = 'cash' and exists (select 1 from cash_closings c where c.day = v_today) then raise exception 'اليوم اتقفل — مينفعش تسجل عمليات جديدة'; end if;
  end if;
  if v_p > 0 then perform p_mb_move(a.id, 'spend', 'paid', -v_p, v_inv, null, null, 'فاتورة #' || i.no || ' (زيارة ' || v_n || ' في الأسبوع)'); end if;
  if v_b > 0 then perform p_mb_move(a.id, 'spend', 'bonus', -v_b, v_inv, null, null, 'فاتورة #' || i.no || ' (زيارة ' || v_n || ' في الأسبوع)'); end if;
  update invoices set payment_method = 'member' where id = v_inv;
  if v_r > 0.004 then
    select name into v_name from customers where id = v_cust;
    insert into member_diff_pay(invoice_id, method, amount) values (v_inv, coalesce(p_diff_method,'cash'), round(v_r,2));
    if coalesce(p_diff_method,'cash') = 'cash' then insert into cash_moves(day, kind, amount, note) values (v_today, 'deposit', round(v_r, 2), '[رصيد اشتراك] فرق فاتورة #' || i.no || ' — ' || coalesce(v_name, '')); end if;
  end if;
  return v_inv;
end $$;
revoke all on function public.member_checkout(bigint, uuid, jsonb, numeric, numeric, bigint, bigint, bigint, bigint, jsonb, boolean, bigint, boolean, text) from public, anon;
grant execute on function public.member_checkout(bigint, uuid, jsonb, numeric, numeric, bigint, bigint, bigint, bigint, jsonb, boolean, bigint, boolean, text) to authenticated;
-- تراجع: شغّل member_checkout من patch_membership_pay.sql (بعد drop للنسخة الجديدة بـ14 عامل)
