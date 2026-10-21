-- patch_audit_archive.sql — أرشيف كامل لأي حركة (إضافة / تعديل / حذف) + صلاحية حذف للمدير
-- الأرشيف للمالك فقط، ومبيتعدلش ولا بيتمسح (حتى من المالك). آمن للتكرار.

-- 1) جدول الأرشيف
create table if not exists public.audit_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  table_name text not null,
  op text not null check (op in ('insert','update','delete')),
  row_id text,
  actor uuid,
  actor_name text,
  actor_role text,
  summary text,
  changed text[],
  old_data jsonb,
  new_data jsonb
);
create index if not exists audit_log_at_idx on public.audit_log (at desc);
create index if not exists audit_log_tbl_idx on public.audit_log (table_name, at desc);
create index if not exists audit_log_row_idx on public.audit_log (table_name, row_id);
alter table public.audit_log enable row level security;
drop policy if exists "owner reads audit" on public.audit_log;
create policy "owner reads audit" on public.audit_log for select to authenticated using (is_owner());
revoke all on public.audit_log from anon, authenticated;
grant select on public.audit_log to authenticated;

-- مفيش تعديل ولا مسح للأرشيف
create or replace function public.p20_audit_lock() returns trigger language plpgsql as $$
begin raise exception 'الأرشيف للقراءة فقط'; end $$;
drop trigger if exists audit_no_change on public.audit_log;
create trigger audit_no_change before update or delete on public.audit_log for each row execute function public.p20_audit_lock();

-- 2) التريجر العام: بيسجّل مين عمل إيه وقبل/بعد، ومبيوقفش الشغل لو حصل خطأ
create or replace function public.p20_audit() returns trigger language plpgsql security definer set search_path to 'public' as $$
declare j jsonb; o jsonb; n jsonb; ch text[]; v_name text; v_role text; v_sum text; v_id text; v_uid uuid;
begin
  begin
    v_uid := auth.uid();
    if tg_op = 'INSERT' then n := to_jsonb(new); j := n;
    elsif tg_op = 'DELETE' then o := to_jsonb(old); j := o;
    else
      o := to_jsonb(old); n := to_jsonb(new); j := n;
      select array_agg(e.key) into ch from jsonb_each(n) e
       where o -> e.key is distinct from e.value and e.key not in ('updated_at','edited_at','sort_at');
      if ch is null then return null; end if;
      select jsonb_object_agg(k, o -> k), jsonb_object_agg(k, n -> k) into o, n from unnest(ch) k;
    end if;
    v_id := coalesce(j ->> 'id', j ->> 'key', j ->> 'staff_id', j ->> 'day');
    select string_agg(k || '=' || left(j ->> k, 60), ' · ') into v_sum
      from unnest(array['no','name','full_name','note','label','kind','amount','total','price','status','reason','category','key','value','ticket_no','day','paid_amount']) k
     where j ? k and nullif(j ->> k, '') is not null;
    if v_uid is not null then select full_name, role::text into v_name, v_role from profiles where id = v_uid; end if;
    insert into audit_log(table_name, op, row_id, actor, actor_name, actor_role, summary, changed, old_data, new_data)
    values (tg_table_name, lower(tg_op), v_id, v_uid, coalesce(v_name, case when v_uid is null then 'النظام' else '؟' end), coalesce(v_role, case when v_uid is null then 'system' end), v_sum, ch, o, n);
  exception when others then
    raise warning 'audit skipped: %', sqlerrm;
  end;
  return null;
end $$;

-- 3) تشغيله على الجداول المالية والتشغيلية (اللي موجود منها بس)
do $$ declare t text;
begin
  foreach t in array array['invoices','invoice_items','open_invoices','expenses','expense_categories','cash_moves','cash_closings',
    'staff_transactions','salary_payments','staff_settlements','salary_day_adjustments','appointments','appointment_services','attendance',
    'services','products','bundles','bundle_items','customers','profiles','app_settings','staff_pay_profile','staff_shifts','staff_leaves',
    'purchases','purchase_items','supplier_payments','suppliers','stock_movements','loyalty_rewards','loyalty_redemptions','loyalty_ledger',
    'discount_requests','late_rule','staff_targets','staff_target_tiers','staff_target_awards','reviews','assistant_day_pay','assistant_day_wage']
  loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists zz_audit on public.%I', t);
      execute format('create trigger zz_audit after insert or update or delete on public.%I for each row execute function public.p20_audit()', t);
    end if;
  end loop;
end $$;

-- 4) حذف للمدير: الحجوزات/التذاكر + الحضور + حركات الموظفين (سلف/مكافآت/خصومات). الباقي للمالك بس.
do $$ declare d text; n text;
begin
  d := pg_get_functiondef('admin_att_delete(text)'::regprocedure);
  if position('p20_mgr' in d) = 0 then
    n := replace(d, 'if not is_owner() then raise exception ''غير مصرح''; end if;', 'if not is_mgr() then raise exception ''غير مصرح''; end if; /* p20_mgr */');
    if n = d then raise exception 'admin_att_delete: anchor not found'; end if; execute n;
  end if;
  d := pg_get_functiondef('admin_delete_appointment(text)'::regprocedure);
  if position('p20_mgr' in d) = 0 then
    n := replace(d, 'if not is_owner() then raise exception ''غير مصرح''; end if;', 'if not is_mgr() then raise exception ''غير مصرح''; end if; /* p20_mgr */');
    if n = d then raise exception 'admin_delete_appointment: anchor not found'; end if; execute n;
  end if;
  d := pg_get_functiondef('admin_delete_record(text,text)'::regprocedure);
  if position('p20_mgr' in d) = 0 then
    n := replace(d, 'if not is_owner() then raise exception ''غير مصرح''; end if;', 'if not (is_owner() or (is_mgr() and p_table = ''staff_transactions'')) then raise exception ''غير مصرح''; end if; /* p20_mgr */');
    if n = d then raise exception 'admin_delete_record: anchor not found'; end if; execute n;
  end if;
end $$;
