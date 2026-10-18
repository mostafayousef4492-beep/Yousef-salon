\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
begin;
-- إدارة الباقات
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.fl('الكاشير مايحفظش باقة', $$select admin_save_bundle(null,'باقة','',120,true,array[1,2]::bigint[])$$);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.fl('خدمة واحدة', $$select admin_save_bundle(null,'باقة','',60,true,array[1]::bigint[])$$);
select t.fl('سعر مش أقل', $$select admin_save_bundle(null,'باقة','',150,true,array[1,2]::bigint[])$$);
select t.fl('خدمة موقوفة', $$select admin_save_bundle(null,'باقة','',60,true,array[1,3]::bigint[])$$);
select t.fl('اسم فاضي', $$select admin_save_bundle(null,' ','',100,true,array[1,2]::bigint[])$$);
select admin_save_bundle(null,'باقة الملك','قصة + دقن',120,true,array[1,2]::bigint[]) as bid \gset
select admin_save_bundle(null,'باقة مخفية','',100,false,array[1,2]::bigint[]) as hid \gset
select t.ok('الباقة اتحفظت', (select count(*) from bundle_items where bundle_id=:bid)=2);
reset role;
-- القائمة للزائر
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select t.ok('الزائر يشوف الباقة النشطة بس', jsonb_array_length(bundles_list())=1 and (bundles_list()->0->>'saving')::numeric=30 and (bundles_list()->0->>'full')::numeric=150);
select t.ok('الزائر مايشوفش الكل', jsonb_array_length(bundles_list(true))=1);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('الإدارة تشوف الكل', jsonb_array_length(bundles_list(true))=2);
-- حجز وربط
select (admin_book_ticket('عميل باقة','01090000555','00000000-0000-0000-0000-0000000000b1'::uuid,(now() at time zone my_tz())::date,current_period(),array[1,2]::bigint[])->'ticket'->>'id')::bigint as tk \gset
select (admin_book_ticket('عميل ناقص','01090000556','00000000-0000-0000-0000-0000000000b1'::uuid,(now() at time zone my_tz())::date,current_period(),array[1]::bigint[])->'ticket'->>'id')::bigint as tk2 \gset
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select t.fl('رقم غلط', format('select set_ticket_bundle(%s,%s,%L)',:tk,:bid,'01011111111'));
select t.fl('باقة مخفية', format('select set_ticket_bundle(%s,%s,%L)',:tk,:hid,'01090000555'));
select t.fl('خدمات ناقصة', format('select set_ticket_bundle(%s,%s,%L)',:tk2,:bid,'01090000556'));
select set_ticket_bundle(:tk,:bid,'01090000555');
select t.ok('ملخص الباقة', (ticket_bundle(:tk,'01090000555')->>'saving')::numeric=30 and (ticket_bundle(:tk,'01090000555')->>'price')::numeric=120);
select t.ok('الملخص مقفول لغير صاحبه', ticket_bundle(:tk,'01011111111') is null);
reset role;
select t.ok('اتربطت', (select bundle_id from appointments where id=:tk)=:bid);
-- الكاشير: دفع بخصم الباقة
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.fl('خصم يدوي مع باقة', format($q$select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1},{"type":"service","id":2,"qty":1}]'::jsonb,5,0,'cash',%s)$q$,:tk));
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1},{"type":"service","id":2,"qty":1}]'::jsonb,0,0,'cash',:tk) as inv \gset
select t.ok('خصم الباقة 30', (select subtotal=150 and discount=30 and total=120 from invoices where id=:inv));
-- تذكرة من غير الباقة كاملة: مفيش خصم
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1}]'::jsonb,0,0,'cash') as inv2 \gset
select t.ok('من غير باقة مفيش خصم', (select discount=0 from invoices where id=:inv2));
reset role;
-- باقة اتربطت لكن الفاتورة ناقصة خدمة
update appointments set bundle_id=:bid where id=:tk2;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1}]'::jsonb,0,0,'cash',:tk2) as inv3 \gset
select t.ok('فاتورة ناقصة خدمة = من غير خصم', (select discount=0 and total=100 from invoices where id=:inv3));
reset role;
rollback;
\echo BUNDLES DONE
