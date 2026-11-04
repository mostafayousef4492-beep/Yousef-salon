\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
\set own '00000000-0000-0000-0000-0000000000a1'
\set cash '00000000-0000-0000-0000-0000000000a2'
\set b1 '00000000-0000-0000-0000-0000000000b1'
\i sql/patch_cash_prev_day.sql
begin;
delete from staff_transactions where note like 'T-PD%'; delete from cash_moves where note like 'T-PD%';
insert into business_days(day,opened_at) values (current_date, now()-interval '1 hour') on conflict do nothing;
select current_date as d \gset
insert into cash_moves(day,kind,amount,note,prev_day) values (:'d','withdraw',100,'T-PD a',true),(:'d','withdraw',40,'T-PD b',false);
insert into staff_transactions(staff_id,kind,amount,note,prev_day) values (:'b1','advance',70,'T-PD c',true),(:'b1','advance',5,'T-PD d',false);
select t.as_(:'own');
select t.ok('سحب الدرج المعلّم بس', (day_prev_out(:'d')->>'moves')::numeric = 100);
select t.ok('السلفة المعلّمة بس', (day_prev_out(:'d')->>'adv')::numeric = 70);
rollback;
delete from business_days where day=current_date and closed_at is null;
