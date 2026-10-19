begin;
insert into services(name,price,group_name,option_label) values('قص — كلاسيك',50,'قص','كلاسيك'),('قص — تدريج',70,'قص','تدريج');
do $$ begin begin insert into services(name,price,group_name,option_label) values('x',1,'قص','كلاسيك'); raise exception 'dup allowed'; exception when unique_violation then null; end;
begin insert into services(name,price,group_name) values('y',1,'قص'); raise exception 'half allowed'; exception when check_violation then null; end; end $$;
select 'OPTIONS DB OK';
rollback;
