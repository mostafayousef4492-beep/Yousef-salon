-- accounting_alerts(p_days): تنبيهات الحسابات الناقصة (آخر p_days يوم، الافتراضي 14). قراءة بس، للمالك/المدير.
--   • أيام فاتت من غير قفل خزنة
--   • فرق جرد من غير سبب مكتوب
--   • أيام اتقفلت وبعد كده حركاتها اتغيّرت (drawer_audit)
--   • حركات درج من غير تصنيف ولا ملاحظة
--   • مصروفات «أخرى» من غير ملاحظة
create or replace function public.accounting_alerts(p_days int default 14)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $fn$
declare v_tz text := my_tz(); v_today date := (now() at time zone v_tz)::date; v_from date; r jsonb := '[]'::jsonb; n int; x numeric; s text;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  p_days := greatest(least(coalesce(p_days, 14), 60), 1);
  v_from := v_today - p_days;

  select count(*), string_agg(to_char(b.day, 'MM-DD'), '، ' order by b.day) into n, s
    from business_days b where b.day >= v_from and b.day < v_today and not exists (select 1 from cash_closings c where c.day = b.day);
  if n > 0 then r := r || jsonb_build_array(jsonb_build_object('level', 'high', 'text', n || ' يوم فات من غير قفل خزنة (' || s || ')')); end if;

  select count(*), coalesce(max(greatest(abs(coalesce(c.diff_cash, 0)), abs(coalesce(c.diff_card, 0)), abs(coalesce(c.diff_wallet, 0)))), 0) into n, x
    from cash_closings c
   where c.day >= v_from and (abs(coalesce(c.diff_cash, 0)) >= 1 or abs(coalesce(c.diff_card, 0)) >= 1 or abs(coalesce(c.diff_wallet, 0)) >= 1) and coalesce(btrim(c.note), '') = '';
  if n > 0 then r := r || jsonb_build_array(jsonb_build_object('level', 'warn', 'text', 'فرق جرد من غير سبب مكتوب في ' || n || ' يوم (أكبر فرق ' || round(x) || ')')); end if;

  select count(*), coalesce(max(abs((e->>'changed')::numeric)), 0) into n, x from jsonb_array_elements(drawer_audit(p_days)) e;
  if n > 0 then r := r || jsonb_build_array(jsonb_build_object('level', 'high', 'text', n || ' يوم اتقفل وبعدها حركاته اتغيّرت (أكبر تغيير ' || round(x) || ')')); end if;

  select count(*) into n from cash_moves m where m.day >= v_from and m.category is null and coalesce(btrim(m.note), '') = '';
  if n > 0 then r := r || jsonb_build_array(jsonb_build_object('level', 'warn', 'text', n || ' حركة درج من غير تصنيف ولا ملاحظة')); end if;

  select count(*), coalesce(sum(e.amount), 0) into n, x from expenses e
   where e.spent_on >= v_from and e.category = 'أخرى' and e.purchase_id is null and coalesce(btrim(e.note), '') = '';
  if n > 0 then r := r || jsonb_build_array(jsonb_build_object('level', 'warn', 'text', n || ' مصروف «أخرى» من غير ملاحظة (إجمالي ' || round(x) || ')')); end if;

  return r;
end $fn$;
revoke all on function public.accounting_alerts(int) from public, anon;
grant execute on function public.accounting_alerts(int) to authenticated;
