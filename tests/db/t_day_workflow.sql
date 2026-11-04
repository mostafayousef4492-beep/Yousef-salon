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
\i sql/patch_edit_day.sql
\i sql/patch_day_workflow.sql
begin;
delete from cash_closings where day >= current_date-3; delete from business_days;
delete from cash_moves where note like 'T-DW%'; delete from staff_transactions where note like 'T-DW%';
insert into business_days(day, opened_at, closed_at) values (current_date-2, now()-interval '60 hours', now()-interval '40 hours'), (current_date-1, now()-interval '40 hours', now()-interval '16 hours');
insert into cash_closings(day,opening,expected_cash,expected_card,expected_wallet,counted_cash,counted_card,counted_wallet,diff_cash,diff_card,diff_wallet,breakdown)
 values (current_date-2,0,0,0,0,0,0,0,0,0,0,'{}'),(current_date-1,0,0,0,0,0,0,0,0,0,0,'{}');
insert into cash_moves(day,kind,amount,note) values (current_date-2,'deposit',600,'T-DW ضخ');
insert into staff_transactions(staff_id,kind,amount,note,created_at) values (:'b1','advance',2000,'T-DW جمعية', now()-interval '30 hours');
select id as mid from cash_moves where note='T-DW ضخ' \gset
select id as tid from staff_transactions where note='T-DW جمعية' \gset
select t.as_(:'own');
select t.ok('المعاينة فيها بند 2000 كبير', exists (select 1 from jsonb_array_elements(close_day_preview(current_date-1)->'big') i where (i->>'amount')::numeric = 2000));
select t.ok('المعاينة فيها المتوقع', (close_day_preview(current_date-1)->>'expected_cash') is not null);
select t.ok('نقل ضخ ليوم تاني', (move_entry_day('cash_move', :mid, current_date-1)->>'to')::date = current_date-1);
reset role;
select t.ok('الضخ اتنقل فعلاً', (select day from cash_moves where id = :mid) = current_date-1);
select t.ok('لقطة الإقفال اتحدّثت بالضخ', (select expected_cash from cash_closings where day=current_date-1) = 600 - 2000);
select t.as_(:'own');
select t.ok('نقل حركة موظف', (move_entry_day('staff_tx', :tid, current_date-2)->>'to')::date = current_date-2);
select t.as_(:'cash');
select t.fl('الكاشير مينفعش ينقل', format('select move_entry_day(%L, %s, %L)', 'cash_move', :mid, current_date-2));
rollback;
