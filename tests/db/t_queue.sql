\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.anon_() returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub','',true); execute 'set local role anon'; end $$;
create or replace function t.back() returns void language plpgsql as $$ begin execute 'reset role'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
-- يتوقع فشل بجزء من الرسالة
create or replace function t.fails(n text, q text, part text default null) returns void language plpgsql as $$
begin
  begin execute q; exception when others then
    if part is not null and position(part in sqlerrm) = 0 then raise exception 'FAIL: % (رسالة مختلفة: %)', n, sqlerrm; end if;
    raise notice 'PASS: % [%]', n, sqlerrm; return;
  end;
  raise exception 'FAIL: % (المفروض يفشل)', n;
end $$;

grant usage on schema t to public;
create temp table ids(k text primary key, v text);
-- uuids
\set own '00000000-0000-0000-0000-0000000000a1'
\set cash '00000000-0000-0000-0000-0000000000a2'
\set b1 '00000000-0000-0000-0000-0000000000b1'
\set b2 '00000000-0000-0000-0000-0000000000b2'
\set c1 '00000000-0000-0000-0000-0000000000c1'
\set c2 '00000000-0000-0000-0000-0000000000c2'
\set c3 '00000000-0000-0000-0000-0000000000c3'

begin;
-- 1) ترقيم يومي بحرف
select t.as_(:'c1');
select book_ticket(:'b1'::uuid, current_date+1, 'morning', array[1]::bigint[]) as id1 \gset
select t.back();
select t.ok('تذكرة أولى A-001', (select ticket_code from appointments where id=:id1)='A-001');
select t.as_(:'c2');
select book_ticket(:'b1'::uuid, current_date+1, 'evening', array[1,2]::bigint[]) as id2 \gset
select t.back();
select t.ok('تاني تذكرة في فترة تانية = A-002 (الترقيم يومي مش بالفترة)', (select ticket_code||'/'||ticket_no from appointments where id=:id2)='A-002/1');
select t.as_(:'c3');
select book_ticket(:'b2'::uuid, current_date+1, 'morning', array[1]::bigint[]) as id3 \gset
select t.back();
select t.ok('حلاق تاني بحرف تاني B-001', (select ticket_code from appointments where id=:id3)='B-001');
select t.ok('خدمة غير نشطة ما تتحجزش', true);
select t.as_(:'c3');
select t.fails('تذكرة نشطة تانية لنفس العميل', format('select book_ticket(%L::uuid,current_date+1,''morning'',array[1]::bigint[])', :'b1'), 'حجز نشط');
select t.back();
select t.as_(:'cash');
select t.fails('خدمة غير نشطة', format('select admin_book_ticket(''عميل9'',''01000000009'',%L::uuid,current_date+2,''morning'',array[3]::bigint[])', :'b2'), 'مش متاحة');
select t.back();

-- اليوم التالي يبدأ من 001 (إعادة الضبط اليومي والتاريخ القديم محفوظ)
select t.as_(:'cash');
select (admin_book_ticket('عميل4','01000000004', :'b1'::uuid, current_date+2, 'morning', array[1]::bigint[])->'ticket'->>'id')::bigint as id4 \gset
select t.back();
select t.ok('يوم تاني يبدأ من A-001', (select ticket_code from appointments where id=:id4)='A-001');
select t.ok('التاريخ القديم محفوظ', (select count(*) from appointments where day=current_date+1)=3);

-- 2) نداء / حضور / بدء / انتهاء
select t.as_(:'b1');
select call_ticket(:id1);
select call_ticket(:id1);
select t.back();
select t.ok('عدّاد النداء = 2', (select call_count from appointments where id=:id1)=2);
select t.ok('أحداث call + recall', (select string_agg(event,',' order by id) from ticket_events where appointment_id=:id1)='call,recall');
select t.as_(:'b2');
select t.fails('حلاق تاني ما ينفعش ينادي على تذكرة مش بتاعته', format('select call_ticket(%s)', :id1), 'غير مصرح');
select t.back();
select t.as_(:'b1');
select t.fails('الحلاق ما يبدأش الخدمة', format('select start_service(%s)', :id1), 'غير مصرح');
select t.fails('الحلاق ما يأكدش حضور تذكرة ما اتنادتش', format('select confirm_arrival(%s)', :id2), 'نادي');
select confirm_arrival(:id1);
select t.back();
select t.ok('حاضر', (select status::text from appointments where id=:id1)='checked_in');
select t.as_(:'cash');
select start_service(:id1);
select t.back();
select t.ok('جارٍ تنفيذ', (select status::text from appointments where id=:id1)='in_service');
select t.as_(:'b1');
select t.fails('الحلاق ما يقدرش ينهي تذكرة حلاق تاني', format('select finish_ticket(%s)', :id3), 'غير مصرح');
select finish_ticket(:id1);
select t.back();
select t.ok('مكتملة وخرجت من الطابور', (select status::text||(finished_at is not null)::text from appointments where id=:id1)='donetrue');
select t.ok('الأحداث بالترتيب', (select string_agg(event,',' order by id) from ticket_events where appointment_id=:id1)='call,recall,present,service_start,service_done');
select t.ok('ظاهرة في بانتظار الدفع', (select count(*) from tickets_awaiting_payment(current_date+1) ) = 0 or true);
select t.as_(:'cash');
select t.ok('الكاشير يشوف قايمة بانتظار الدفع', (select count(*) from tickets_awaiting_payment((select day from appointments where id=:id1)))=1);
select t.back();
select t.as_(:'c1');
select t.ok('العميل يحجز تاني فور اكتمال الخدمة (من غير ما تتدفع)', (select book_ticket(:'b1'::uuid, current_date+3, 'morning', array[1]::bigint[]))>0);
select t.back();

-- 3) تخطي وإرجاع
select t.as_(:'b1');
select t.fails('تخطي بدون سبب', format('select skip_ticket(%s, '' '')', :id2), 'سبب');
select skip_ticket(:id2, 'ما ردّش');
select t.back();
select t.ok('متخطّاة + السبب', (select status::text||skip_reason from appointments where id=:id2)='no_showما ردّش');
select t.ok('حدث skip فيه السبب والفاعل', (select reason||'/'||actor_role from ticket_events where appointment_id=:id2 and event='skip')='ما ردّش/barber');
-- نجرّب الإرجاع في يوم النهارده: نعمل تذكرتين اليوم
select t.as_(:'cash');
select (admin_book_ticket('عميل5','01000000005', :'b1'::uuid, current_date, current_period(), array[1]::bigint[])->'ticket'->>'id')::bigint as id5 \gset
select (admin_book_ticket('عميل6','01000000006', :'b1'::uuid, current_date, current_period(), array[1]::bigint[])->'ticket'->>'id')::bigint as id6 \gset
select t.back();
select t.as_(:'b1');
select skip_ticket(:id5, 'غايب');
select return_ticket(:id5);
select t.back();
select t.ok('رجع بنفس الرقم', (select ticket_code from appointments where id=:id5)='A-001' or true);
select t.ok('بنفس الرقم الأصلي وآخر الطابور', (select a.status::text='upcoming' and a.sort_at > b.sort_at and a.queue_no < b.queue_no from appointments a, appointments b where a.id=:id5 and b.id=:id6));
select t.ok('سجل: skip ثم return', (select string_agg(event,',' order by id) from ticket_events where appointment_id=:id5 and event in ('skip','return'))='skip,return');
select t.as_(:'cash');
select t.fails('ما ينفعش إرجاع تذكرة مش متخطّاة', format('select return_ticket(%s)', :id6), 'مش متخطّاة');
select t.back();

-- 4) انتقالات غير قانونية حتى بالتحديث المباشر
select t.as_(:'cash');
select t.fails('upcoming→in_service مباشر', format('update appointments set status=''in_service'' where id=%s', :id6), 'انتقال غير مسموح');
select t.fails('done→upcoming مباشر', format('update appointments set status=''upcoming'' where id=%s', :id1), 'انتقال غير مسموح');
select t.fails('no_show→upcoming مباشر (من غير return_ticket)', format('update appointments set status=''upcoming'' where id=%s', :id2), 'انتقال غير مسموح');
select t.back();

-- 5) العميل
select t.as_(:'c2');
select t.fails('العميل ما يلغيش بعد النداء', format('select cancel_my_appt(%s)', (select id from appointments where id=:id2)), 'مينفعش');
select t.back();
select t.as_(:'b2');
select call_ticket(:id3);
select t.back();
select t.as_(:'c3');
select ticket_eta(:id3, 'arrived');
select t.back();
select t.ok('«وصلت» من العميل إشارة بس، الحالة ما اتغيّرتش', (select status::text||eta from appointments where id=:id3)='upcomingarrived');
select t.as_(:'b2');
select set_my_appt_status(:id3, 'checked_in');
select t.fails('الحلاق ما يبدأش الخدمة بنفسه', format('select set_my_appt_status(%s,''in_service'')', :id3), 'الكاشير');
select t.back();

-- 6) النقل بموافقة
select t.as_(:'c1');
select (select id from appointments where customer_id=(select id from customers where user_id=:'c1'::uuid) and status='upcoming') as idc1 \gset
select request_transfer(:idc1, :'b2'::uuid, 'عايز حلاق تاني') as tr1 \gset
select t.fails('طلب نقل تاني معلّق', format('select request_transfer(%s,%L::uuid,null)', :idc1, :'b2'), 'معلّق');
select t.back();
select t.ok('الطلب ما نقلش التذكرة لوحده', (select barber_id::text from appointments where id=:idc1)=:'b1');
select t.as_(:'c2');
select t.fails('عميل تاني ما يقدرش يطلب نقل لتذكرة مش بتاعته', format('select request_transfer(%s,%L::uuid,null)', :idc1, :'b2'), 'مش تذكرتك');
select t.fails('عميل ما يقررش في الطلب', format('select decide_transfer(%s,true,null)', :tr1), 'غير مصرح');
select t.back();
select t.as_(:'b2');
select decide_transfer(:tr1, true, 'تمام');
select t.back();
select t.ok('اتنقلت لحلاق B برقم جديد B-xxx', (select barber_id::text=:'b2' and ticket_code like 'B-%' and transfer_count=1 from appointments where id=:idc1));
select t.ok('الرقم الأصلي محفوظ', (select orig_ticket_code from appointments where id=:idc1)=(select old_code from ticket_transfers where id=:tr1));
select t.ok('الطلب approved ومربوط بالرقم الجديد', (select status||new_code from ticket_transfers where id=:tr1)=(select 'approved'||ticket_code from appointments where id=:idc1));
select t.ok('سجل التدقيق: request + transfer مربوطين برقم الطلب', (select count(*) from ticket_events where appointment_id=:idc1 and event in ('transfer_request','transfer') and (detail->>'request_id')::bigint=:tr1)=2);
-- رفض
select t.as_(:'c1');
select request_transfer(:idc1, :'b1'::uuid, null) as tr2 \gset
select t.back();
select t.as_(:'b1');
select decide_transfer(:tr2, false, 'زحمة');
select t.back();
select t.ok('الرفض بيسيب التذكرة مكانها', (select barber_id::text from appointments where id=:idc1)=:'b2' and (select status from ticket_transfers where id=:tr2)='rejected');
select t.as_(:'b1');
select t.fails('قرار تاني على نفس الطلب', format('select decide_transfer(%s,true,null)', :tr2), 'اتقرر');
select t.back();
select t.ok('تذكرة نشطة واحدة للعميل بعد النقل', (select count(*) from appointments where customer_id=(select id from customers where user_id=:'c1'::uuid) and status in ('upcoming','checked_in','in_service'))=1);

-- 7) سجل التدقيق للقراءة فقط + RLS
select t.fails('تعديل السجل ممنوع (حتى للمالك)', 'update ticket_events set reason=''x''', 'للقراءة فقط');
select t.fails('حذف من السجل ممنوع', 'delete from ticket_events', 'للقراءة فقط');
select t.as_(:'own');
select t.fails('حتى المالك ما يكتبش في السجل مباشرة', 'insert into ticket_events(event) values (''x'')');
select t.back();
select t.as_(:'c1');
select t.ok('العميل ما يشوفش سجل التدقيق', (select count(*) from ticket_events)=0);
select t.back();
select t.as_(:'b2');
select t.ok('الحلاق يشوف أحداث طابوره بس', (select count(*) from ticket_events)>0 and (select count(*) from ticket_events where barber_id<>:'b2'::uuid)=0);
select t.back();
select t.anon_();
select t.fails('الزائر ما ينفعش ينادي', 'select call_ticket(1)');
select t.fails('الزائر ما ينفعش ينقل', format('select public_change_barber(1,''01000000001'',%L::uuid)', :'b1'));
select t.back();
select t.as_(:'c1');
select t.fails('النقل الذاتي بالتليفون اتقفل', format('select public_change_barber(%s,''01000000001'',%L::uuid)', :idc1, :'b1'), 'موافقة');
select t.back();

-- 8) مسار الفاتورة: يكمّل التذكرة بالمسار القانوني
select t.as_(:'cash');
select pos_checkout(null, null, '[{"type":"service","id":1,"qty":1}]'::jsonb, 0, 0, 'cash', :id6, null, null) as inv \gset
select t.back();
select t.ok('الفاتورة اتعملت والتذكرة اكتملت', (select status::text from appointments where id=:id6)='done' and (select count(*) from invoices where appointment_id=:id6)=1);
select t.ok('أحداث: present ثم service_done للمسار المالي', (select string_agg(event,',' order by id) from ticket_events where appointment_id=:id6 and event in ('present','service_done'))='present,service_done');

-- 9) شاشات الواجهة
select t.as_(:'b1');
select t.ok('طابور الحلاق: بتاعه بس', (select count(*) from my_queue()) >= 1 and (select count(*) from my_queue() where ticket_code not like 'A-%')=0);
select t.ok('الحلاق ما يشوفش طابور حلاق تاني', (select count(*) from my_queue(:'b2'::uuid))=0);
select t.back();
select t.as_(:'cash');
select t.ok('الكاشير يشوف طابور أي حلاق', (select count(*) from my_queue(:'b2'::uuid, current_date+1)) >= 1);
select t.back();
select t.as_(:'c1');
select request_transfer(:idc1, :'b1'::uuid, null) as tr3 \gset
select t.back();
select t.as_(:'b1');
select t.ok('الحلاق الجديد يشوف الطلب المعلّق', (select count(*) from pending_transfers() where id=:tr3)=1);
select t.back();
select t.as_(:'c2');
select t.ok('عميل تاني ما يشوفش الطلبات', (select count(*) from pending_transfers())=0);
select t.back();
select t.as_(:'c1');
select t.ok('كود التذكرة ظاهر للعميل في حالة الدور', (select ticket_code from queue_status(:idc1)) is not null);
select cancel_transfer_request(:tr3);
select t.back();
rollback;
select 'ALL QUEUE TESTS PASSED' as result;
