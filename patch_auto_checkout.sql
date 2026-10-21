-- patch_auto_checkout.sql — انصراف تلقائي لمن ينسى: بيتسجل عند آخر الشيفت اللي حاططه للموظف
-- بيشتغل كل 5 دقايق. بيقفل التسجيلات المفتوحة بس بعد ما الشيفت يخلص، ووقت الانصراف = ساعة نهاية الشيفت بالظبط.
-- لو مفيش شيفت للموظف في اليوم ده، أو يوم إجازة، أو سجّل حضور بعد نهاية الشيفت: بيسيبه مفتوح (تقفله إنت).
-- يتوقف من الإعدادات (auto_checkout_enabled). آمن للتكرار.

insert into app_settings(key, value) values ('auto_checkout_enabled', 'true'::jsonb) on conflict (key) do nothing;

create or replace function public.p21_auto_checkout() returns integer
language plpgsql security definer set search_path to 'public' as $$
declare r record; tz text := my_tz(); d date; sh record; e_ts timestamp; v_end timestamptz; n int := 0;
  v_on boolean := coalesce(setting('auto_checkout_enabled', 'true'::jsonb) #>> '{}', 'true') <> 'false';
begin
  if not v_on then return 0; end if;
  for r in select a.id, a.staff_id, a.check_in, a.note from attendance a
            where a.check_out is null and a.check_in > now() - interval '7 days' and a.check_in < now() loop
    v_end := null;
    d := (r.check_in at time zone tz)::date;
    -- لو حضر بعد نص الليل وقبل نهاية شيفت ليلي بدأ إمبارح، ده شيفت إمبارح
    select * into sh from staff_shifts where staff_id = r.staff_id and weekday = extract(dow from d - 1)::int;
    if found and not sh.is_off and sh.start_time is not null and sh.end_time is not null and sh.end_time <= sh.start_time
       and (r.check_in at time zone tz) < d + sh.end_time then
      v_end := (d + sh.end_time) at time zone tz;
    else
      -- شيفت اليوم اللي سجّل فيه حضور
      select * into sh from staff_shifts where staff_id = r.staff_id and weekday = extract(dow from d)::int;
      if found and not sh.is_off and sh.start_time is not null and sh.end_time is not null then
        e_ts := case when sh.end_time <= sh.start_time then (d + 1) + sh.end_time else d + sh.end_time end;
        if (r.check_in at time zone tz) < e_ts then v_end := e_ts at time zone tz; end if;
      end if;
    end if;
    if v_end is not null and v_end <= now() and v_end > r.check_in then
      update attendance set check_out = v_end,
             note = case when coalesce(note, '') = '' then 'انصراف تلقائي (آخر الشيفت)' else note || ' · انصراف تلقائي (آخر الشيفت)' end
       where id = r.id and check_out is null;
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.p21_auto_checkout() from public, anon, authenticated;

-- جدولة كل 5 دقايق (لو pg_cron متاح)
do $$ begin
  if to_regnamespace('cron') is not null then
    perform cron.schedule('p21-auto-checkout', '*/5 * * * *', 'select public.p21_auto_checkout()');
  end if;
end $$;
