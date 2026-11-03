-- منع فتح يوم جديد وفيه يوم قبله فيه شغل ولسه ما اتقفلش بجرد الدرج
-- آمن للتكرار. شغّله في Supabase SQL Editor.
do $$
declare d text; n text;
begin
  select pg_get_functiondef('public.open_business_day()'::regprocedure) into d;
  if d like '%p26_guard%' then raise notice 'already applied'; return; end if;
  if position('  insert into business_days(day, opened_by) values (v, auth.uid())' in d) = 0 then
    raise exception 'anchor not found';
  end if;
  n := replace(d, '  insert into business_days(day, opened_by) values (v, auth.uid())',
$g$  /* p26_guard */
  if exists (select 1 from invoices i where (i.created_at at time zone my_tz())::date = v - 1)
     and not exists (select 1 from cash_closings c where c.day = v - 1)
     and not exists (select 1 from business_days b where b.day = v - 1 and b.closed_at is not null) then
    raise exception 'يوم % فيه شغل ولسه ما اتقفلش بجرد الدرج. اقفله الأول من الخزنة (اختار يوم % واعمل قفل اليوم) وبعدها افتح اليوم الجديد.', v - 1, v - 1;
  end if;
  insert into business_days(day, opened_by) values (v, auth.uid())$g$);
  execute n;
end $$;
