\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
\set own '00000000-0000-0000-0000-0000000000a1'
\set cash '00000000-0000-0000-0000-0000000000a2'
\set b1 '00000000-0000-0000-0000-0000000000b1'
\i sql/patch_bundles.sql
\i sql/patch_walkin_bundles.sql
\i sql/patch_outside_fee.sql
\i sql/patch_staff_cuts_list.sql
\i sql/patch_outside_customer.sql
\i sql/patch_outside_customer.sql
begin;
insert into app_settings(key,value) values ('outside_fee','200') on conflict (key) do update set value=excluded.value;
select commission_pct as pct from profiles where id = :'b1' \gset
select t.as_(:'cash');
select pos_checkout_b(null,null,null,:'b1'::uuid,'[{"type":"service","id":1,"qty":1},{"type":"service","id":2,"qty":1}]'::jsonb,0,0,'cash',null,null,null,true) as inv \gset
reset role;
select t.as_(:'b1');
select t.ok('إجمالي الفاتورة 350', (select sum(total) = 350 from staff_cuts_list(:'b1'::uuid, now() - interval '1 hour', now() + interval '1 hour')));
select t.ok('العمولة على الخدمات (150) بس', (select abs(sum(commission) - 150 * :pct / 100) < 0.01 from staff_cuts_list(:'b1'::uuid, now() - interval '1 hour', now() + interval '1 hour')));
select t.ok('staff_summary العمولة على الخدمات بس', (select abs(commission - 150 * :pct / 100) < 0.01 from staff_summary(:'b1'::uuid, now() - interval '1 hour', now() + interval '1 hour')));
rollback;
\echo OUTSIDE COMM DONE
