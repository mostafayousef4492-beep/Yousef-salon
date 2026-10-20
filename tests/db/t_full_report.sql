\set ON_ERROR_STOP 1
\set QUIET 1
begin;
update profiles set commission_pct=40, salary=3000 where id='00000000-0000-0000-0000-0000000000b1';
insert into invoices(barber_id,subtotal,discount,total,payment_method) values ('00000000-0000-0000-0000-0000000000b1',200,0,200,'cash'),('00000000-0000-0000-0000-0000000000b1',100,0,100,'cash');
insert into expenses(spent_on,category,amount,note) values (current_date,'إيجار',500,'x'),(current_date,'كهرباء',120,'y');
insert into staff_transactions(staff_id,kind,amount,note) values ('00000000-0000-0000-0000-0000000000b1','advance',50,'سلفة'),('00000000-0000-0000-0000-0000000000b1','bonus',30,'مكافأة'),('00000000-0000-0000-0000-0000000000b1','deduction',10,'خصم');
select t.as_('00000000-0000-0000-0000-0000000000a1');
create temp table r as select full_report(now() - interval '60 days', now() + interval '1 day') j, report_data(now() - interval '60 days', now() + interval '1 day') d;
grant all on r to public;
select t.ok('الإيراد بيطابق report_data', (select (j->>'revenue')::numeric = (d->'totals'->>'revenue')::numeric from r));
select t.ok('الربح بيطابق report_data', (select abs((j->>'profit')::numeric - (d->'totals'->>'profit')::numeric) < 0.01 from r));
select t.ok('مجموع تكلفة الموظفين = مجموع بنودهم', (select abs((j->>'staff_cost')::numeric - coalesce((select sum((x->>'cost')::numeric) from jsonb_array_elements(j->'staff') x),0)) < 0.01 from r));
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.ok('مبيعات الحلاق صح', (select (x->>'sales')::numeric=300 and (x->>'commission')::numeric=120 and (x->>'advance')::numeric=50 from r, jsonb_array_elements(j->'staff') x where x->>'id'='00000000-0000-0000-0000-0000000000b1'));
select t.ok('بنود المصاريف', (select jsonb_array_length(j->'expense_cats')=2 and (j->>'expenses')::numeric=620 from r));
select t.fl('الكاشير مرفوض', $$select full_report(now() - interval '1 day', now())$$);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000b1');
select t.fl('الحلاق مرفوض', $$select full_report(now() - interval '1 day', now())$$);
reset role;
rollback;
select 'ALL FULL REPORT TESTS PASSED';
