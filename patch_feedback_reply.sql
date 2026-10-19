-- ردود على آراء العملاء (حتى المجهولة) + رقم تواصل اختياري. شغّله بعد patch_customer_feedback.sql
-- المجهول: بيتولّد له رمز سري بيتحفظ في جهاز العميل بس، والسيرفر بيخزّن بصمة الرمز (مش العميل) — فالإدارة بتقدر ترد والعميل يشوف الرد من غير ما حد يعرف هو مين.
alter table public.customer_feedback add column if not exists secret_hash text, add column if not exists reply text, add column if not exists replied_at timestamptz, add column if not exists contact_phone text;
create index if not exists customer_feedback_secret_idx on public.customer_feedback(secret_hash) where secret_hash is not null;

drop function if exists public.send_feedback(text, boolean);
create or replace function public.send_feedback(p_message text, p_anonymous boolean default false, p_contact text default null)
returns text language plpgsql security definer set search_path = public as $$
declare c customers; v_mode text; m text := btrim(coalesce(p_message, '')); v_n int; v_anon boolean; v_sec text; v_ph text;
begin
  select * into c from customers where user_id = auth.uid();
  if c.id is null then raise exception 'مفيش حساب عميل'; end if;
  v_mode := coalesce((select value #>> '{}' from app_settings where key = 'feedback_mode'), 'choice');
  if v_mode = 'off' then raise exception 'استقبال الآراء متوقف دلوقتي'; end if;
  if length(m) < 3 or length(m) > 1000 then raise exception 'اكتب رسالة من 3 لـ 1000 حرف'; end if;
  insert into feedback_quota(customer_id, day, n) values (c.id, current_date, 1)
    on conflict (customer_id, day) do update set n = feedback_quota.n + 1 returning n into v_n;
  if v_n > 3 then raise exception 'وصلت للحد اليومي (3 رسائل). جرّب بكرة'; end if;
  v_anon := (v_mode = 'choice' and coalesce(p_anonymous, false));
  v_ph := nullif(regexp_replace(coalesce(p_contact, ''), '\D', '', 'g'), '');
  if v_ph is not null and v_ph !~ '^01\d{9}$' then raise exception 'رقم التواصل غلط'; end if;
  if v_anon then
    v_sec := replace(gen_random_uuid()::text, '-', '');
    insert into customer_feedback(customer_id, message, created_at, secret_hash, contact_phone)
      values (null, m, date_trunc('day', now()), encode(sha256(convert_to(v_sec, 'UTF8')), 'hex'), v_ph);
    return v_sec;
  end if;
  insert into customer_feedback(customer_id, message, contact_phone) values (c.id, m, v_ph);
  return null;
end $$;
revoke all on function public.send_feedback(text, boolean, text) from public, anon;
grant execute on function public.send_feedback(text, boolean, text) to authenticated;

-- رسايل العميل وردودها: بتاعته باسمه + المجهولة اللي معاه رمزها
create or replace function public.my_feedback(p_secrets text[] default '{}')
returns table(message text, created_at timestamptz, reply text, replied_at timestamptz) language plpgsql security definer stable set search_path = public as $$
declare cid bigint;
begin
  select id into cid from customers where user_id = auth.uid();
  if cid is null then raise exception 'مفيش حساب عميل'; end if;
  return query select f.message, f.created_at, f.reply, f.replied_at from customer_feedback f
    where f.customer_id = cid
       or f.secret_hash in (select encode(sha256(convert_to(s, 'UTF8')), 'hex') from unnest(coalesce(p_secrets, '{}'::text[])) s limit 20)
    order by f.created_at desc limit 50;
end $$;
revoke all on function public.my_feedback(text[]) from public, anon;
grant execute on function public.my_feedback(text[]) to authenticated;
