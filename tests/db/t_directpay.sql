\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
begin;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select (admin_book_ticket('دفع مباشر','01055550001','00000000-0000-0000-0000-0000000000b1'::uuid, current_date+2, 'morning', array[1]::bigint[])->'ticket'->>'id')::bigint as tid \gset
select t.ok('التذكرة upcoming', (select status::text from appointments where id=:tid)='upcoming');
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1}]'::jsonb,0,0,'cash',:tid,null,null) as inv \gset
select t.ok('الفاتورة اتعملت', :inv>0);
select t.ok('التذكرة بقت done من غير نداء/حضور/بدء', (select status::text from appointments where id=:tid)='done');
select t.ok('الفاتورة مربوطة بالتذكرة', (select count(*) from invoices where appointment_id=:tid)=1);
rollback;
\echo DIRECTPAY DONE
