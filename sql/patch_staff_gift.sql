-- patch_staff_gift.sql — هدية عينية كنوع قطاع في عجلة الموظفين (مثلاً: وجبة غداء، شاي مجاني، يوم إجازة)
-- القطاع من نوع «هدية»: الاسم هو الجايزة والقيمة مابتتحسبش فلوس. لما حد يكسبها بيوصل المدير إشعار يسلّمها.
-- مابتتسجّلش مكافأة مالية ولا نقاط. لازم patch_staff_wheel.sql متشغّل. آمن للتشغيل أكتر من مرة.
do $$ declare c text; begin
  select conname into c from pg_constraint where conrelid = 'public.staff_wheel_slices'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%points%' and pg_get_constraintdef(oid) ilike '%kind%';
  if c is not null then execute format('alter table public.staff_wheel_slices drop constraint %I', c); end if;
  alter table public.staff_wheel_slices add constraint staff_wheel_slices_kind_chk check (kind in ('cash','points','none','gift'));
exception when duplicate_object then null; end $$;

create or replace function public.staff_ch_spin(p_log bigint) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare l staff_ch_log; s staff_wheel_slices; v_tot int; v_pick int; v_acc int := 0; v_day date := p_sw_day();
        v_max int := p_ref_cfg('staff_wheel_day_max',2)::int; v_cap numeric := p_ref_cfg('staff_wheel_cash_month',500);
        v_month numeric; v_label text; v_kind text; v_val numeric; v_sid bigint;
begin
  if not p11_cfg_bool('staff_wheel_on', false) then raise exception 'عجلة الموظفين مش شغّالة دلوقتي'; end if;
  select * into l from staff_ch_log where id = p_log for update;
  if not found or l.staff_id <> auth.uid() then raise exception 'غير مصرح'; end if;
  if l.status <> 'confirmed' then raise exception 'لازم المدير أو الكاشير يأكّد التحدي الأول'; end if;
  if (select count(*) from staff_ch_log where staff_id = auth.uid() and day = v_day and status = 'spun') >= v_max then raise exception 'خلّصت لفات النهارده'; end if;
  select coalesce(sum(weight),0) into v_tot from staff_wheel_slices where active and weight > 0;
  if v_tot <= 0 then raise exception 'العجلة مفيهاش جوايز، كلّم المدير'; end if;
  v_pick := floor(random() * v_tot)::int;
  for s in select * from staff_wheel_slices where active and weight > 0 order by sort, id loop
    v_acc := v_acc + s.weight;
    if v_pick < v_acc then exit; end if;
  end loop;
  v_label := s.label; v_kind := s.kind; v_val := s.value; v_sid := s.id;
  if v_kind = 'cash' then
    select coalesce(sum(prize_value),0) into v_month from staff_ch_log where prize_kind = 'cash' and spun_at >= date_trunc('month', now() at time zone my_tz()) at time zone my_tz();
    if v_val <= 0 or v_month + v_val > v_cap then v_kind := 'none'; v_val := 0; v_label := 'حظ أوفر'; v_sid := coalesce((select id from staff_wheel_slices where active and kind = 'none' order by sort, id limit 1), s.id); end if;
  end if;
  if v_kind = 'cash' then
    insert into staff_transactions(staff_id, kind, amount, note, created_by) values (auth.uid(), 'bonus', round(v_val,2), 'جايزة عجلة تحديات الموظفين: ' || l.title, auth.uid());
  elsif v_kind = 'gift' then
    begin
      perform push_send(coalesce((select array_agg(pr.id) from profiles pr where pr.role in ('owner','manager')), '{}'::uuid[]), 'جايزة عينية للتسليم', coalesce((select full_name from profiles where id = auth.uid()),'موظف') || ' كسب: ' || v_label, null, 'swgift-' || l.id, false);
    exception when others then null; end;
  elsif v_kind = 'points' and v_val > 0 then
    insert into staff_points_ledger(staff_id, pts, reason) values (auth.uid(), v_val::int, 'عجلة التحديات: ' || l.title);
  end if;
  update staff_ch_log set status = 'spun', prize_label = v_label, prize_kind = v_kind, prize_value = v_val, spun_at = now() where id = l.id;
  return jsonb_build_object('label', v_label, 'kind', v_kind, 'value', v_val, 'points', p_sw_pts(auth.uid()), 'slice_id', v_sid);
end $$;
-- تراجع: شغّل نسخة staff_ch_spin من patch_staff_wheel.sql وامسح القطاعات من نوع gift ثم أرجع القيد القديم
