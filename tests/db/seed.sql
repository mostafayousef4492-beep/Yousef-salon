truncate appointments, appointment_services, customers, profiles, services, app_settings, ticket_events, ticket_transfers, customer_notifications, invoices restart identity cascade;
delete from auth.users;
insert into auth.users(id,email) values
 ('00000000-0000-0000-0000-0000000000a1','owner@staff.x'),('00000000-0000-0000-0000-0000000000a2','cash@staff.x'),
 ('00000000-0000-0000-0000-0000000000b1','b1@staff.x'),('00000000-0000-0000-0000-0000000000b2','b2@staff.x'),
 ('00000000-0000-0000-0000-0000000000c1','01000000001@c.x'),('00000000-0000-0000-0000-0000000000c2','01000000002@c.x'),('00000000-0000-0000-0000-0000000000c3','01000000003@c.x');
alter table profiles disable trigger all;
insert into profiles(id,full_name,role,created_at) values
 ('00000000-0000-0000-0000-0000000000a1','المالك','owner',now()-interval '9 d'),
 ('00000000-0000-0000-0000-0000000000a2','الكاشير','cashier',now()-interval '8 d'),
 ('00000000-0000-0000-0000-0000000000b1','أحمد','barber',now()-interval '7 d'),
 ('00000000-0000-0000-0000-0000000000b2','محمود','barber',now()-interval '6 d');
alter table profiles enable trigger all;
insert into customers(user_id,name,phone) values
 ('00000000-0000-0000-0000-0000000000c1','عميل1','01000000001'),('00000000-0000-0000-0000-0000000000c2','عميل2','01000000002'),('00000000-0000-0000-0000-0000000000c3','عميل3','01000000003');
insert into services(name,price,duration_min,active) values ('قصة',100,20,true),('دقن',50,10,true),('قديمة',10,10,false);
