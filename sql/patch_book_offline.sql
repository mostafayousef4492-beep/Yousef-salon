-- patch_book_offline.sql — حجز دور من غير إنترنت (بيتبعت لما النت يرجع) من غير ما يتحجز مرتين
-- العميل بيحجز وهو أوفلاين، الطلب بيتحفظ على موبايله، ولما النت يرجع التطبيق بيبعته بمعرّف عملية (request_id).
-- لو الإرسال اتكرر (النت قطع بعد ما وصل مثلًا) السيرفر بيرجّع نفس الدور القديم بدل ما يعمل حجز تاني.
-- الحجز نفسه بينفّذ book_ticket بكل قواعده (الحجز مفتوح؟ التاريخ؟ الحلاق؟ الزحمة؟) فلو الدور اتملى بيرجع خطأ والعميل بيتنبّه.
-- لازم book_ticket (patch_dependents.sql) يكون متشغّل. آمن للتشغيل أكتر من مرة.
create table if not exists public.booking_receipts(
  request_id uuid primary key,
  user_id uuid not null,
  appointment_id bigint not null,
  created_at timestamptz not null default now()
);
alter table public.booking_receipts enable row level security;
revoke all on public.booking_receipts from public, anon, authenticated;

create or replace function public.book_ticket_offline(p_request_id uuid, p_barber uuid, p_day date, p_period text, p_services bigint[], p_for bigint default null) returns bigint
language plpgsql security definer set search_path to 'public' as $$
declare v_id bigint; v_old booking_receipts;
begin
  if auth.uid() is null then raise exception 'غير مصرح'; end if;
  if p_request_id is null then raise exception 'معرّف العملية ناقص'; end if;
  perform pg_advisory_xact_lock(hashtext('bko' || p_request_id::text));
  select * into v_old from booking_receipts where request_id = p_request_id;
  if found then
    if v_old.user_id <> auth.uid() then raise exception 'معرّف العملية مستخدم بحساب آخر'; end if;
    return v_old.appointment_id;
  end if;
  v_id := book_ticket(p_barber, p_day, p_period, p_services, p_for);
  insert into booking_receipts(request_id, user_id, appointment_id) values (p_request_id, auth.uid(), v_id);
  return v_id;
end $$;
revoke all on function public.book_ticket_offline(uuid, uuid, date, text, bigint[], bigint) from public, anon;
grant execute on function public.book_ticket_offline(uuid, uuid, date, text, bigint[], bigint) to authenticated;
-- تراجع: drop function book_ticket_offline(uuid, uuid, date, text, bigint[], bigint); drop table booking_receipts;
