-- علاج لمرة واحدة: اليوم 25 اتفتح الساعة 12 والشغل بتاع يوم 24 كان لسه شغال.
-- بيرجّع يوم 24 هو اليوم المفتوح (من أول اليوم) ويمسح يوم 25 المفتوح بالغلط.
-- بعدها تقفل يوم 24 من الخزنة بجرد الدرج، وبعدين تفتح يوم 25 بنفسك.
-- آمن: مش بيعمل حاجة لو فيه جرد متسجل لأي من اليومين.
do $$
declare t date := '2026-10-25'; y date := '2026-10-24'; ob uuid;
begin
  if not exists (select 1 from business_days where day = t and closed_at is null) then
    raise notice 'يوم % مش مفتوح - مفيش حاجة تتعمل', t; return; end if;
  if exists (select 1 from cash_closings where day in (t, y)) then
    raise exception 'فيه جرد متسجل ليوم % أو % - اتواصل قبل ما تكمل', y, t; end if;
  select opened_by into ob from business_days where day = t;
  delete from business_days where day = t;
  insert into business_days(day, opened_at, opened_by) values (y, (y::timestamp at time zone my_tz()), ob)
    on conflict (day) do update set closed_at = null, closed_by = null, opened_at = excluded.opened_at;
  raise notice 'تم: يوم % هو المفتوح دلوقتي', y;
end $$;
select day, opened_at, closed_at from business_days order by day desc limit 3;
