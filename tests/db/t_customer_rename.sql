\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fails2(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS: % [%]', n, sqlerrm; return; end; raise exception 'FAIL: % (المفروض يفشل)', n; end $$;
grant usage on schema t to public;
begin;
insert into customers(name,phone,points) values ('محمد غلط','01577712345',50);
select id as cid from customers where phone='01577712345' \gset
select t.as_('00000000-0000-0000-0000-0000000000a1');
select admin_set_customer_name(:cid, '  محمد صح  ') as r \gset
reset role;
select t.ok('المالك عدّل الاسم (من غير مسافات زيادة)', (select name from customers where id=:cid)='محمد صح' and :'r'='محمد صح');
select t.ok('الرقم والنقاط زي ما هي', (select phone||'/'||points from customers where id=:cid)='01577712345/50');
select t.as_('00000000-0000-0000-0000-0000000000a2');
select admin_set_customer_name(:cid, 'محمد الكاشير');
reset role;
select t.ok('الكاشير يقدر يعدّل', (select name from customers where id=:cid)='محمد الكاشير');
select t.as_('00000000-0000-0000-0000-0000000000b1');
select t.fails2('الحلاق من غير صلاحية مرفوض', format('select admin_set_customer_name(%s, %L)', :cid, 'اسم'));
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.fails2('اسم قصير', format('select admin_set_customer_name(%s, %L)', :cid, 'م'));
select t.fails2('اسم فاضي', format('select admin_set_customer_name(%s, %L)', :cid, '   '));
select t.fails2('اسم طويل', format('select admin_set_customer_name(%s, %L)', :cid, repeat('ا', 61)));
select t.fails2('عميل مش موجود', 'select admin_set_customer_name(-5, ''اسم صح'')');
reset role;
set local role anon;
select t.fails2('الزائر مرفوض', format('select admin_set_customer_name(%s, %L)', :cid, 'اسم'));
reset role;
select t.ok('الاسم بعد المحاولات الغلط', (select name from customers where id=:cid)='محمد الكاشير');
rollback;
select 'CUSTOMER RENAME DONE';
