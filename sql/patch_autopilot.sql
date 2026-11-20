-- التشغيل الذاتي (Autopilot): السيستم يقرر لوحده في حدود سياسة المالك حددها مرة واحدة، ويرجعله بس في الاستثناءات.
-- مهم: الميزة مقفولة افتراضيًا (enabled=false) — مفيش أي سلوك بيتغيّر قبل ما المالك يشغّلها من شاشة «التشغيل الذاتي».
-- القرارات التلقائية:
--   1) طلب خصم فوق حدّ الكاشير: بيتوافق عليه تلقائيًا لو النسبة ≤ حدّ السياسة وإجمالي الخصومات التلقائية النهارده ≤ السقف اليومي.
--   2) طلب إلغاء فاتورة: بيتنفّذ تلقائيًا بس لو الفاتورة بتاعت نفس الموظف، حديثة (≤ دقايق السياسة)، قيمتها ≤ الحد، واليوم مش مقفول،
--      ولم يتجاوز عدد الإلغاءات التلقائية اليومي. غير كده بيستنى قرار المالك.
--   3) أي طلب مستني أكتر من ~20 دقيقة: تذكير للمالك والمدير (مرة واحدة).
-- كل قرار تلقائي بيتسجّل في «سجل التشغيل الذاتي» ويوصل للمالك إشعار. لا خصم رواتب ولا جزاءات ولا تغيير عمولات هنا.
-- بيحتاج patch_approvals.sql متشغّل قبله. آمن لو اتشغّل أكتر من مرة، ومبيغيّر أي بيانات قديمة.

create table if not exists public.autopilot_policy (
  id int primary key default 1 check (id = 1),
  enabled boolean not null default false,
  disc_auto boolean not null default true,
  disc_auto_max_pct numeric not null default 15 check (disc_auto_max_pct between 0 and 100),
  disc_auto_daily_total numeric not null default 300 check (disc_auto_daily_total >= 0),
  void_auto boolean not null default true,
  void_auto_minutes int not null default 30 check (void_auto_minutes between 0 and 240),
  void_auto_max_total numeric not null default 300 check (void_auto_max_total >= 0),
  void_auto_daily_max int not null default 2 check (void_auto_daily_max between 0 and 50),
  updated_by uuid,
  updated_at timestamptz not null default now()
);
insert into public.autopilot_policy(id) values (1) on conflict do nothing;
alter table public.autopilot_policy enable row level security;
revoke all on public.autopilot_policy from public, anon, authenticated;

create table if not exists public.autopilot_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  kind text not null,
  ref text,
  decision text not null,
  detail jsonb
);
create index if not exists autopilot_log_at on public.autopilot_log(at desc);
alter table public.autopilot_log enable row level security;
revoke all on public.autopilot_log from public, anon, authenticated;

-- السماح لقرار النظام التلقائي بتنفيذ الإلغاء (بنفس دالة الإلغاء الأصلية وكل أرشيفها). مرة واحدة بس.
do $$
declare v_def text; v_new text;
begin
  select pg_get_functiondef('public.admin_void_invoice(text,boolean)'::regprocedure) into v_def;
  if v_def like '%app.autopilot%' then return; end if;
  v_new := replace(v_def, 'if not is_owner() then raise exception ''غير مصرح''; end if;',
                   'if not (is_owner() or coalesce(current_setting(''app.autopilot'', true), '''') = ''1'') then raise exception ''غير مصرح''; end if;');
  assert v_new <> v_def, 'admin_void_invoice: anchor not found';
  execute v_new;
end $$;

-- طلب الخصم: نفس الدالة الأصلية + محاولة قرار تلقائي بعد الإدخال
create or replace function public.request_discount(p_chair integer, p_pct numeric, p_subtotal numeric, p_reason text)
returns bigint language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  if not can_use_pos() then raise exception 'غير مصرح'; end if;
  if p_pct <= 0 or p_pct > p11_cfg_num('disc_global_max_pct', 20) then raise exception 'الخصم ده فوق الحد الأقصى في النظام'; end if;
  insert into discount_requests(chair, pct, subtotal, reason) values (p_chair, p_pct, p_subtotal, left(coalesce(p_reason, ''), 200)) returning id into v;
  begin perform autopilot_try_discount(v);
  exception when others then insert into autopilot_log(kind, ref, decision, detail) values ('discount', v::text, 'error', jsonb_build_object('err', sqlerrm));
  end;
  return v;
end $$;

create or replace function public.autopilot_try_discount(p_id bigint)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare pol autopilot_policy; r discount_requests; v_used numeric; v_amt numeric; v_tz text := my_tz();
begin
  select * into pol from autopilot_policy where id = 1;
  if not pol.enabled or not pol.disc_auto then return false; end if;
  select * into r from discount_requests where id = p_id for update;
  if not found or r.status <> 'pending' then return false; end if;
  v_amt := round(coalesce(r.subtotal, 0) * r.pct / 100, 2);
  select coalesce(sum(round(coalesce(subtotal, 0) * pct / 100, 2)), 0) into v_used from discount_requests d
   where d.status in ('approved', 'used') and d.decided_by is null and (d.decided_at at time zone v_tz)::date = (now() at time zone v_tz)::date;
  if r.pct > pol.disc_auto_max_pct or v_used + v_amt > pol.disc_auto_daily_total then
    insert into autopilot_log(kind, ref, decision, detail) values ('discount', p_id::text, 'escalated',
      jsonb_build_object('pct', r.pct, 'amount', v_amt, 'used_today', v_used, 'why', case when r.pct > pol.disc_auto_max_pct then 'النسبة فوق حد السياسة' else 'السقف اليومي للخصومات التلقائية' end));
    return false;
  end if;
  update discount_requests set status = 'approved', decided_by = null, decided_at = now() where id = p_id;
  insert into autopilot_log(kind, ref, decision, detail) values ('discount', p_id::text, 'approved', jsonb_build_object('pct', r.pct, 'amount', v_amt, 'chair', r.chair, 'reason', r.reason));
  begin
    perform push_send(push_staff_ids(array['owner'], null, null), 'خصم اتوافق عليه تلقائي', r.pct || '% (' || v_amt || ' ج) كرسي ' || coalesce(r.chair::text, '-'), 'auto', 'auto_d' || p_id, false);
  exception when others then null;
  end;
  return true;
end $$;

-- طلب الإلغاء: نفس دالة patch_approvals + محاولة قرار تلقائي بعد الإدخال
create or replace function public.approval_request(p_kind text, p_ref text, p_title text, p_reason text)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id bigint; v_title text := left(trim(coalesce(p_title, '')), 160); v_inv record; v_auto boolean := false;
begin
  if auth.uid() is null or not (can_use_pos() or is_mgr()) then raise exception 'غير مصرح'; end if;
  if p_kind not in ('void_invoice', 'custom') then raise exception 'نوع الطلب غير مدعوم'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'اكتب السبب'; end if;
  if p_kind = 'void_invoice' then
    select no, total into v_inv from invoices where id::text = p_ref;
    if not found then raise exception 'الفاتورة مش موجودة'; end if;
    v_title := 'إلغاء فاتورة رقم ' || v_inv.no || ' (' || v_inv.total || ' ج)';
  elsif v_title = '' then raise exception 'اكتب عنوان الطلب'; end if;
  begin
    insert into approval_requests(kind, ref, title, reason, requested_by)
      values (p_kind, nullif(p_ref, ''), v_title, left(trim(p_reason), 400), auth.uid()) returning id into v_id;
  exception when unique_violation then raise exception 'فيه طلب مفتوح بالفعل للفاتورة دي';
  end;
  if p_kind = 'void_invoice' then
    begin v_auto := autopilot_try_void(v_id);
    exception when others then insert into autopilot_log(kind, ref, decision, detail) values ('void', v_id::text, 'error', jsonb_build_object('err', sqlerrm));
    end;
  end if;
  if not v_auto then
    begin
      perform push_send(push_staff_ids(array['owner'], null, null), 'طلب موافقة جديد', v_title, 'apr', 'apr_' || v_id, false);
    exception when others then null;
    end;
  end if;
  return v_id;
end $$;

create or replace function public.autopilot_try_void(p_id bigint)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare pol autopilot_policy; a approval_requests; i invoices; v_n int; v_res jsonb; v_tz text := my_tz();
begin
  select * into pol from autopilot_policy where id = 1;
  if not pol.enabled or not pol.void_auto then return false; end if;
  select * into a from approval_requests where id = p_id for update;
  if not found or a.status <> 'pending' or a.kind <> 'void_invoice' then return false; end if;
  select * into i from invoices where id::text = a.ref;
  if not found then return false; end if;
  select count(*) into v_n from approval_requests x
   where x.kind = 'void_invoice' and x.status = 'approved' and x.decided_by is null and (x.decided_at at time zone v_tz)::date = (now() at time zone v_tz)::date;
  if i.cashier_id is distinct from a.requested_by or i.created_at < now() - make_interval(mins => pol.void_auto_minutes)
     or i.total > pol.void_auto_max_total or v_n >= pol.void_auto_daily_max
     or exists (select 1 from cash_closings c where c.day = (i.created_at at time zone v_tz)::date) then
    insert into autopilot_log(kind, ref, decision, detail) values ('void', p_id::text, 'escalated',
      jsonb_build_object('invoice_no', i.no, 'total', i.total, 'why', case
        when i.cashier_id is distinct from a.requested_by then 'الفاتورة مش بتاعة طالب الإلغاء'
        when i.created_at < now() - make_interval(mins => pol.void_auto_minutes) then 'الفاتورة أقدم من حد السياسة'
        when i.total > pol.void_auto_max_total then 'قيمة الفاتورة فوق الحد'
        when v_n >= pol.void_auto_daily_max then 'وصلنا للحد اليومي للإلغاء التلقائي'
        else 'يوم الفاتورة مقفول' end));
    return false;
  end if;
  perform set_config('app.autopilot', '1', true);
  v_res := admin_void_invoice(a.ref, false);
  perform set_config('app.autopilot', '', true);
  if coalesce((v_res->>'deleted')::boolean, false) is not true then return false; end if;
  update approval_requests set status = 'approved', decided_by = null, decided_at = now(), decision_note = 'تلقائي حسب السياسة', result = v_res where id = p_id;
  insert into autopilot_log(kind, ref, decision, detail) values ('void', p_id::text, 'approved', jsonb_build_object('invoice_no', i.no, 'total', i.total, 'reason', a.reason, 'by', a.requested_by));
  begin
    perform push_send(push_staff_ids(array['owner'], null, null), 'فاتورة اتلغت تلقائي', a.title || ' — ' || a.reason, 'auto', 'auto_v' || p_id, false);
    perform push_send(array[a.requested_by], 'اتلغت الفاتورة ✓', a.title, 'apr', 'apr_' || p_id, false);
  exception when others then null;
  end;
  return true;
end $$;

-- تذكير بالطلبات المتأخرة (للمالك والمدير) — مرة واحدة لكل طلب
create or replace function public.autopilot_nudge()
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare n int := 0; r record;
begin
  for r in select 'd' k, d.id, 'خصم ' || d.pct || '% كرسي ' || coalesce(d.chair::text, '-') t from discount_requests d
            where d.status = 'pending' and d.created_at < now() - interval '20 minutes'
              and not exists (select 1 from autopilot_log l where l.kind = 'nudge' and l.ref = 'd' || d.id)
           union all
           select 'a', a.id, a.title from approval_requests a
            where a.status = 'pending' and a.created_at < now() - interval '20 minutes'
              and not exists (select 1 from autopilot_log l where l.kind = 'nudge' and l.ref = 'a' || a.id)
  loop
    insert into autopilot_log(kind, ref, decision) values ('nudge', r.k || r.id, 'sent');
    begin perform push_send(push_staff_ids(array['owner', 'manager'], null, null), 'طلب مستني قرار من 20 دقيقة', r.t, 'apr', 'nudge_' || r.k || r.id, false);
    exception when others then null;
    end;
    n := n + 1;
  end loop;
  return n;
end $$;

-- قراءة وحفظ السياسة (المالك بس يغيّر، والمدير يقرأ)
create or replace function public.autopilot_get()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  return jsonb_build_object('policy', (select to_jsonb(p) - 'updated_by' from autopilot_policy p where id = 1), 'owner', is_owner(),
    'log', coalesce((select jsonb_agg(to_jsonb(l) order by l.at desc) from (select at, kind, ref, decision, detail from autopilot_log where kind <> 'nudge' order by at desc limit 40) l), '[]'::jsonb));
end $$;

create or replace function public.autopilot_save(p_policy jsonb)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not is_owner() then raise exception 'السياسة للمالك بس'; end if;
  update autopilot_policy set
    enabled = coalesce((p_policy->>'enabled')::boolean, enabled),
    disc_auto = coalesce((p_policy->>'disc_auto')::boolean, disc_auto),
    disc_auto_max_pct = coalesce((p_policy->>'disc_auto_max_pct')::numeric, disc_auto_max_pct),
    disc_auto_daily_total = coalesce((p_policy->>'disc_auto_daily_total')::numeric, disc_auto_daily_total),
    void_auto = coalesce((p_policy->>'void_auto')::boolean, void_auto),
    void_auto_minutes = coalesce((p_policy->>'void_auto_minutes')::int, void_auto_minutes),
    void_auto_max_total = coalesce((p_policy->>'void_auto_max_total')::numeric, void_auto_max_total),
    void_auto_daily_max = coalesce((p_policy->>'void_auto_daily_max')::int, void_auto_daily_max),
    updated_by = auth.uid(), updated_at = now()
   where id = 1;
  insert into autopilot_log(kind, ref, decision, detail) values ('policy', null, 'changed', p_policy);
end $$;

do $$
declare f text;
begin
  foreach f in array array['autopilot_get()', 'autopilot_save(jsonb)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  foreach f in array array['autopilot_try_discount(bigint)', 'autopilot_try_void(bigint)', 'autopilot_nudge()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  if exists (select 1 from cron.job where jobname = 'autopilot-nudge') then perform cron.unschedule('autopilot-nudge'); end if;
  perform cron.schedule('autopilot-nudge', '*/15 * * * *', 'select public.autopilot_nudge()');
end $$;

do $$
begin
  if to_regprocedure('public.p20_audit()') is not null and not exists (select 1 from pg_trigger where tgname = 'zz_audit' and tgrelid = 'public.autopilot_policy'::regclass) then
    create trigger zz_audit after insert or update or delete on public.autopilot_policy for each row execute function public.p20_audit();
  end if;
end $$;

notify pgrst, 'reload schema';
