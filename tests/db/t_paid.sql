\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
begin;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1}]'::jsonb,0,0,'cash') as inv \gset
select total as tot from invoices where id=:inv \gset
select (range_figures(current_date,current_date)->>'cash_sales')::numeric as c0 \gset
select t.fl('أقل من المطلوب', format('select invoice_set_paid(%s,%s)',:inv,:tot-1));
select invoice_set_paid(:inv,:tot+20);
select t.ok('زيادة 20', (select extra_paid from invoices where id=:inv)=20);
select t.ok('الدرج بيشمل الزيادة', (range_figures(current_date,current_date)->>'cash_sales')::numeric=:c0+20);
select t.ok('الإيراد ثابت', (range_figures(current_date,current_date)->>'revenue')::numeric>=:tot);
select t.ok('tips', (range_figures(current_date,current_date)->>'tips')::numeric=20);
reset role;
update invoices set created_at=now()-interval '2 hours' where id=:inv;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.fl('كاشير بعد 15 دقيقة', format('select invoice_set_paid(%s,%s)',:inv,:tot+5));
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select invoice_set_paid(:inv,:tot+5);
select t.ok('المدير يعدل', (select extra_paid from invoices where id=:inv)=5);
rollback;
\echo PAID DONE
