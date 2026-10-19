\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
begin;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select (admin_book_ticket('عميل تابلت','01090000700','00000000-0000-0000-0000-0000000000b1'::uuid,(now() at time zone my_tz())::date,current_period(),array[1,2]::bigint[])->'ticket'->>'id')::bigint as tk \gset
select (admin_book_ticket('عميل تابلت2','01090000701','00000000-0000-0000-0000-0000000000b2'::uuid,(now() at time zone my_tz())::date,current_period(),array[1]::bigint[])->'ticket'->>'id')::bigint as tk2 \gset
reset role;
-- الحلاق b1: ينادي ويأكد الحضور ويبدأ على تذكرته
select t.as_('00000000-0000-0000-0000-0000000000b1');
select call_ticket(:tk);
select confirm_arrival(:tk);
select t.fl('مايبدأش تذكرة حلاق تاني', format('select start_service(%s)',:tk2));
select start_service(:tk);
reset role;
select t.ok('بدأت الخدمة', (select status::text from appointments where id=:tk)='in_service');
-- الإعداد يقفل بدء الحلاق
update appointments set status='upcoming' where id=:tk2;
insert into app_settings(key,value) values ('barber_can_start','false'::jsonb) on conflict (key) do update set value='false'::jsonb;
select t.as_('00000000-0000-0000-0000-0000000000b2');
select call_ticket(:tk2);
select confirm_arrival(:tk2);
select t.fl('الإعداد مقفول', format('select start_service(%s)',:tk2));
reset role;
delete from app_settings where key='barber_can_start';
-- الحساب
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select t.ok('حساب قبل الدفع', (ticket_bill(:tk,'01090000700')->>'total')::numeric=150 and (ticket_bill(:tk,'01090000700')->>'paid')::boolean is false);
select t.ok('حساب مقفول لغير صاحبه', ticket_bill(:tk,'01011111111') is null);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1},{"type":"service","id":2,"qty":1}]'::jsonb,0,0,'cash',:tk) as inv \gset
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select t.ok('حساب بعد الدفع = الفاتورة', (ticket_bill(:tk,'01090000700')->>'paid')::boolean and (ticket_bill(:tk,'01090000700')->>'total')::numeric=150);
reset role;
rollback;
\echo TABLET DONE
