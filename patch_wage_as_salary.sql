-- patch_wage_as_salary.sql — "أجر يوم" بالحضور يتحسب في خانة الراتب (مش المكافآت)
-- التأخير (خصم الدقايق) بيفضل في خانة الخصومات زي ما هو. مفيش أي حركة بتتغير ولا بتتمسح،
-- ومجموع التكلفة والصافي والربح ثابت: الفرق بس في الخانة اللي بتظهر فيها اليومية.
do $$ declare d text; n text;
begin
  -- ملخص الموظف
  d := pg_get_functiondef('staff_summary(uuid,timestamptz,timestamptz)'::regprocedure);
  if position('p22_wage' in d) = 0 then
    n := replace(d, 'v_role user_role; v_sal numeric;', 'v_role user_role; v_w numeric := 0; v_sal numeric;');
    n := replace(n, 'select coalesce(sum(t.amount) filter (where t.kind=''bonus''),0), coalesce(sum(t.amount) filter (where t.kind=''advance''),0),',
                    'select coalesce(sum(t.amount) filter (where t.kind=''bonus'' and coalesce(t.note,'''') not like ''أجر يوم%''),0), coalesce(sum(t.amount) filter (where t.kind=''advance''),0),');
    n := replace(n, 'coalesce(sum(t.amount) filter (where t.kind=''deduction''),0) into v_b, v_a, v_d',
                    'coalesce(sum(t.amount) filter (where t.kind=''deduction''),0), coalesce(sum(t.amount) filter (where t.kind=''bonus'' and coalesce(t.note,'''') like ''أجر يوم%''),0) into v_b, v_a, v_d, v_w');
    n := replace(n, 'end;' || E'\n' || '  if v_role = ''assistant'' then', 'end; /* p22_wage */' || E'\n' || '  v_salp := v_salp + v_w;' || E'\n' || '  if v_role = ''assistant'' then');
    if n = d or position('v_salp := v_salp + v_w' in n) = 0 or position('into v_b, v_a, v_d, v_w' in n) = 0 or position('not like ''أجر يوم%''' in n) = 0 or position('v_w numeric := 0' in n) = 0 then
      raise exception 'staff_summary: anchor not found'; end if;
    execute n;
  end if;
  -- التقرير الشامل
  d := pg_get_functiondef('full_report(timestamptz,timestamptz)'::regprocedure);
  if position('p22_wage' in d) = 0 then
    n := replace(d, 'case when pr.salary > 0 then round(salary_part_for(pr.id, pr.salary, p_from, p_to), 2) else 0 end sal,',
                    '(case when pr.salary > 0 then round(salary_part_for(pr.id, pr.salary, p_from, p_to), 2) else 0 end) + coalesce(t.wg,0) sal, /* p22_wage */');
    n := replace(n, 'select sum(amount) filter (where kind=''bonus'') bon,',
                    'select sum(amount) filter (where kind=''bonus'' and coalesce(note,'''') not like ''أجر يوم%'') bon, sum(amount) filter (where kind=''bonus'' and coalesce(note,'''') like ''أجر يوم%'') wg,');
    if n = d or position('t.wg' in n) = 0 or position(' wg,' in n) = 0 then raise exception 'full_report: anchor not found'; end if;
    execute n;
  end if;
  -- تقرير الفترة
  d := pg_get_functiondef('report_data(timestamptz,timestamptz)'::regprocedure);
  if position('p22_wage' in d) = 0 then
    n := replace(d, 'into v_sal from profiles pr where pr.role <> ''owner'' and pr.salary > 0;',
                    'into v_sal from profiles pr where pr.role <> ''owner'' and pr.salary > 0; /* p22_wage */' || E'\n' ||
                    '  v_sal := v_sal + coalesce((select sum(w.amount) from staff_transactions w where w.kind = ''bonus'' and coalesce(w.note,'''') like ''أجر يوم%'' and w.created_at >= p_from and w.created_at < p_to), 0);');
    n := replace(n, 'coalesce(sum(amount) filter (where kind=''bonus''),0), coalesce(sum(amount) filter (where kind=''deduction''),0)',
                    'coalesce(sum(amount) filter (where kind=''bonus'' and coalesce(note,'''') not like ''أجر يوم%''),0), coalesce(sum(amount) filter (where kind=''deduction''),0)');
    n := replace(n, 'salary_part_for(pr.id, pr.salary, p_from, p_to) sal',
                    '(salary_part_for(pr.id, pr.salary, p_from, p_to) + coalesce((select sum(w.amount) from staff_transactions w where w.staff_id = pr.id and w.kind = ''bonus'' and coalesce(w.note,'''') like ''أجر يوم%'' and w.created_at >= p_from and w.created_at < p_to), 0)) sal');
    if n = d or position('not like ''أجر يوم%''' in n) = 0 or position('v_sal := v_sal +' in n) = 0 or position('w.staff_id = pr.id' in n) = 0 then raise exception 'report_data: anchor not found'; end if;
    execute n;
  end if;
end $$;
