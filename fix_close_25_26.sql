-- فصل يوم 25 عن يوم 26، وقفلهم بجرد الدرج الحقيقي، وفتح يوم 27 نضيف.
-- كاش الدرج الحقيقي دلوقتي = 1730 (كله: فلوس الشهر). الكارت 0 والمحفظة زي المتوقع.
-- بيتشغل مرة واحدة (لو اتشغل قبل كده بيقول "اتنفذ قبل كده" ومبيعملش حاجة).
do $$
declare
  c_cash constant numeric := 1730;           -- كاش الدرج الحقيقي دلوقتي
  b1 timestamptz := (timestamp '2026-10-26 00:00') at time zone my_tz();
  b2 timestamptz := (timestamp '2026-10-27 00:00') at time zone my_tz();
  op uuid; f25 jsonb; f26 jsonb; net25 numeric; net26 numeric; c25 numeric; o25 numeric;
begin
  if exists (select 1 from business_days where day = date '2026-10-26') then raise notice 'اتنفذ قبل كده'; return; end if;
  if not exists (select 1 from business_days where day = date '2026-10-25' and closed_at is null) then raise exception 'يوم 25 مش مفتوح'; end if;
  if exists (select 1 from cash_closings where day >= date '2026-10-25') then raise exception 'فيه قفل متسجل للأيام دي'; end if;
  select opened_by into op from business_days where day = date '2026-10-25';

  -- حركات اتعملت بعد منتصف ليل 26 كانت متسجلة على يوم 25 لأنه كان لسه مفتوح
  update cash_moves set day = date '2026-10-26' where day = date '2026-10-25' and created_at >= b1;
  update expenses   set spent_on = date '2026-10-26' where spent_on = date '2026-10-25' and created_at >= b1;

  update business_days set closed_at = b1, closed_by = op where day = date '2026-10-25';
  insert into business_days(day, opened_at, opened_by, closed_at, closed_by) values (date '2026-10-26', b1, op, b2, op);
  insert into business_days(day, opened_at, opened_by) values (date '2026-10-27', b2, op);

  f25 := day_figures(date '2026-10-25'); f26 := day_figures(date '2026-10-26');
  net25 := expected_cash_of(f25, 0); net26 := expected_cash_of(f26, 0);
  c25 := c_cash - net26;          -- كاش الدرج آخر يوم 25
  o25 := c25 - net25;             -- افتتاح يوم 25
  f25 := f25 || jsonb_build_object('opening', o25); f26 := f26 || jsonb_build_object('opening', c25);

  insert into cash_closings(day, opening, expected_cash, expected_card, expected_wallet, counted_cash, counted_card, counted_wallet, diff_cash, diff_card, diff_wallet, breakdown, note, closed_by)
  values (date '2026-10-25', o25, c25, (f25->>'card_sales')::numeric, (f25->>'wallet_sales')::numeric, c25, (f25->>'card_sales')::numeric, (f25->>'wallet_sales')::numeric, 0, 0, 0, f25, 'تسوية: افتتاح محسوب من جرد الدرج الفعلي', op),
         (date '2026-10-26', c25, c_cash, (f26->>'card_sales')::numeric, (f26->>'wallet_sales')::numeric, c_cash, (f26->>'card_sales')::numeric, (f26->>'wallet_sales')::numeric, 0, 0, 0, f26, 'تسوية: جرد الدرج الفعلي', op);
end $$;
select day, opening, expected_cash, counted_cash, diff_cash from cash_closings where day >= '2026-10-25' order by day;
select day, opened_at, closed_at from business_days where day >= '2026-10-24' order by day;
