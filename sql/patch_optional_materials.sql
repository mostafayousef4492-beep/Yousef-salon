-- ============================================================================
-- patch_optional_materials.sql — خامات اختيارية مع الخدمة (موس بلاستيك، فوطة طبية...)
--   • الخامة الاختيارية بتتخصم من المخزون، وتمنها (التكلفة × الكمية) بيتخصم من مبلغ الفاتورة الأول،
--     وبعدين الصنايعي بياخد نسبته من الباقي (عمولة الحلاق = (الإجمالي − المساعد − خدمة خارج المحل − تكلفة الخامات الاختيارية) × النسبة).
--   • سعر الفاتورة للعميل ما بيتغيّرش.
--   • كل نتايج الحسابات لو مفيش خامات اختيارية بتفضل زي ما هي بالظبط (الملف بيتأكد من كده قبل ما يخلّص، ولو في فرق بيتلغي كله).
--   • نسخة من الدوال القديمة محفوظة في جدول _func_backup_optmat للرجوع.
-- ============================================================================
do $mig$
declare
  v_names text[] := array['pos_checkout','staff_summary','staff_cuts_list','staff_statement','export_report','full_report','report_data','owner_dashboard'];
  n text; d text; cnt int; exp_cnt int;
  v_from timestamptz := '2026-09-01'::timestamptz; v_to timestamptz := now();
  b jsonb := '{}'::jsonb; a jsonb := '{}'::jsonb; k text; v jsonb;
begin
  -- 1) الأعمدة
  alter table public.materials add column if not exists optional boolean not null default false;
  alter table public.materials add column if not exists opt_qty numeric not null default 1;
  alter table public.invoice_items add column if not exists mat_cost numeric(12,2) not null default 0;
  alter table public.open_invoices add column if not exists mats jsonb not null default '[]'::jsonb;

  -- 2) نسخة احتياطية من الدوال القديمة
  create table if not exists public._func_backup_optmat(name text, def text, saved_at timestamptz default now());
  alter table public._func_backup_optmat enable row level security;
  insert into public._func_backup_optmat(name, def)
    select p.proname, pg_get_functiondef(p.oid) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any(v_names)
      and not exists (select 1 from public._func_backup_optmat x where x.name = p.proname);

  -- 3) لقطة قبل التعديل (نفس اللي هنقارن بيه بعد التعديل)
  perform set_config('request.jwt.claims', '{"sub":"6286251b-312a-4a8b-aa2c-7941bd3b481f","role":"authenticated"}', true);
  b := jsonb_build_object(
    'summary',   (select coalesce(jsonb_agg(to_jsonb(x) order by p.id), '[]') from profiles p cross join lateral staff_summary(p.id, v_from, v_to) x where p.role::text in ('barber','assistant')),
    'cuts',      (select coalesce(jsonb_agg(to_jsonb(c) order by p.id, c.invoice_id), '[]') from profiles p cross join lateral staff_cuts_list(p.id, v_from, v_to) c where p.role::text = 'barber'),
    'statement', (select coalesce(jsonb_agg(staff_statement(p.id, v_from, v_to) order by p.id), '[]') from profiles p where p.role::text in ('barber','assistant')),
    'full',      full_report(v_from, v_to),
    'rdata',     report_data(v_from, v_to),
    'dash_day',  owner_dashboard(v_from::date, v_to::date, 'day'),
    'dash_month',owner_dashboard(v_from::date, v_to::date, 'month'));

  -- 4) pos_checkout: عناصر type='material' (خامات اختيارية) بتتسجّل على أول خدمة في الفاتورة
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pos_checkout';
  if position('declare it jsonb;' in d) = 0 or position('if v_qty < 1 then raise exception ''كمية غير صحيحة''; end if;' in d) = 0 then raise exception 'pos_checkout: مفيش anchor'; end if;
  d := replace(d, 'declare it jsonb;', 'declare v_mat materials; v_msi bigint; it jsonb;');
  d := replace(d, 'if v_qty < 1 then raise exception ''كمية غير صحيحة''; end if;',
    'if v_qty < 1 then raise exception ''كمية غير صحيحة''; end if;
    if it->>''type'' = ''material'' then
      select * into v_mat from materials where id = (it->>''id'')::bigint and active and optional;
      if v_mat.id is null then raise exception ''خامة اختيارية غير صالحة''; end if;
      select min(x.id) into v_msi from invoice_items x where x.invoice_id = v_inv and x.item_type = ''service'' and x.item_id <> 0;
      if v_msi is null then raise exception ''الخامات الاختيارية بتتضاف مع خدمة بس''; end if;
      insert into material_movements(material_id, qty, reason, invoice_id, invoice_item_id, created_by) values (v_mat.id, -(v_mat.opt_qty * v_qty), ''service_option'', v_inv, v_msi, auth.uid());
      update invoice_items set mat_cost = mat_cost + round(v_mat.cost * v_mat.opt_qty * v_qty, 2) where id = v_msi;
      continue;
    end if;');
  execute d;

  -- 5) عمولة الصنايعي: نطرح تكلفة الخامات الاختيارية قبل النسبة
  -- staff_summary
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'staff_summary';
  n := '), 0)) * coalesce(v_p,0) / 100;';
  if (length(d) - length(replace(d, n, ''))) / length(n) <> 1 then raise exception 'staff_summary: anchor'; end if;
  d := replace(d, n, '), 0) - coalesce((select sum(ii.mat_cost) from invoice_items ii join invoices i on i.id = ii.invoice_id where i.barber_id = p_staff and i.created_at >= p_from and i.created_at < p_to), 0)) * coalesce(v_p,0) / 100;');
  execute d;
  -- staff_cuts_list
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'staff_cuts_list';
  n := '), 0)) * v_pct / 100 end';
  if (length(d) - length(replace(d, n, ''))) / length(n) <> 1 then raise exception 'staff_cuts_list: anchor'; end if;
  d := replace(d, n, '), 0) - coalesce((select sum(ii.mat_cost) from invoice_items ii where ii.invoice_id = i.id), 0)) * v_pct / 100 end');
  execute d;
  -- staff_statement
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'staff_statement';
  n := 'from invoice_items ii where ii.invoice_id = i.id), 0)) * coalesce(pr.commission_pct, 0) / 100, 2)';
  if (length(d) - length(replace(d, n, ''))) / length(n) <> 1 then raise exception 'staff_statement: anchor'; end if;
  d := replace(d, n, 'from invoice_items ii where ii.invoice_id = i.id), 0) - coalesce((select sum(ii.mat_cost) from invoice_items ii where ii.invoice_id = i.id), 0)) * coalesce(pr.commission_pct, 0) / 100, 2)');
  execute d;
  -- export_report (2) / full_report (1) / report_data (2)
  foreach n in array array['export_report','full_report','report_data'] loop
    select pg_get_functiondef(p.oid) into d from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = n;
    select count(*) into cnt from regexp_matches(d, 'coalesce\(\(select sum\(x\.assistant_cut\) from invoice_items x where x\.invoice_id = (?:i|invoices)\.id\), ?0\)', 'g');
    exp_cnt := case n when 'full_report' then 1 else 2 end;
    if cnt <> exp_cnt then raise exception '%: متوقع عدد مواضع تاني (لقيت %)', n, cnt; end if;
    d := regexp_replace(d, 'coalesce\(\(select sum\(x\.assistant_cut\) from invoice_items x where x\.invoice_id = (i|invoices)\.id\), ?0\)',
      '(coalesce((select sum(x.assistant_cut) from invoice_items x where x.invoice_id = \1.id), 0) + coalesce((select sum(x.mat_cost) from invoice_items x where x.invoice_id = \1.id), 0))', 'g');
    execute d;
  end loop;
  -- owner_dashboard
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'owner_dashboard';
  if position('select i.total, i.subtotal, i.discount, i.customer_id,' in d) = 0
     or (length(d) - length(replace(d, 'sum(total * pct / 100)', ''))) / length('sum(total * pct / 100)') <> 2
     or position('sum(i.total * coalesce(ic.pct, p.commission_pct, 0) / 100)' in d) = 0 then raise exception 'owner_dashboard: anchor'; end if;
  d := replace(d, 'select i.total, i.subtotal, i.discount, i.customer_id,', 'select i.total, i.subtotal, i.discount, i.customer_id, coalesce((select sum(mx.mat_cost) from invoice_items mx where mx.invoice_id = i.id), 0) as mc,');
  d := replace(d, 'sum(total * pct / 100)', 'sum((total - mc) * pct / 100)');
  d := replace(d, 'sum(i.total * coalesce(ic.pct, p.commission_pct, 0) / 100)', 'sum((i.total - coalesce((select sum(mx.mat_cost) from invoice_items mx where mx.invoice_id = i.id), 0)) * coalesce(ic.pct, p.commission_pct, 0) / 100)');
  execute d;

  -- 6) لقطة بعد التعديل لازم تساوي اللي قبل (لأن مفيش خامات اختيارية لسه)
  a := jsonb_build_object(
    'summary',   (select coalesce(jsonb_agg(to_jsonb(x) order by p.id), '[]') from profiles p cross join lateral staff_summary(p.id, v_from, v_to) x where p.role::text in ('barber','assistant')),
    'cuts',      (select coalesce(jsonb_agg(to_jsonb(c) order by p.id, c.invoice_id), '[]') from profiles p cross join lateral staff_cuts_list(p.id, v_from, v_to) c where p.role::text = 'barber'),
    'statement', (select coalesce(jsonb_agg(staff_statement(p.id, v_from, v_to) order by p.id), '[]') from profiles p where p.role::text in ('barber','assistant')),
    'full',      full_report(v_from, v_to),
    'rdata',     report_data(v_from, v_to),
    'dash_day',  owner_dashboard(v_from::date, v_to::date, 'day'),
    'dash_month',owner_dashboard(v_from::date, v_to::date, 'month'));
  for k in select jsonb_object_keys(b) loop
    if b->k is distinct from a->k then raise exception 'فرق في نتيجة % بعد التعديل، اتلغى كل حاجة', k; end if;
  end loop;
end $mig$;

-- 7) تحديد الخامة كاختيارية (للمدير / صلاحية المخزون)
create or replace function public.material_set_optional(p_id bigint, p_optional boolean, p_qty numeric default 1)
returns void language plpgsql security definer set search_path to 'public' as $fn$
begin
  if not (is_mgr() or has_perm('restock')) then raise exception 'غير مصرح'; end if;
  if coalesce(p_qty, 1) <= 0 or coalesce(p_qty, 1) > 100000 then raise exception 'الكمية غلط'; end if;
  update materials set optional = coalesce(p_optional, false), opt_qty = coalesce(p_qty, 1) where id = p_id;
  if not found then raise exception 'الخامة مش موجودة'; end if;
end $fn$;
revoke all on function public.material_set_optional(bigint, boolean, numeric) from public, anon;
grant execute on function public.material_set_optional(bigint, boolean, numeric) to authenticated;
