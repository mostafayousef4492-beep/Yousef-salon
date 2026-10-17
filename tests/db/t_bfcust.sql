\set ON_ERROR_STOP 1
begin;
insert into customers(name) values ('عميل باك');
select id as cid from customers where name='عميل باك' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
set local role authenticated;
select admin_backfill_invoices((current_date-3), jsonb_build_array(jsonb_build_object('customer',:cid,'method','cash','time','14:00','items','[{"type":"service","id":1,"qty":1}]'::jsonb)),false);
reset role;
select (select customer_id=:cid from invoices order by id desc limit 1) as linked, (select visits from customers where id=:cid) v, (select points from customers where id=:cid)>0 pts;
rollback;
