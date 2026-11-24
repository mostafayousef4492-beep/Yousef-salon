-- ============================================================================
-- patch_service_profit.sql — ربحية كل خدمة + تصنيف حركات الدرج
--   service_profit(p_from,p_to): لكل خدمة: عدد المرات، الإيراد بعد الخصم، عمولة الصنايعي، المساعد، تكلفة الخامات الفعلية، الربح.
--     • الخصم بيتوزّع على بنود الفاتورة بنسبة سعر كل بند.
--     • عمولة الصنايعي = (البند بعد الخصم − حصة المساعد − الخامات الاختيارية) × نسبته (نسبة الفاتورة الخاصة لو موجودة).
--     • تكلفة الخامات = حركات الخامات المربوطة بالبند فعلاً × تكلفة الخامة الحالية (يعني لو الاستهلاك مش مسجّل هتطلع صفر وبنعلّم الخدمة «مفيش وصفة»).
--     • قراءة بس، للمالك/المدير.
--   cash_moves.category: تصنيف السحب والإضافة (سحب المالك، إيداع بنك، ضخ من المالك، فكة، أخرى).
-- ============================================================================
alter table public.cash_moves add column if not exists category text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'cash_moves_category_chk') then
    alter table public.cash_moves add constraint cash_moves_category_chk
      check (category is null or category in ('owner_draw','bank_deposit','owner_inject','float','other'));
  end if;
end $$;

create or replace function public.service_profit(p_from date, p_to date)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $fn$
declare v_tz text := my_tz(); v_from timestamptz; v_to timestamptz; r jsonb;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'الفترة غير صحيحة'; end if;
  v_from := (p_from::timestamp) at time zone v_tz;
  v_to   := ((p_to + 1)::timestamp) at time zone v_tz;
  with lines as (
    select ii.id, ii.item_id, ii.name, ii.qty, ii.assistant_cut, ii.mat_cost,
           ii.unit_price * ii.qty as gross, i.subtotal, i.discount,
           coalesce(ic.pct, pr.commission_pct, 0) as pct
      from invoice_items ii
      join invoices i on i.id = ii.invoice_id
      left join invoice_commissions ic on ic.invoice_id = i.id
      left join profiles pr on pr.id = i.barber_id
     where ii.item_type = 'service' and ii.item_id <> 0 and i.created_at >= v_from and i.created_at < v_to
  ), calc as (
    select l.*, case when l.subtotal > 0 then l.gross * (1 - coalesce(l.discount, 0) / l.subtotal) else 0 end as net from lines l
  ), mat as (
    select mm.invoice_item_id as id, sum(-mm.qty * m.cost) as cost
      from material_movements mm join materials m on m.id = mm.material_id
     where mm.invoice_item_id in (select id from calc) group by 1
  ), per as (
    select c.item_id, max(c.name) as name, count(*) as n, sum(c.qty) as qty, sum(c.gross) as gross, sum(c.net) as net,
           sum(greatest(c.net - coalesce(c.assistant_cut, 0) - coalesce(c.mat_cost, 0), 0) * c.pct / 100) as commission,
           sum(coalesce(c.assistant_cut, 0)) as assistant, coalesce(sum(mt.cost), 0) as mats
      from calc c left join mat mt on mt.id = c.id group by c.item_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'service_id', per.item_id, 'name', coalesce(s.name, per.name), 'category', s.category, 'price', s.price,
           'n', per.n, 'qty', per.qty, 'gross', round(per.gross, 2), 'net', round(per.net, 2),
           'commission', round(per.commission, 2), 'assistant', round(per.assistant, 2), 'materials', round(per.mats, 2),
           'profit', round(per.net - per.commission - per.assistant - per.mats, 2),
           'has_recipe', exists(select 1 from service_materials sm where sm.service_id = per.item_id))
         order by (per.net - per.commission - per.assistant - per.mats) desc), '[]'::jsonb)
    into r from per left join services s on s.id = per.item_id;
  return jsonb_build_object('from', p_from, 'to', p_to, 'rows', r);
end $fn$;
revoke all on function public.service_profit(date, date) from public, anon;
grant execute on function public.service_profit(date, date) to authenticated;
