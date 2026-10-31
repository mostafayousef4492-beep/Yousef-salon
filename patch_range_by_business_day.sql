-- ============================================================================
-- إصلاح: "الموجود في الدرج" في التقرير الشامل (range_figures) كان بيوزّع الفواتير والسلف
-- على التاريخ الميلادي، بينما قفل اليوم (day_figures) بيوزّعها على يوم العمل (اللي بيفضل
-- مفتوح بعد 12 بالليل). فالشغل اللي بعد منتصف الليل كان بيتحسب على يوم غلط والرصيد بيختلف.
-- دلوقتي نفس منطق يوم العمل بيتطبّق على الفواتير والسلف ومبيعات الكوفي في التقرير.
-- مفيش تغيير في أي بيانات. الدالتين بس.
-- ============================================================================
create or replace function range_figures_salon(p_from date, p_to date) returns jsonb
language plpgsql stable set search_path to 'public' as $$
declare v_tz text := my_tz(); r jsonb;
begin
  with w as (select b.day, p24b_start(b.day) s, coalesce(b.closed_at, 'infinity'::timestamptz) e from business_days b),
  inv as (select i.total, i.payment_method,
            coalesce((select w.day from w where i.created_at >= w.s and i.created_at < w.e order by w.day desc limit 1), (i.created_at at time zone v_tz)::date) d
          from invoices i),
  adv as (select t.amount,
            coalesce((select w.day from w where t.created_at >= w.s and t.created_at < w.e order by w.day desc limit 1), (t.created_at at time zone v_tz)::date) d
          from staff_transactions t where t.kind = 'advance')
  select jsonb_build_object(
    'invoices', (select count(*) from inv where d between p_from and p_to),
    'revenue', (select coalesce(sum(total),0) from inv where d between p_from and p_to),
    'cash_sales', (select coalesce(sum(total),0) from inv where d between p_from and p_to and payment_method = 'cash'),
    'card_sales', (select coalesce(sum(total),0) from inv where d between p_from and p_to and payment_method = 'card'),
    'wallet_sales', (select coalesce(sum(total),0) from inv where d between p_from and p_to and payment_method = 'wallet'),
    'exp_cash', (select coalesce(sum(e.amount),0) from expenses e where e.spent_on between p_from and p_to and e.paid_from = 'drawer' and e.purchase_id is null),
    'pur_cash', (select coalesce(sum(p.paid),0) from purchases p where p.bought_on between p_from and p_to and p.paid_from = 'drawer'),
    'sup_cash', (select coalesce(sum(s.amount),0) from supplier_payments s where s.paid_on between p_from and p_to and s.paid_from = 'drawer'),
    'sal_cash', (select coalesce(sum(s.amount),0) from salary_payments s where s.paid_on between p_from and p_to and s.paid_from = 'drawer'),
    'adv_cash', (select coalesce(sum(amount),0) from adv where d between p_from and p_to),
    'moves_out', (select coalesce(sum(m.amount),0) from cash_moves m where m.day between p_from and p_to and m.kind = 'withdraw'),
    'moves_in', (select coalesce(sum(m.amount),0) from cash_moves m where m.day between p_from and p_to and m.kind = 'deposit'),
    'opening', coalesce((select c.counted_cash from cash_closings c where c.day < p_from order by c.day desc limit 1), 0)
  ) into r;
  return r;
end $$;

-- لفّاف الكوفي: نفس التوزيع على يوم العمل
create or replace function range_figures(p_from date, p_to date) returns jsonb
language plpgsql stable set search_path to 'public' as $$
declare f jsonb := range_figures_salon(p_from, p_to); v_tz text := my_tz(); cc numeric; cd numeric; cw numeric; ce numeric; cp numeric;
begin
  with w as (select b.day, p24b_start(b.day) s, coalesce(b.closed_at, 'infinity'::timestamptz) e from business_days b),
  cs as (select s.total, s.payment_method,
           coalesce((select w.day from w where s.created_at >= w.s and s.created_at < w.e order by w.day desc limit 1), (s.created_at at time zone v_tz)::date) d
         from cafe_sales s where s.status = 'paid')
  select coalesce(sum(total) filter (where payment_method = 'cash'),0), coalesce(sum(total) filter (where payment_method = 'card'),0),
         coalesce(sum(total) filter (where payment_method = 'wallet'),0)
    into cc, cd, cw from cs where d between p_from and p_to;
  select coalesce(sum(amount),0) into ce from cafe_expenses e where e.spent_on between p_from and p_to and e.paid_from = 'drawer' and e.purchase_id is null;
  select coalesce(sum(total),0) into cp from cafe_purchases p where p.bought_on between p_from and p_to and p.paid_from = 'drawer';
  return f || jsonb_build_object(
    'cash_sales',   (f->>'cash_sales')::numeric + cc, 'card_sales', (f->>'card_sales')::numeric + cd, 'wallet_sales', (f->>'wallet_sales')::numeric + cw,
    'exp_cash',     (f->>'exp_cash')::numeric + ce,   'pur_cash',   (f->>'pur_cash')::numeric + cp,
    'cafe_cash', cc, 'cafe_card', cd, 'cafe_wallet', cw, 'cafe_exp_cash', ce, 'cafe_pur_cash', cp);
end $$;
