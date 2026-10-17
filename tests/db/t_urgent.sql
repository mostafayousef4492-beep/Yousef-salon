\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-0000000000f1') on conflict do nothing;
insert into customers(user_id,name,phone) values ('00000000-0000-0000-0000-0000000000f1','زبون مستعجل','01090000001');
-- حجوزات عادية ورا بعض عند b1 (النهارده، الفترة الحالية)
select t.as_('00000000-0000-0000-0000-0000000000a1');
select (admin_book_ticket('عادي1','01090000011','00000000-0000-0000-0000-0000000000b1'::uuid,(now() at time zone my_tz())::date,current_period(),array[1]::bigint[])->'ticket'->>'id')::bigint as n1 \gset
select (admin_book_ticket('عادي2','01090000012','00000000-0000-0000-0000-0000000000b1'::uuid,(now() at time zone my_tz())::date,current_period(),array[1]::bigint[])->'ticket'->>'id')::bigint as n2 \gset
reset role;
-- الزبون يطلب مستعجل
select t.as_('00000000-0000-0000-0000-0000000000f1');
select (request_urgent('00000000-0000-0000-0000-0000000000b1'::uuid,array[1]::bigint[])->>'id')::bigint as u1 \gset
select t.ok('الطلب معلّق', (select urgent_state from appointments where id=:u1)='requested' and (select is_urgent from appointments where id=:u1) is false);
select t.fl('طلب تاني', $$select request_urgent('00000000-0000-0000-0000-0000000000b1'::uuid,array[1]::bigint[])$$);
select t.fl('الزبون يوافق نفسه', format('select decide_urgent(%s,true)',:u1));
reset role;
select set_config('p17.urgent','',true);
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.fl('الكاشير مايوافقش', format('select decide_urgent(%s,true)',:u1));
do $$ begin begin update appointments set is_urgent=true where id=(select id from appointments where urgent_state='requested' limit 1); exception when others then null; end; end $$;
reset role;
select t.ok('الكاشير مايعدلش مباشرة', (select is_urgent from appointments where urgent_state='requested' limit 1) is false);
select t.as_('00000000-0000-0000-0000-0000000000a2');
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('اللوحة فيها الطلب', (select count(*) from urgent_board() where id=:u1 and state='requested')=1);
select decide_urgent(:u1,true);
select t.ok('اتوافق', (select is_urgent from appointments where id=:u1));
select t.ok('المستعجل قبل العاديين', p11_ahead(:u1) < p11_ahead(:n1) and p11_ahead(:u1) < p11_ahead(:n2));
select t.ok('الأول في الطابور (ahead=0)', p11_ahead(:u1)=0);
select t.ok('العادي1 بقى وراه', p11_ahead(:n1)=1);
-- مستعجل ثاني من الإدارة يجي بعد الأول وقبل العاديين
select (admin_urgent_ticket('واقف','01090000021','00000000-0000-0000-0000-0000000000b1'::uuid,array[1]::bigint[])->'ticket'->>'id')::bigint as u2 \gset
select t.ok('الثاني بعد الأول', p11_ahead(:u2)=1 and p11_ahead(:n1)=2);
select t.ok('الإدارة فتحته حاضر', (select status::text from appointments where id=:u2)='checked_in');
-- الفاتورة ×2
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1}]'::jsonb,0,0,'cash',:u2,null,null) as inv \gset
select t.ok('الإجمالي ×2', (select total from invoices where id=:inv)=2*(select price from services where id=1));
select t.ok('بند الرسوم موجود', (select count(*) from invoice_items where invoice_id=:inv and name like 'رسوم مستعجل%')=1);
-- فاتورة لتذكرة عادية ما فيهاش رسوم
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1}]'::jsonb,0,0,'cash',:n1,null,null) as inv2 \gset
select t.ok('العادي بدون رسوم', (select total from invoices where id=:inv2)=(select price from services where id=1));
-- رفض
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select make_urgent(:n2);
select t.ok('تحويل تذكرة موجودة لمستعجل', (select is_urgent from appointments where id=:n2));
rollback;
\echo URGENT DONE
