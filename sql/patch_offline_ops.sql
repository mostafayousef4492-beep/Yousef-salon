-- عمليات أوفلاين (المرحلة 1): مصروفات/سحب/إضافة للدرج/سلف + حضور وانصراف الموظفين.
-- بتتنفّذ بعد رجوع النت بنفس دوال النظام الأصلية وبنفس قواعدها، ومعرّف ثابت لكل عملية
-- (لو اتبعتت مرتين ما بتتكررش). آمن لو اتشغّل أكتر من مرة، ومبيغيّر أي بيانات قديمة.
-- ملحوظة: المصروفات/السحب/السلف بتتسجّل في يوم العمل المفتوح وقت المزامنة (زامن قبل قفل اليوم).
--          الحضور والانصراف بيتسجّل بوقته الأصلي مش وقت المزامنة.

create table if not exists public.offline_op_receipts (
  request_id uuid primary key,
  kind text not null,
  created_by uuid,
  response jsonb not null,
  occurred_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.offline_op_receipts enable row level security;
revoke all on public.offline_op_receipts from public, anon, authenticated;

-- 1) المصروفات والسحب والسلف (للكاشير / اللي معاه صلاحية cash_ops)
create or replace function public.cashier_offline_op(p_request_id uuid, p_kind text, p_args jsonb, p_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid := auth.uid(); v_resp jsonb; v_amt numeric;
begin
  if v_user is null or not p16_cash_ops() then raise exception 'غير مصرح'; end if;
  if p_request_id is null or p_args is null or jsonb_typeof(p_args) <> 'object' then raise exception 'بيانات العملية غير مكتملة'; end if;
  perform pg_advisory_xact_lock(hashtextextended('offop:' || p_request_id::text, 0));
  select response into v_resp from offline_op_receipts where request_id = p_request_id and created_by = v_user;
  if found then return v_resp; end if;
  if exists (select 1 from offline_op_receipts where request_id = p_request_id) then raise exception 'معرّف العملية مستخدم بحساب آخر'; end if;
  v_amt := (p_args->>'amount')::numeric;
  if p_kind = 'expense' then
    v_resp := cashier_add_expense(p_args->>'category', v_amt, nullif(p_args->>'note', ''), coalesce(nullif(p_args->>'paid_from', ''), 'drawer'));
  elsif p_kind = 'advance' then
    v_resp := cashier_add_advance((p_args->>'staff')::uuid, v_amt, nullif(p_args->>'note', ''));
  elsif p_kind = 'move' then
    v_resp := cashier_add_move(p_args->>'kind', v_amt, nullif(p_args->>'note', ''));
  else
    raise exception 'نوع العملية غير مدعوم';
  end if;
  insert into offline_op_receipts(request_id, kind, created_by, response, occurred_at)
    values (p_request_id, p_kind, v_user, v_resp, case when p_at <= now() then p_at end);
  return v_resp;
end $$;
revoke all on function public.cashier_offline_op(uuid, text, jsonb, timestamptz) from public, anon;
grant execute on function public.cashier_offline_op(uuid, text, jsonb, timestamptz) to authenticated;

-- 2) الحضور والانصراف من شاشة الحضور (نفس منطق kiosk_att بس بوقت العملية الأصلي)
create or replace function public.kiosk_att_offline(p_token text, p_code text, p_pin text, p_action text, p_at timestamptz, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_p profiles; v_open attendance; v_now timestamp; v_sh staff_shifts; v_late int := 0; v_note text; v_leave boolean;
        v_fails int; v_resp jsonb; v_id bigint;
begin
  if not exists (select 1 from kiosk_devices where active and token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex')) then
    return jsonb_build_object('ok', false, 'device', false, 'msg', 'الجهاز ده مش مصرّح');
  end if;
  if p_request_id is null or p_at is null or p_action not in ('in', 'out') then return jsonb_build_object('ok', false, 'msg', 'بيانات غير مكتملة'); end if;
  perform pg_advisory_xact_lock(hashtextextended('offop:' || p_request_id::text, 0));
  select response into v_resp from offline_op_receipts where request_id = p_request_id;
  if found then return v_resp; end if;
  if p_at > now() + interval '2 minutes' then return jsonb_build_object('ok', false, 'msg', 'وقت العملية في المستقبل'); end if;
  if p_at < now() - interval '36 hours' then return jsonb_build_object('ok', false, 'msg', 'العملية أقدم من 36 ساعة، سجّلها المدير يدوي'); end if;

  p_code := trim(coalesce(p_code, ''));
  delete from kiosk_fails where at < now() - interval '1 day';
  select count(*) into v_fails from kiosk_fails where code = p_code and at > now() - interval '10 minutes';
  if v_fails >= 5 then return jsonb_build_object('ok', false, 'msg', 'محاولات غلط كتير. استنى 10 دقايق أو كلّم المدير'); end if;
  select p.* into v_p from profiles p join staff_pins s on s.staff_id = p.id
   where p.code = p_code and p.role::text not in ('owner', 'customer') and s.pin_hash = crypt(coalesce(p_pin, ''), s.pin_hash) limit 1;
  if v_p.id is null then
    insert into kiosk_fails(code) values (p_code);
    return jsonb_build_object('ok', false, 'msg', 'الكود أو الـ PIN غلط');
  end if;
  delete from kiosk_fails where code = p_code;
  perform pg_advisory_xact_lock(hashtext('kiosk_att:' || v_p.id::text));

  if p_action = 'in' then
    if exists (select 1 from attendance a where a.staff_id = v_p.id
                and a.check_in <= p_at and coalesce(a.check_out, 'infinity'::timestamptz) > p_at) then
      v_resp := jsonb_build_object('ok', false, 'name', v_p.full_name, 'msg', 'مسجل حضور بالفعل في الوقت ده');
      return v_resp;
    end if;
    v_now := p_at at time zone my_tz();
    select exists (select 1 from staff_leaves l where l.staff_id = v_p.id and v_now::date between l.from_date and l.to_date) into v_leave;
    select * into v_sh from staff_shifts where staff_id = v_p.id and weekday = extract(dow from v_now)::int;
    if v_leave then v_note := 'يوم إجازة';
    elsif v_sh.staff_id is not null and v_sh.is_off then v_note := 'يوم إجازة أسبوعية';
    elsif v_sh.staff_id is not null then v_late := greatest(0, floor(extract(epoch from (v_now::time - v_sh.start_time)) / 60)::int); end if;
    insert into attendance(staff_id, check_in, late_min, note, source) values (v_p.id, p_at, v_late, v_note, 'kiosk')
      returning id into v_id;
    v_resp := jsonb_build_object('ok', true, 'name', v_p.full_name, 'id', v_id, 'msg', 'اتسجل حضورك (أوفلاين)' || case when v_late > 0 then ' - متأخر ' || v_late || ' دقيقة' else '' end);
  else
    select * into v_open from attendance a where a.staff_id = v_p.id and a.check_out is null and a.check_in <= p_at order by a.check_in desc limit 1;
    if v_open.id is null then return jsonb_build_object('ok', false, 'name', v_p.full_name, 'msg', 'مفيش حضور مسجل قبل وقت الانصراف ده'); end if;
    if p_at - v_open.check_in > interval '20 hours' then return jsonb_build_object('ok', false, 'name', v_p.full_name, 'msg', 'مدة الشغل أكتر من 20 ساعة، راجع المدير'); end if;
    update attendance set check_out = p_at where id = v_open.id;
    v_resp := jsonb_build_object('ok', true, 'name', v_p.full_name, 'id', v_open.id, 'msg', 'اتسجل انصرافك (أوفلاين)');
  end if;
  insert into offline_op_receipts(request_id, kind, created_by, response, occurred_at) values (p_request_id, 'att_' || p_action, v_p.id, v_resp, p_at);
  return v_resp;
end $$;
revoke all on function public.kiosk_att_offline(text, text, text, text, timestamptz, uuid) from public;
grant execute on function public.kiosk_att_offline(text, text, text, text, timestamptz, uuid) to anon, authenticated;

notify pgrst, 'reload schema';
