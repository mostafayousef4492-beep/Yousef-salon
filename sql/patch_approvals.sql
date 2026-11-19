-- مركز موافقات المالك: طلبات (إلغاء فاتورة / طلب حر) من الكاشير والمدير، والمالك بيقرر.
-- الإلغاء بيتنفّذ بنفس دالة النظام الأصلية admin_void_invoice (وبكل قواعدها وأرشيفها)، مش بديل عنها.
-- آمن لو اتشغّل أكتر من مرة، ومبيغيّر أي بيانات قديمة. طلبات الخصم القديمة (discount_requests) زي ما هي،
-- وبتظهر في نفس الشاشة عن طريق approvals_inbox().

create table if not exists public.approval_requests (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('void_invoice', 'custom')),
  ref text,
  title text not null,
  reason text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  requested_by uuid not null,
  decided_by uuid,
  decided_at timestamptz,
  decision_note text,
  result jsonb,
  created_at timestamptz not null default now()
);
create unique index if not exists approval_one_pending on public.approval_requests(kind, ref) where status = 'pending' and ref is not null;
alter table public.approval_requests enable row level security;
drop policy if exists approval_read on public.approval_requests;
create policy approval_read on public.approval_requests for select to authenticated using (is_owner() or requested_by = auth.uid());
revoke all on public.approval_requests from public, anon, authenticated;
grant select on public.approval_requests to authenticated;

-- إرسال الطلب (كاشير أو مدير)
create or replace function public.approval_request(p_kind text, p_ref text, p_title text, p_reason text)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id bigint; v_title text := left(trim(coalesce(p_title, '')), 160); v_inv record;
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
  begin
    perform push_send(push_staff_ids(array['owner'], null, null), 'طلب موافقة جديد', v_title, 'apr', 'apr_' || v_id, false);
  exception when others then null;
  end;
  return v_id;
end $$;

-- قرار المالك
create or replace function public.approval_decide(p_id bigint, p_ok boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare r approval_requests; v_res jsonb := null;
begin
  if not is_owner() then raise exception 'القرار للمالك بس'; end if;
  select * into r from approval_requests where id = p_id for update;
  if not found or r.status <> 'pending' then raise exception 'الطلب اتقفل أو مش موجود'; end if;
  if p_ok and r.kind = 'void_invoice' then
    v_res := admin_void_invoice(r.ref, false);
    if coalesce((v_res->>'needs_force')::boolean, false) then
      raise exception 'يوم الفاتورة مقفول (%). افتح اليوم أو الغي من شاشة الفواتير بتأكيد القفل', v_res->>'day';
    end if;
  end if;
  update approval_requests set status = case when p_ok then 'approved' else 'rejected' end, decided_by = auth.uid(),
    decided_at = now(), decision_note = left(nullif(trim(coalesce(p_note, '')), ''), 300), result = v_res where id = p_id;
  begin
    perform push_send(array[r.requested_by], case when p_ok then 'اتوافق على طلبك ✓' else 'طلبك اترفض' end, r.title, 'apr', 'apr_' || p_id, false);
  exception when others then null;
  end;
  return jsonb_build_object('ok', true, 'result', v_res);
end $$;

-- صاحب الطلب يسحبه
create or replace function public.approval_cancel(p_id bigint)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update approval_requests set status = 'cancelled', decided_at = now() where id = p_id and requested_by = auth.uid() and status = 'pending';
  if not found then raise exception 'الطلب مش موجود أو اتقفل'; end if;
end $$;

-- صندوق الموافقات الموحّد: طلبات الخصم + طلبات الموافقة + آخر القرارات
create or replace function public.approvals_inbox()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_owner boolean := is_owner(); v_disc boolean := can_approve_disc();
begin
  if auth.uid() is null then raise exception 'غير مصرح'; end if;
  return jsonb_build_object(
    'owner', v_owner,
    'discounts', case when v_disc then coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'chair', d.chair, 'pct', d.pct, 'subtotal', d.subtotal,
        'reason', d.reason, 'by', p.full_name, 'at', d.created_at) order by d.created_at)
        from discount_requests d left join profiles p on p.id = d.requested_by where d.status = 'pending'), '[]'::jsonb) else '[]'::jsonb end,
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'ref', a.ref, 'title', a.title, 'reason', a.reason,
        'by', p.full_name, 'at', a.created_at, 'mine', a.requested_by = auth.uid()) order by a.created_at)
        from approval_requests a left join profiles p on p.id = a.requested_by
        where a.status = 'pending' and (v_owner or a.requested_by = auth.uid())), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(x order by x->>'at' desc) from (
        select jsonb_build_object('src', 'req', 'title', a.title, 'status', a.status, 'by', p.full_name, 'note', a.decision_note, 'at', a.decided_at) x
          from approval_requests a left join profiles p on p.id = a.requested_by
         where a.status <> 'pending' and (v_owner or a.requested_by = auth.uid()) order by a.decided_at desc nulls last limit 20) t), '[]'::jsonb));
end $$;

do $$
declare f text;
begin
  foreach f in array array['approval_request(text,text,text,text)', 'approval_decide(bigint,boolean,text)', 'approval_cancel(bigint)', 'approvals_inbox()']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;

-- التدقيق على الجدول الجديد بنفس آلية الأرشيف الموجودة
do $$
begin
  if to_regprocedure('public.p20_audit()') is not null and not exists (select 1 from pg_trigger where tgname = 'zz_audit' and tgrelid = 'public.approval_requests'::regclass) then
    create trigger zz_audit after insert or update or delete on public.approval_requests for each row execute function public.p20_audit();
  end if;
end $$;

notify pgrst, 'reload schema';
