\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
begin;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select (admin_book_ticket('عميل دفع','01090000800','00000000-0000-0000-0000-0000000000b1'::uuid,current_date+2,'morning',array[1,2]::bigint[])->'ticket'->>'id')::bigint as tk \gset
select (admin_book_ticket('عميل دفع2','01090000801','00000000-0000-0000-0000-0000000000b2'::uuid,current_date+2,'morning',array[1]::bigint[])->'ticket'->>'id')::bigint as tk2 \gset
reset role;
set local session_replication_role=replica;
update appointments set customer_id=(select id from customers where user_id='00000000-0000-0000-0000-0000000000c1'), status='in_service' where id=:tk;
update appointments set customer_id=(select id from customers where user_id='00000000-0000-0000-0000-0000000000c2'), status='in_service' where id=:tk2;
set local session_replication_role=origin;
-- الزبون c1
select t.as_('00000000-0000-0000-0000-0000000000c1');
select t.ok('حالة قبل الطلب none', my_pay_claim(:tk)->>'status'='none');
select t.fl('تذكرة غيره', format('select submit_pay_claim(%s,''AB12345'')',:tk2));
select t.fl('رقم قصير', format('select submit_pay_claim(%s,''12'')',:tk));
select t.ok('طلب', submit_pay_claim(:tk,'VC-998877')->>'status'='pending');
select t.ok('المبلغ من السيرفر = 150', (my_pay_claim(:tk)->>'amount')::numeric=150);
select t.ok('تعديل الرقم لنفس التذكرة', submit_pay_claim(:tk,'VC-998878')->>'ref'='VC-998878');
select t.fl('الزبون مايشوفش طلبات الكاشير', format('select pay_claim_for(%s)',:tk));
reset role;
-- زبون c2 بنفس الرقم
select t.as_('00000000-0000-0000-0000-0000000000c2');
select t.fl('نفس رقم العملية لتذكرة تانية', format('select submit_pay_claim(%s,''vc-998878'')',:tk2));
reset role;
-- الكاشير
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.ok('الكاشير يشوف الطلب', pay_claim_for(:tk)->>'ref'='VC-998878');
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1},{"type":"service","id":2,"qty":1}]'::jsonb,0,0,'wallet',:tk) as inv \gset
select t.ok('بعد الفاتورة الطلب يختفي', pay_claim_for(:tk) is null);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000c1');
select t.ok('الزبون يشوف paid', my_pay_claim(:tk)->>'status'='paid');
select t.fl('مايبلّغش على تذكرة مدفوعة', format('select submit_pay_claim(%s,''ZZ99999'')',:tk));
reset role;
-- رفض
select t.as_('00000000-0000-0000-0000-0000000000c2');
select submit_pay_claim(:tk2,'RJ-111111');
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select reject_pay_claim((pay_claim_for(:tk2)->>'id')::bigint);
select t.ok('بعد الرفض مفيش طلب', pay_claim_for(:tk2) is null);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000c2');
select t.ok('الزبون يشوف rejected', my_pay_claim(:tk2)->>'status'='rejected');
select t.ok('يقدر يبعت رقم صح', submit_pay_claim(:tk2,'RJ-222222')->>'status'='pending');
reset role;
select t.as_('00000000-0000-0000-0000-0000000000b1');
select t.fl('الحلاق مايشوفش', format('select pay_claim_for(%s)',:tk2));
reset role;
rollback;
select 'PAY CLAIMS DONE';
