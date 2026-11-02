\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS: % [%]', n, sqlerrm; return; end; raise exception 'FAIL (no error): %', n; end $$;
grant usage on schema t to public;
\set own '00000000-0000-0000-0000-0000000000a1'
\set cash '00000000-0000-0000-0000-0000000000a2'
\set bar '00000000-0000-0000-0000-0000000000b1'
begin;
\i patch_role_perms.sql
delete from role_perms; 
\i patch_role_perms.sql
select t.ok('الأصل: الكاشير ليه use_pos و cash_ops والكوفي', (perm_defaults('cashier')->>'use_pos')::boolean and (perm_defaults('cashier')->>'cash_ops')::boolean and (perm_defaults('cashier')->>'use_cafe')::boolean);
select t.ok('الحلاق ليه عمولته وملوش use_pos', (perm_defaults('barber')->>'view_own_commission')::boolean and not coalesce((perm_defaults('barber')->>'use_pos')::boolean,false));
update profiles set perms='{}' where id in (:'cash', :'bar');
select t.as_(:'cash');
select t.ok('has_perm للكاشير زي الأول', has_perm('use_pos') and has_perm('view_invoices') and not has_perm('view_reports'));
reset role;
select t.ok('الكاشير cash_ops والكوفي من الافتراضي', p16_cash_ops() and can_use_cafe());
select t.as_(:'cash');
select t.ok('الواجهة تقرا الافتراضي', role_perm_defaults() ? 'cashier');
select t.fl('الكاشير مايعدّلش الأدوار', $q$select set_role_perms('cashier','{"use_pos":true}')$q$);
select t.fl('الكاشير مايشغّلش التنضيف', $q$select clean_perm_overrides()$q$);
reset role;
select t.as_(:'own');
select set_role_perms('cashier','{"use_pos":true,"view_stock":true,"view_invoices":false,"manage_appts":true,"view_customers":true,"use_attendance":true}');
select t.fl('مفتاح مش معروف', $q$select set_role_perms('cashier','{"hack":true}')$q$);
select t.fl('قيمة مش boolean', $q$select set_role_perms('cashier','{"use_pos":"x"}')$q$);
select t.fl('دور غلط', $q$select set_role_perms('owner','{"use_pos":true}')$q$);
reset role;
select t.ok('الافتراضي اتغيّر', not coalesce((perm_defaults('cashier')->>'view_invoices')::boolean,false) and not coalesce((perm_defaults('cashier')->>'cash_ops')::boolean,false));
select t.as_(:'cash');
select t.ok('الكاشير فقد view_invoices', not has_perm('view_invoices'));
reset role;
select t.ok('الكاشير فقد cash_ops', not p16_cash_ops());
select t.as_(:'cash');
select t.ok('الكوفي: الدور مفيهوش use_cafe فبيتبع use_pos', can_use_cafe());
reset role;
select t.ok('اتسجل في settings_history', exists (select 1 from settings_history where key='role_perms:cashier'));
-- التنضيف: استثناء مطابق يتشال ومختلف يفضل
update profiles set perms = '{"use_pos":true,"view_reports":false,"view_invoices":true,"cafe_only":true,"use_cafe":true}' where id = :'cash';
select t.as_(:'own');
select clean_perm_overrides();
reset role;
select t.ok('المطابق اتشال (use_pos, view_reports=false)', not (select perms ? 'use_pos' or perms ? 'view_reports' from profiles where id=:'cash'));
select t.ok('المختلف فضل + الكوفي ماتلمسش', (select perms ? 'view_invoices' and perms ? 'cafe_only' and perms ? 'use_cafe' from profiles where id=:'cash'));
select t.as_(:'cash');
select t.ok('الصلاحية الفعلية بعد التنضيف: use_pos لسه شغال', has_perm('use_pos') and not has_perm('view_reports'));
reset role;
rollback;
select 'ALL ROLE-PERMS TESTS PASSED';
