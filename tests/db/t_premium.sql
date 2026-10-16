\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-0000000000f1') on conflict do nothing;
insert into customers(user_id,name,phone) values ('00000000-0000-0000-0000-0000000000f1','عميل بريميوم','01090000001');
select t.as_('00000000-0000-0000-0000-0000000000f1');
select t.ok('بروفايل بدون صورة', (my_profile()->>'avatar') is null);
select set_my_profile('data:image/jpeg;base64,/9j/4AAQSkZJRg==', date '1990-05-10', false);
select t.ok('الصورة اتحفظت', (my_profile()->>'avatar') like 'data:image/jpeg%');
select t.fl('صورة مش صالحة', $$select set_my_profile('http://evil/x.js',null,false)$$);
select t.fl('ميلاد مستقبلي', $$select set_my_profile(null,current_date,false)$$);
select t.fl('هدية بدون زيارة', $$select claim_birthday_gift()$$);
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a2',true);
insert into invoices(customer_id,subtotal,discount,total,payment_method) values ((select id from customers where phone='01090000001'),50,0,50,'cash');
update customers set birthday = (current_date - 1 - 9*365 + 9*365) where phone='01090000001'; 
select t.as_('00000000-0000-0000-0000-0000000000f1');
select t.ok('الهدية متاحة', (my_profile()->>'can_claim_birthday')::boolean);
select t.ok('الهدية 50', claim_birthday_gift()=50);
select t.fl('مرتين', $$select claim_birthday_gift()$$);
reset role;
select t.ok('النقاط اتضافت', (select points from customers where phone='01090000001')>=50);
select t.as_('00000000-0000-0000-0000-0000000000f1');
select t.ok('مفيش آخر زيارة', my_last_visit() is null);
rollback;
\echo PREMIUM TESTS DONE
