\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.anon_() returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub','',true); execute 'set local role anon'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS: % [%]', n, sqlerrm; return; end; raise exception 'FAIL: % (المفروض يفشل)', n; end $$;
grant usage on schema t to public;
begin;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.ok('كاشير: مصروف', (cashier_add_expense('إيجار',100,'t','drawer')->>'ok')::boolean);
select t.ok('كاشير: سحب', (cashier_add_move('withdraw',50,null)->>'ok')::boolean);
select t.ok('كاشير: سلفة', (cashier_add_advance('00000000-0000-0000-0000-0000000000b1',30,null)->>'ok')::boolean);
select t.ok('اللوحة فيها العمليات', jsonb_array_length(cashier_board()->'expenses')=1 and jsonb_array_length(cashier_board()->'moves')=1 and jsonb_array_length(cashier_board()->'advances')=1);
select t.fl('مبلغ صفر','select cashier_add_expense(''إيجار'',0)');
select t.fl('نوع غلط','select cashier_add_move(''x'',5)');
select t.fl('مصدر غلط','select cashier_add_expense(''إيجار'',5,null,''x'')');
reset role;
reset role;
select t.as_('00000000-0000-0000-0000-0000000000b1');
select t.fl('حلاق ممنوع','select cashier_board()');
reset role;
select t.anon_();
select t.fl('زائر ممنوع','select cashier_board()');
reset role;
insert into cash_closings(day,expected_cash,expected_card,expected_wallet,counted_cash,counted_card,counted_wallet,diff_cash,diff_card,diff_wallet) values ((now() at time zone my_tz())::date,0,0,0,0,0,0,0,0,0);
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.fl('بعد قفل اليوم','select cashier_add_expense(''إيجار'',5)');
rollback;
\echo ALL CASHIER TESTS DONE
