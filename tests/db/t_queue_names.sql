\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.anon_() returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub','',true); execute 'set local role anon'; end $$;
create or replace function t.back() returns void language plpgsql as $$ begin execute 'reset role'; end $$;
grant usage on schema t to public;
begin;
alter table appointments disable trigger user;
insert into customers(id,name,phone) values (990001,'أحمد محمود علي','01000000001'),(990002,'سارة','01000000002'),(990003,'خالد يوسف','01000000003'),(990004,'منى حسن','01000000004');
-- حلاق وهمي: أي uuid موجود في profiles
select id as b from profiles where role::text='barber' limit 1 \gset
insert into appointments(id,customer_id,barber_id,day,period,status,ticket_no,sort_at) values
 (990001,990001,:'b',current_date,'evening','in_service',901,now()-interval '4 min'),
 (990002,990002,:'b',current_date,'evening','upcoming',902,now()-interval '3 min'),
 (990003,990003,:'b',current_date,'evening','cancelled',903,now()-interval '2 min'),
 (990004,990004,:'b',current_date,'evening','upcoming',904,now()-interval '1 min');
select t.ok('الأسامي = العدد (p11_ahead)', jsonb_array_length(p23_queue_names(990004)) = p11_ahead(990004));
select t.ok('الملغي مش ظاهر', not (p23_queue_names(990004)::text like '%خالد%'));
select t.ok('الاسم الأول + حرف: أحمد م.', p23_queue_names(990004)->0->>'name' = 'أحمد م.');
select t.ok('اسم من كلمة واحدة بيفضل زي ما هو', p23_queue_names(990004)->1->>'name' = 'سارة');
select t.ok('الترتيب صح', p23_queue_names(990004)->0->>'status' = 'in_service' and p23_queue_names(990004)->1->>'status' = 'upcoming');
select t.ok('أول واحد: مفيش قدامه حد', p23_queue_names(990001) = '[]'::jsonb);
select t.ok('الرقم الكامل مش في الرد', not (p23_queue_names(990004)::text like '%0100000%'));
-- التحقق بالموبايل
select t.anon_();
select t.ok('موبايل صح بيشوف', jsonb_array_length(public_queue_names(990004,'01000000004')) = 2);
do $$ begin begin perform public_queue_names(990004,'01999999999'); raise exception 'FAIL: موبايل غلط عدّى'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: موبايل غلط اترفض'; end; end $$;
do $$ begin begin perform public_queue_names(990004,''); raise exception 'FAIL: موبايل فاضي عدّى'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: موبايل فاضي اترفض'; end; end $$;
do $$ begin begin perform p23_queue_names(990004); raise exception 'FAIL: الدالة الداخلية مفتوحة للعامة'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: الدالة الداخلية مقفولة'; end; end $$;
select t.back();
-- الإيقاف من الإعدادات
insert into app_settings(key,value) values ('queue_show_names','false') on conflict (key) do update set value='false';
select t.ok('الإعداد مقفول = قايمة فاضية', p23_queue_names(990004) = '[]'::jsonb);
rollback;
select 'QUEUE NAMES DONE';
