-- الدخول المستعجل (زي الطوارئ): الزبون يطلب من تطبيقه أو الإدارة تفتحه للزبون الواقف،
-- بعد موافقة الإدارة التذكرة تقفز لأول الطابور (بعد اللي على الكرسي) وحساب الخدمات بيتضرب ×2 (قابل للتغيير).
-- الإعدادات: urgent_enabled (الافتراضي true) / urgent_multiplier (الافتراضي 2). آمن للتشغيل أكتر من مرة.
-- محتاج patch_queue_v2.sql (موجود عندك).

alter table public.appointments
  add column if not exists is_urgent boolean not null default false,
  add column if not exists urgent_state text,
  add column if not exists urgent_at timestamptz,
  add column if not exists urgent_by uuid;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'appointments_urgent_state_check') then
    alter table public.appointments add constraint appointments_urgent_state_check check (urgent_state is null or urgent_state in ('requested','approved','declined'));
  end if;
end $$;

-- الكاشير عنده صلاحية تعديل الحجوزات، فنمنع تعديل حالة المستعجل غير من الإدارة أو من الدوال دي
create or replace function public.p17_urgent_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('p17.urgent', true), '') = '1' or is_mgr() then return new; end if;
  if tg_op = 'INSERT' then
    if new.is_urgent or new.urgent_state is not null then raise exception 'المستعجل للإدارة بس'; end if;
  elsif new.is_urgent is distinct from old.is_urgent or new.urgent_state is distinct from old.urgent_state then
    raise exception 'المستعجل للإدارة بس';
  end if;
  return new;
end $$;
drop trigger if exists zz_p17_urgent_guard on public.appointments;
create trigger zz_p17_urgent_guard before insert or update of is_urgent, urgent_state on public.appointments
  for each row execute function public.p17_urgent_guard();

-- يحط التذكرة المستعجلة أول الطابور (بعد اللي في الكرسي وبعد أي مستعجل سبقها)
create or replace function public.p17_urgent_place(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare a appointments; v_first timestamptz; v_lastu timestamptz; v_new timestamptz;
begin
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  perform set_config('p17.urgent', '1', true);
  select min(x.sort_at) filter (where not x.is_urgent), max(x.sort_at) filter (where x.is_urgent)
    into v_first, v_lastu
    from appointments x
   where x.barber_id is not distinct from a.barber_id and x.day = a.day and x.period::text = a.period::text
     and x.id <> a.id and x.status::text in ('upcoming', 'checked_in');
  v_new := case when v_lastu is not null then v_lastu + interval '1 millisecond'
                when v_first is not null then v_first - interval '1 second'
                else a.sort_at end;
  update appointments set is_urgent = true, urgent_state = 'approved', urgent_by = auth.uid(), urgent_at = coalesce(urgent_at, now()), sort_at = least(v_new, a.sort_at)
   where id = p_id;
  perform p15_log(p_id, 'urgent_approved', null, '{}'::jsonb);
end $$;
revoke all on function public.p17_urgent_place(bigint) from public, anon, authenticated;

-- الزبون يطلب مستعجل من تطبيقه (حجز جديد النهارده أو ترقية حجزه الحالي) — بيستنى موافقة الإدارة
create or replace function public.request_urgent(p_barber uuid, p_services bigint[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c bigint; v_tz text := my_tz(); v_day date := (now() at time zone my_tz())::date; r jsonb; v_id bigint; a appointments;
        v_mult numeric := p11_cfg_num('urgent_multiplier', 2);
begin
  if not p11_cfg_bool('urgent_enabled', true) then raise exception 'الحجز المستعجل متوقف دلوقتي'; end if;
  if not coalesce((setting('booking_open','true'::jsonb) #>> '{}')::boolean, true) then raise exception 'الحجز متوقف حاليًا'; end if;
  select c.id into v_c from customers c where c.user_id = auth.uid();
  if v_c is null then raise exception 'سجّل بياناتك الأول'; end if;
  if coalesce(array_length(p_services, 1), 0) = 0 then raise exception 'اختار خدمة واحدة على الأقل'; end if;
  if (select count(*) from appointments x where x.customer_id = v_c and x.status::text = 'no_show' and x.day >= v_day - 30) >= 2 then
    raise exception 'الحجز الأونلاين موقوف لحسابك بسبب غياب متكرر. كلّم الصالون'; end if;
  if exists (select 1 from appointments x where x.customer_id = v_c and x.urgent_state = 'requested' and x.status::text = 'upcoming') then
    raise exception 'طلبك المستعجل بالفعل في انتظار موافقة الإدارة'; end if;
  r := p14_make_ticket(v_c, p_barber, v_day, current_period(), p_services, 'upcoming'::appt_status, 'urgent_request');
  v_id := (r->>'id')::bigint;
  select * into a from appointments where id = v_id;
  if a.day <> v_day or a.status::text <> 'upcoming' then raise exception 'عندك حجز شغّال بالفعل ومينفعش يتحول لمستعجل'; end if;
  if a.is_urgent then raise exception 'حجزك مستعجل بالفعل'; end if;
  perform set_config('p17.urgent', '1', true);
  update appointments set urgent_state = 'requested', urgent_at = now() where id = v_id;
  perform p15_log(v_id, 'urgent_requested', null, '{}'::jsonb);
  return jsonb_build_object('id', v_id, 'no', a.ticket_no, 'code', a.ticket_code, 'existing', coalesce((r->>'existing')::boolean, false), 'multiplier', v_mult);
end $$;
revoke all on function public.request_urgent(uuid, bigint[]) from public, anon;
grant execute on function public.request_urgent(uuid, bigint[]) to authenticated;

-- الإدارة توافق أو ترفض الطلب
create or replace function public.decide_urgent(p_id bigint, p_ok boolean)
returns void language plpgsql security definer set search_path = public as $$
declare a appointments;
begin
  if not is_mgr() then raise exception 'الموافقة على المستعجل للإدارة بس'; end if;
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  if a.status::text not in ('upcoming', 'checked_in') then raise exception 'التذكرة دي مبقتش في الانتظار'; end if;
  if p_ok then
    perform p17_urgent_place(p_id);
  else
    perform set_config('p17.urgent', '1', true);
    update appointments set urgent_state = 'declined', urgent_by = auth.uid() where id = p_id;
    perform p15_log(p_id, 'urgent_declined', null, '{}'::jsonb);
  end if;
end $$;
revoke all on function public.decide_urgent(bigint, boolean) from public, anon;
grant execute on function public.decide_urgent(bigint, boolean) to authenticated;

-- الإدارة تحوّل تذكرة موجودة لمستعجل
create or replace function public.make_urgent(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare a appointments;
begin
  if not is_mgr() then raise exception 'المستعجل للإدارة بس'; end if;
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  if a.status::text not in ('upcoming', 'checked_in') then raise exception 'التذكرة دي مبقتش في الانتظار'; end if;
  perform p17_urgent_place(p_id);
end $$;
revoke all on function public.make_urgent(bigint) from public, anon;
grant execute on function public.make_urgent(bigint) to authenticated;

-- الإدارة تفتح تذكرة مستعجلة لزبون واقف قدامها (حاضر ومستعجل على طول)
create or replace function public.admin_urgent_ticket(p_name text, p_phone text, p_barber uuid, p_services bigint[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare j jsonb; v_id bigint; v_day date := (now() at time zone my_tz())::date; a appointments;
begin
  if not is_mgr() then raise exception 'المستعجل للإدارة بس'; end if;
  if not p11_cfg_bool('urgent_enabled', true) then raise exception 'الحجز المستعجل متوقف دلوقتي'; end if;
  if coalesce(array_length(p_services, 1), 0) = 0 then raise exception 'اختار خدمة واحدة على الأقل'; end if;
  j := p14_book_core(p_name, p_phone, p_barber, v_day, current_period(), p_services, 'urgent');
  v_id := (j->'ticket'->>'id')::bigint;
  select * into a from appointments where id = v_id;
  if a.day <> v_day then raise exception 'للزبون ده حجز في يوم تاني'; end if;
  if a.status::text not in ('upcoming', 'checked_in') then raise exception 'التذكرة دي مبقتش في الانتظار'; end if;
  perform p17_urgent_place(v_id);
  if a.status::text = 'upcoming' then update appointments set status = 'checked_in' where id = v_id; end if;
  return jsonb_build_object('ok', true, 'ticket', j->'ticket', 'existing', coalesce((j->>'existing')::boolean, false));
end $$;
revoke all on function public.admin_urgent_ticket(text, text, uuid, bigint[]) from public, anon;
grant execute on function public.admin_urgent_ticket(text, text, uuid, bigint[]) to authenticated;

-- لوحة المستعجل النهارده: الإدارة والكاشير يشوفوا الكل، والحلاق يشوف بتاعه بس
create or replace function public.urgent_board()
returns table(id bigint, ticket_code text, state text, status text, barber_id uuid, barber_name text, customer_name text, services text, urgent_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.id, a.ticket_code, a.urgent_state, a.status::text, a.barber_id, pr.full_name, c.name,
         coalesce((select string_agg(sv.name, ' + ') from appointment_services x join services sv on sv.id = x.service_id where x.appointment_id = a.id), ''),
         a.urgent_at
    from appointments a left join customers c on c.id = a.customer_id left join profiles pr on pr.id = a.barber_id
   where a.day = (now() at time zone my_tz())::date and a.urgent_state in ('requested', 'approved')
     and a.status::text in ('upcoming', 'checked_in', 'in_service')
     and (is_mgr() or has_perm('manage_appts') or can_use_pos() or a.barber_id = auth.uid())
   order by (a.urgent_state = 'requested') desc, a.urgent_at
$$;
revoke all on function public.urgent_board() from public, anon;
grant execute on function public.urgent_board() to authenticated;

-- حالة طلب الزبون المستعجل
create or replace function public.my_urgent()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('id', a.id, 'state', a.urgent_state, 'status', a.status::text, 'multiplier', p11_cfg_num('urgent_multiplier', 2),
           'ahead', p11_ahead(a.id))
    from appointments a join customers c on c.id = a.customer_id
   where c.user_id = auth.uid() and a.urgent_state is not null and a.status::text in ('upcoming', 'checked_in', 'in_service')
   order by a.id desc limit 1), 'null'::jsonb)
$$;
revoke all on function public.my_urgent() from public, anon;
grant execute on function public.my_urgent() to authenticated;

-- رسوم المستعجل: pos_checkout بيضيف بند "رسوم مستعجل" (الخدمات × (المعامل - 1)) لو التذكرة مستعجلة ومتوافق عليها
do $$
declare d text; a text := '  -- قواعد الخصم (بعد معرفة الإجمالي)';
        ins text := E'  declare v_ur numeric; v_um numeric := greatest(p11_cfg_num(''urgent_multiplier'', 2), 1);\n  begin\n    if p_appointment is not null and v_um > 1 and exists (select 1 from appointments x where x.id = p_appointment and x.is_urgent and x.urgent_state = ''approved'') then\n      select coalesce(sum(unit_price * qty), 0) * (v_um - 1) into v_ur from invoice_items where invoice_id = v_inv and item_type = ''service'';\n      if v_ur > 0 then\n        insert into invoice_items(invoice_id, item_type, item_id, name, qty, unit_price) values (v_inv, ''service'', 0, ''رسوم مستعجل (×'' || v_um || '')'', 1, round(v_ur, 2));\n        v_sub := v_sub + round(v_ur, 2);\n      end if;\n    end if;\n  end;\n\n';
begin
  select pg_get_functiondef('public.pos_checkout(bigint,uuid,jsonb,numeric,numeric,text,bigint,bigint,bigint)'::regprocedure) into d;
  if position('urgent_multiplier' in d) > 0 then return; end if;
  if position(a in d) = 0 then raise exception 'pos_checkout مختلفة عن المتوقع، ابعتلي الرسالة دي'; end if;
  execute replace(d, a, ins || a);
end $$;
