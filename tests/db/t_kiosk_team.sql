\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
begin;
-- نسخ محلية من جداول/دالة الكشك الموجودة في الإنتاج (المحلي ما فيهوش)
create extension if not exists pgcrypto with schema extensions;
create table if not exists kiosk_devices(id serial primary key, name text, token_hash text, active boolean default true);
create table if not exists kiosk_fails(id serial primary key, code text, at timestamptz default now());
create table if not exists staff_pins(staff_id uuid primary key, pin_hash text, updated_at timestamptz default now());
create or replace function public.kiosk_who(p_token text, p_code text, p_pin text) returns jsonb language plpgsql security definer set search_path to 'public','extensions' as $f$
declare v_p profiles; v_fails int;
begin
  if not exists (select 1 from kiosk_devices where active and token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex')) then
    return jsonb_build_object('ok', false, 'device', false, 'msg', 'الجهاز ده مش مصرّح'); end if;
  p_code := trim(coalesce(p_code, ''));
  select count(*) into v_fails from kiosk_fails where code = p_code and at > now() - interval '10 minutes';
  if v_fails >= 5 then return jsonb_build_object('ok', false, 'msg', 'محاولات غلط كتير'); end if;
  select p.* into v_p from profiles p join staff_pins s on s.staff_id = p.id where p.code = p_code and p.role::text not in ('owner','customer') and s.pin_hash = crypt(coalesce(p_pin,''), s.pin_hash) limit 1;
  if v_p.id is null then insert into kiosk_fails(code) values (p_code); return jsonb_build_object('ok', false, 'msg', 'الكود أو الـ PIN غلط'); end if;
  delete from kiosk_fails where code = p_code;
  return jsonb_build_object('ok', true, 'id', v_p.id, 'name', v_p.full_name, 'role', v_p.role::text);
end $f$;
\i sql/patch_kiosk_team.sql
insert into kiosk_devices(name, token_hash) values ('tab', encode(extensions.digest('TOK','sha256'),'hex'));
update profiles set code='C1' where id='00000000-0000-0000-0000-0000000000a2';  -- كاشير
update profiles set code='B1' where id='00000000-0000-0000-0000-0000000000b1';  -- حلاق
update profiles set code='M1' where id='00000000-0000-0000-0000-0000000000a1';
insert into staff_pins(staff_id,pin_hash) values ('00000000-0000-0000-0000-0000000000a2', extensions.crypt('1111', extensions.gen_salt('bf'))),('00000000-0000-0000-0000-0000000000b1', extensions.crypt('2222', extensions.gen_salt('bf')));
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select t.ok('كاشير يشوف الفريق', (kiosk_team('TOK','C1','1111')->>'ok')::boolean and jsonb_array_length(kiosk_team('TOK','C1','1111')->'staff') >= 3);
select t.ok('الدور اتبعت', kiosk_team('TOK','C1','1111')->>'role' = 'cashier');
select t.ok('الحلاق مايشوفش الفريق', (kiosk_team('TOK','B1','2222')->>'ok')::boolean is false);
select t.ok('PIN غلط', (kiosk_team('TOK','C1','9999')->>'ok')::boolean is false);
select t.ok('جهاز غير مصرّح', kiosk_team('BAD','C1','1111')->>'msg' = 'الجهاز ده مش مصرّح');
select t.ok('المالك مش بيدخل بالـ PIN', (kiosk_team('TOK','M1','1111')->>'ok')::boolean is false);
reset role;
rollback;
select 'KIOSK TEAM DONE';
