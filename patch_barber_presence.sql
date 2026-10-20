-- patch_barber_presence.sql — ظهور الحلاق في الحجز مربوط بالحضور والانصراف
-- النهارده بس: الحلاق بيظهر لما يكون مسجّل حضور (ولسه ما سجلش انصراف)، ويختفي أول ما يسجل انصراف.
-- الأيام الجاية بتفضل على مواعيد الشغل زي ما هي. تقدر توقفه من الإعدادات > الحجوزات.
-- آمن للتكرار.

insert into app_settings(key, value) values ('booking_require_checkin', 'true'::jsonb)
  on conflict (key) do nothing;

create or replace function p19_present(p_barber uuid, p_day date) returns boolean
language plpgsql stable security definer set search_path to 'public' as $$
declare v_on boolean := coalesce(setting('booking_require_checkin', 'true'::jsonb) #>> '{}', 'true') <> 'false';
begin
  if not v_on then return true; end if;
  if p_day is distinct from (now() at time zone my_tz())::date then return true; end if;
  return exists (select 1 from attendance a
                  where a.staff_id = p_barber and a.check_out is null and a.check_in > now() - interval '20 hours');
end $$;
grant execute on function p19_present(uuid, date) to anon, authenticated;

do $$ declare d text; n text;
begin
  d := pg_get_functiondef('available_barbers(date,text)'::regprocedure);
  if position('p19_present' in d) = 0 then
    n := replace(d, 'where (not b.is_off and b.start_time < r.e and b.end_time > r.s)',
                    'where p19_present(b.barber_id, p_day) and ((not b.is_off and b.start_time < r.e and b.end_time > r.s)');
    n := replace(n, $q$and '00:00'::time < r.e)$q$, $q$and '00:00'::time < r.e))$q$);
    if n = d or position('p19_present' in n) = 0 or position($q$< r.e))$q$ in n) = 0 then raise exception 'available_barbers: anchor not found'; end if;
    execute n;
  end if;
end $$;
