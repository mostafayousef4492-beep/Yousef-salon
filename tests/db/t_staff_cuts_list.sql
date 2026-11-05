\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
\set own '00000000-0000-0000-0000-0000000000a1'
\set cash '00000000-0000-0000-0000-0000000000a2'
\set b1 '00000000-0000-0000-0000-0000000000b1'
\i sql/patch_staff_cuts_list.sql
begin;
select t.as_(:'cash');
select pos_checkout(null, :'b1'::uuid, '[{"type":"service","id":1,"qty":1},{"type":"service","id":2,"qty":1}]'::jsonb, 0, 0, 'cash') as inv \gset
reset role;
select commission_pct as pct from profiles where id = :'b1' \gset
select t.as_(:'b1');
select t.ok('الحلاق يشوف فاتورته بالمبلغ', (select count(*) = 1 and sum(total) = 150 from staff_cuts_list(:'b1'::uuid, now() - interval '1 hour', now() + interval '1 hour')));
select t.ok('العمولة = النسبة × المبلغ', (select abs(sum(commission) - 150 * :pct / 100) < 0.01 from staff_cuts_list(:'b1'::uuid, now() - interval '1 hour', now() + interval '1 hour')));
select t.ok('فيه اسم العميل والخدمات', (select customer = 'عميل عابر' and services <> '' from staff_cuts_list(:'b1'::uuid, now() - interval '1 hour', now() + interval '1 hour') limit 1));
reset role;
select t.as_(:'cash');
select t.fl('الكاشير مايشوفش حلاق تاني', format('select * from staff_cuts_list(%L::uuid, now() - interval ''1 hour'', now())', :'b1'));
rollback;
\echo CUTS LIST DONE
