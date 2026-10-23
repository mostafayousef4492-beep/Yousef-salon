-- patch_pay_by_days.sql — راتب المساعدين = أيام الحضور اللي حضرها بس (أجر اليوم × عدد الأيام)
-- مفيش راتب شهري بيتحسب للمساعد خالص: اليوم اللي مفيهوش حضور مفيهوش أجر.
-- القاعدة: لأي مساعد على "يومية بالحضور"، تاريخ بدء الحضور (att_from) بيرجع لأول يوم له (تاريخ إنشاء حسابه أو أول أجر يوم).
-- مفيش حركة بتتمسح أو بتتعدل. لو يوم اتشتغل ومتسجلش حضور: ضيف له حضور يدوي من الإدارة وهيتحسب له أجره.
-- 1) المساعدين الحاليين
update staff_pay_profile f
   set att_from = least(f.att_from,
                        (select (p.created_at at time zone p11_tz())::date from profiles p where p.id = f.staff_id),
                        coalesce((select min(to_date(substring(t.note from 'أجر يوم (\d{4}-\d{2}-\d{2})'), 'YYYY-MM-DD'))
                                    from staff_transactions t
                                   where t.staff_id = f.staff_id and t.kind::text = 'bonus' and t.note ~ '^أجر يوم \d{4}-\d{2}-\d{2}'), f.att_from))
 where f.pay_mode = 'daily_attendance' and f.att_from is not null
   and exists (select 1 from profiles p where p.id = f.staff_id and p.role::text = 'assistant');

-- 2) أي مساعد يتحول لاحقًا للحضور: يبدأ من أول يوم له مش من يوم التحويل
do $$ declare d text; n text;
begin
  d := pg_get_functiondef('p19_pay_cutover()'::regprocedure);
  if position('p25_by_days' in d) = 0 then
    n := replace(d, 'new.att_from := coalesce(new.att_from, v_start);',
      'if exists (select 1 from profiles p where p.id = new.staff_id and p.role::text = ''assistant'') then /* p25_by_days */' || E'\n' ||
      '      v_start := least(v_start, (select (p.created_at at time zone p11_tz())::date from profiles p where p.id = new.staff_id),' || E'\n' ||
      '        coalesce((select min(to_date(substring(t.note from ''أجر يوم (\d{4}-\d{2}-\d{2})''), ''YYYY-MM-DD'')) from staff_transactions t where t.staff_id = new.staff_id and t.kind::text = ''bonus'' and t.note ~ ''^أجر يوم \d{4}-\d{2}-\d{2}''), v_start));' || E'\n' ||
      '    end if;' || E'\n' ||
      '    new.att_from := coalesce(new.att_from, v_start);');
    if n = d or position('p25_by_days' in n) = 0 then raise exception 'p19_pay_cutover: anchor not found'; end if;
    execute n;
  end if;
end $$;
