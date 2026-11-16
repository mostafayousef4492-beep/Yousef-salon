-- ============================================================
-- بيانات مبدئية للخامات — كل الأرقام تقريبية (مؤقتة) وتتعدّل من شاشة «خامات الخدمات» (جرد / تعديل / استهلاك الخدمة).
--   شفرة حلاقة (قطعة): تكلفة 2.5 ج، رصيد 500، تنبيه عند 50  ← 1 مع: حلاقة ذقن (تدريج / ماكينة+تحديد / موس)
--   كريم حمام (جرام): تكلفة 0.10 ج، رصيد 10000 (10 كجم)، تنبيه عند 1000 ← 50 جرام مع: حمام كريم
--   ماسك (جرام): تكلفة 0.15 ج، رصيد 5000 (5 كجم)، تنبيه عند 500 ← 30 جرام مع: مسك طمي، مسك صنفرة
-- الأرقام دي من مثال الخطة مش من قياس حقيقي. بعد القياس: «جرد» للرصيد و«استهلاك كل خدمة» للكميات.
-- لازم patch_materials.sql يكون اتشغّل قبله. آمن للتكرار (مبيكرّرش خامة ومبيضيفش رصيد ابتدائي تاني).
-- شغّل الملف كله مرة واحدة (Ctrl+A ثم Run).
-- ============================================================
do $$
declare r record; v_id bigint;
begin
  for r in select * from (values
      ('شفرة حلاقة', 'قطعة', 2.5::numeric, 500::numeric, 50::numeric),
      ('كريم حمام',  'جرام', 0.10, 10000, 1000),
      ('ماسك',       'جرام', 0.15, 5000, 500)
    ) as t(name, unit, cost, stock, min_stock)
  loop
    select id into v_id from materials where lower(btrim(name)) = lower(btrim(r.name));
    if v_id is null then
      insert into materials(name, unit, cost, min_stock, stock, active) values (r.name, r.unit, r.cost, r.min_stock, 0, true) returning id into v_id;
      insert into material_movements(material_id, qty, reason, note) values (v_id, r.stock, 'initial', 'رصيد ابتدائي تقريبي — يتعدّل بالجرد');
    end if;
  end loop;

  -- الربط (بيتخطى أي خدمة مش موجودة، ومبيغيّرش كمية اتعدّلت قبل كده)
  insert into service_materials(service_id, material_id, qty)
  select s.id, m.id, x.qty
    from (values (2,'شفرة حلاقة',1::numeric),(35,'شفرة حلاقة',1),(36,'شفرة حلاقة',1),
                 (4,'كريم حمام',50),(10,'ماسك',30),(9,'ماسك',30)) as x(sid, mname, qty)
    join services s on s.id = x.sid
    join materials m on lower(btrim(m.name)) = lower(btrim(x.mname))
  on conflict (service_id, material_id) do nothing;
end $$;
