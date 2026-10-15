-- =====================================================================
-- cashier_ops.sql — تسجيل الكاشير من الخزنة: مصروف / سحب / إضافة للدرج / سلفة موظف
-- (للمراجعة: اتجرّب على نسخة محلية من المخطط فقط — جرّبه على branch قبل الإنتاج)
-- بيستخدم الجداول الموجودة: expenses, cash_moves, staff_transactions, cash_closings. لا جداول جديدة.
-- الصلاحية: المالك/المدير، أو الموظف اللي عنده perms.cash_ops (الكاشير افتراضيًا ما لم تُقفل له).
-- كل العمليات بتتسجل بتاريخ النهارده (توقيت my_tz) وبـ created_by = المستخدم الحالي، وبتتمنع بعد قفل اليوم.
-- التراجع: drop function public.cashier_board(), cashier_add_expense(text,numeric,text,text),
--          cashier_add_advance(uuid,numeric,text), cashier_add_move(text,numeric,text), p16_cash_ops();
-- =====================================================================

create or replace function public.p16_cash_ops() returns boolean
language sql stable security definer set search_path to 'public'
as $$
  select coalesce((select case when p.role::text in ('owner','manager') then true
                               when p.perms ? 'cash_ops' then coalesce((p.perms->>'cash_ops')::boolean, false)
                               else p.role::text = 'cashier' end
                     from profiles p where p.id = auth.uid()), false) $$;

create or replace function public.p16_today() returns date
language sql stable set search_path to 'public','pg_temp'
as $$ select (now() at time zone my_tz())::date $$;

create or replace function public.cashier_board() returns jsonb
language plpgsql stable security definer set search_path to 'public'
as $$
declare v_d date := p16_today();
begin
  if not p16_cash_ops() then raise exception 'غير مصرح'; end if;
  return jsonb_build_object(
    'day', v_d,
    'closed', exists (select 1 from cash_closings c where c.day = v_d),
    'cats', coalesce((select jsonb_agg(c.name order by c.id) from expense_categories c where c.active), '[]'::jsonb),
    'staff', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.full_name) order by p.full_name)
                         from profiles p where p.role::text in ('barber','assistant','cashier','manager')), '[]'::jsonb),
    'expenses', coalesce((select jsonb_agg(jsonb_build_object('category', e.category, 'amount', e.amount, 'note', e.note, 'paid_from', e.paid_from) order by e.id desc)
                            from expenses e where e.spent_on = v_d and e.purchase_id is null), '[]'::jsonb),
    'moves', coalesce((select jsonb_agg(jsonb_build_object('kind', m.kind, 'amount', m.amount, 'note', m.note) order by m.id desc)
                         from cash_moves m where m.day = v_d), '[]'::jsonb),
    'advances', coalesce((select jsonb_agg(jsonb_build_object('staff', p.full_name, 'amount', t.amount, 'note', t.note) order by t.id desc)
                            from staff_transactions t join profiles p on p.id = t.staff_id
                           where t.kind = 'advance' and (t.created_at at time zone my_tz())::date = v_d), '[]'::jsonb));
end $$;

create or replace function public.cashier_add_expense(p_category text, p_amount numeric, p_note text default null, p_paid_from text default 'drawer')
returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_d date := p16_today(); v_id bigint; v_cat text := btrim(coalesce(p_category,''));
begin
  if not p16_cash_ops() then raise exception 'غير مصرح'; end if;
  if exists (select 1 from cash_closings c where c.day = v_d) then raise exception 'اليوم اتقفل — مينفعش تسجل عمليات جديدة'; end if;
  if v_cat = '' or char_length(v_cat) > 60 then raise exception 'اختار البند'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 10000000 then raise exception 'المبلغ غير صحيح'; end if;
  if coalesce(p_paid_from,'drawer') not in ('drawer','other') then raise exception 'مصدر الدفع غير صحيح'; end if;
  insert into expenses(spent_on, category, amount, note, paid_from)
  values (v_d, v_cat, round(p_amount,2), nullif(btrim(coalesce(p_note,'')),''), coalesce(p_paid_from,'drawer')) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.cashier_add_advance(p_staff uuid, p_amount numeric, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_d date := p16_today(); v_id bigint;
begin
  if not p16_cash_ops() then raise exception 'غير مصرح'; end if;
  if exists (select 1 from cash_closings c where c.day = v_d) then raise exception 'اليوم اتقفل — مينفعش تسجل عمليات جديدة'; end if;
  if not exists (select 1 from profiles p where p.id = p_staff and p.role::text in ('barber','assistant','cashier','manager')) then
    raise exception 'الموظف غير موجود'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 10000000 then raise exception 'المبلغ غير صحيح'; end if;
  insert into staff_transactions(staff_id, kind, amount, note)
  values (p_staff, 'advance', round(p_amount,2), nullif(btrim(coalesce(p_note,'')),'')) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.cashier_add_move(p_kind text, p_amount numeric, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_d date := p16_today(); v_id bigint;
begin
  if not p16_cash_ops() then raise exception 'غير مصرح'; end if;
  if exists (select 1 from cash_closings c where c.day = v_d) then raise exception 'اليوم اتقفل — مينفعش تسجل عمليات جديدة'; end if;
  if p_kind not in ('withdraw','deposit') then raise exception 'نوع العملية غير صحيح'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 10000000 then raise exception 'المبلغ غير صحيح'; end if;
  insert into cash_moves(day, kind, amount, note) values (v_d, p_kind, round(p_amount,2), nullif(btrim(coalesce(p_note,'')),'')) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

revoke all on function public.p16_cash_ops() from public, anon, authenticated;
revoke all on function public.p16_today() from public, anon, authenticated;
revoke all on function public.cashier_board() from public, anon;
revoke all on function public.cashier_add_expense(text,numeric,text,text) from public, anon;
revoke all on function public.cashier_add_advance(uuid,numeric,text) from public, anon;
revoke all on function public.cashier_add_move(text,numeric,text) from public, anon;
grant execute on function public.cashier_board() to authenticated;
grant execute on function public.cashier_add_expense(text,numeric,text,text) to authenticated;
grant execute on function public.cashier_add_advance(uuid,numeric,text) to authenticated;
grant execute on function public.cashier_add_move(text,numeric,text) to authenticated;
