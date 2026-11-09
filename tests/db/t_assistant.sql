\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
\i sql/patch_assistant.sql
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',true);
set local role authenticated;
select assistant_hit() as r1 \gset
select t.ok('زبون: أول سؤال مسموح والباقي 19', (:'r1'::jsonb->>'ok')::boolean and (:'r1'::jsonb->>'left')::int = 19);
select t.ok('الدور customer', :'r1'::jsonb->>'role' = 'customer');
do $$ begin for i in 1..19 loop perform assistant_hit(); end loop; end $$;
select assistant_hit() as r2 \gset
select t.ok('السؤال 21 مرفوض (limit)', not (:'r2'::jsonb->>'ok')::boolean and :'r2'::jsonb->>'reason' = 'limit');
reset role;
select t.ok('العدّاد ثابت عند الحد', (select n from assistant_usage limit 1) = 20);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',true);
set local role authenticated;
select assistant_hit() as r3 \gset
select t.ok('موظف: حد 40 ودوره staff', (:'r3'::jsonb->>'left')::int = 39 and :'r3'::jsonb->>'role' = 'barber');
reset role;
insert into app_settings(key, value) values ('assistant_enabled', '"false"') on conflict (key) do update set value = '"false"';
set local role authenticated;
select t.ok('إيقاف عام', not (assistant_hit()->>'ok')::boolean);
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$ begin perform assistant_hit(); raise exception 'FAIL: بدون دخول'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: بدون دخول مرفوض [%]', sqlerrm; end $$;
rollback;
\echo AS DONE
