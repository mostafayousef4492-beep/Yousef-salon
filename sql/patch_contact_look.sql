-- ============================================================================
-- patch_contact_look.sql — المرحلة 1: مركز التواصل + ملف اللوك (نص)
-- كله إضافات: مفيش حذف لبيانات موجودة.
-- ============================================================================

-- ===== 1) مركز التواصل: نوع الرسالة وحالتها =====
alter table public.customer_feedback add column if not exists kind   text not null default 'feedback';
alter table public.customer_feedback add column if not exists status text not null default 'new';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'customer_feedback_kind_chk') then
    alter table public.customer_feedback add constraint customer_feedback_kind_chk check (kind in ('feedback','inquiry','complaint','request'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'customer_feedback_status_chk') then
    alter table public.customer_feedback add constraint customer_feedback_status_chk check (status in ('new','in_progress','done'));
  end if;
end $$;
update public.customer_feedback set status = 'done' where reply is not null and status = 'new';

-- send_feedback: نفس القواعد القديمة + نوع الرسالة (الاستدعاء القديم بـ 3 باراميترات لسه شغال)
drop function if exists public.send_feedback(text, boolean, text);
create or replace function public.send_feedback(p_message text, p_anonymous boolean default false, p_contact text default null, p_kind text default 'feedback')
returns text
language plpgsql security definer
set search_path to 'public'
as $fn$
declare c customers; v_mode text; m text := btrim(coalesce(p_message, '')); v_n int; v_anon boolean; v_sec text; v_ph text;
        v_kind text := case when p_kind in ('feedback','inquiry','complaint','request') then p_kind else 'feedback' end;
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
    insert into customer_feedback(customer_id, message, created_at, secret_hash, contact_phone, kind)
      values (null, m, date_trunc('day', now()), encode(sha256(convert_to(v_sec, 'UTF8')), 'hex'), v_ph, v_kind);
    return v_sec;
  end if;
  insert into customer_feedback(customer_id, message, contact_phone, kind) values (c.id, m, v_ph, v_kind);
  return null;
end $fn$;

-- my_feedback: بنرجّع كمان النوع والحالة (العميل يتابع رسايله)
drop function if exists public.my_feedback(text[]);
create or replace function public.my_feedback(p_secrets text[] default '{}'::text[])
returns table(message text, created_at timestamptz, reply text, replied_at timestamptz, kind text, status text)
language plpgsql stable security definer
set search_path to 'public'
as $fn$
declare cid bigint;
begin
  select id into cid from customers where user_id = auth.uid();
  if cid is null then raise exception 'مفيش حساب عميل'; end if;
  return query select f.message, f.created_at, f.reply, f.replied_at, f.kind, f.status from customer_feedback f
    where f.customer_id = cid
       or f.secret_hash in (select encode(sha256(convert_to(s, 'UTF8')), 'hex') from unnest(coalesce(p_secrets, '{}'::text[])) s limit 20)
    order by f.created_at desc limit 50;
end $fn$;

-- إشعار فوري للعميل لما الإدارة تردّ (للرسايل باسمه؛ المجهولة بتظهر في التطبيق بس)
create or replace function public.trg_feedback_reply()
returns trigger language plpgsql security definer set search_path to 'public' as $fn$
begin
  if new.customer_id is not null and new.reply is not null and btrim(new.reply) <> '' and new.reply is distinct from old.reply then
    insert into customer_notifications(customer_id, kind, title, body) values (new.customer_id, 'feedback_reply', 'رد من الإدارة 💬', left(new.reply, 140));
  end if;
  return new;
end $fn$;
drop trigger if exists trg_feedback_reply on public.customer_feedback;
create trigger trg_feedback_reply after update of reply on public.customer_feedback for each row execute function public.trg_feedback_reply();

revoke all on function public.send_feedback(text, boolean, text, text) from public, anon;
revoke all on function public.my_feedback(text[]) from public, anon;
grant execute on function public.send_feedback(text, boolean, text, text) to authenticated;
grant execute on function public.my_feedback(text[]) to authenticated;

-- ===== 2) ملف اللوك (نص بس) =====
create table if not exists public.customer_looks (
  customer_id bigint primary key references public.customers(id) on delete cascade,
  last_cut    text,   -- آخر قصة
  clipper     text,   -- رقم الماكينة
  grade       text,   -- درجات التدريج
  beard_style text,   -- شكل تحديد الدقن
  notes       text,   -- ملاحظات الحلاق عن اللوك
  updated_by  uuid,
  updated_at  timestamptz not null default now()
);
alter table public.customer_looks enable row level security;
drop policy if exists "mgr looks" on public.customer_looks;
create policy "mgr looks" on public.customer_looks for all using (is_mgr()) with check (is_mgr());

-- الحلاق بيشوف/يكتب لوك العميل اللي على تذكرته هو بس (مفيش بحث ولا سجل)
create or replace function public.p_look_json(p_customer bigint)
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select coalesce((select jsonb_build_object('last_cut', l.last_cut, 'clipper', l.clipper, 'grade', l.grade, 'beard_style', l.beard_style, 'notes', l.notes, 'updated_at', l.updated_at)
                   from customer_looks l where l.customer_id = p_customer), '{}'::jsonb) $fn$;

create or replace function public.p_look_upsert(p_customer bigint, p_last_cut text, p_clipper text, p_grade text, p_beard text, p_notes text)
returns void language plpgsql security definer set search_path to 'public' as $fn$
declare f text[] := array[left(btrim(coalesce(p_last_cut,'')),200), left(btrim(coalesce(p_clipper,'')),100), left(btrim(coalesce(p_grade,'')),100), left(btrim(coalesce(p_beard,'')),200), left(btrim(coalesce(p_notes,'')),600)];
begin
  insert into customer_looks(customer_id, last_cut, clipper, grade, beard_style, notes, updated_by, updated_at)
  values (p_customer, nullif(f[1],''), nullif(f[2],''), nullif(f[3],''), nullif(f[4],''), nullif(f[5],''), auth.uid(), now())
  on conflict (customer_id) do update set last_cut = excluded.last_cut, clipper = excluded.clipper, grade = excluded.grade,
    beard_style = excluded.beard_style, notes = excluded.notes, updated_by = excluded.updated_by, updated_at = now();
end $fn$;

create or replace function public.look_for_ticket(p_appt bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare a appointments;
begin
  select * into a from appointments where id = p_appt;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  if not (is_mgr() or (a.barber_id = auth.uid() and a.status in ('upcoming','checked_in','in_service'))) then raise exception 'غير مصرح'; end if;
  if a.customer_id is null then return '{}'::jsonb; end if;
  return p_look_json(a.customer_id);
end $fn$;

create or replace function public.look_save_for_ticket(p_appt bigint, p_last_cut text, p_clipper text, p_grade text, p_beard text, p_notes text)
returns void language plpgsql security definer set search_path to 'public' as $fn$
declare a appointments;
begin
  select * into a from appointments where id = p_appt;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  if not (is_mgr() or (a.barber_id = auth.uid() and (a.status in ('upcoming','checked_in','in_service')
          or (a.status = 'done' and a.completed_at > now() - interval '30 minutes')))) then raise exception 'غير مصرح'; end if;
  if a.customer_id is null then raise exception 'مفيش عميل مسجّل على التذكرة دي'; end if;
  perform p_look_upsert(a.customer_id, p_last_cut, p_clipper, p_grade, p_beard, p_notes);
end $fn$;

create or replace function public.look_get(p_customer bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  return p_look_json(p_customer);
end $fn$;

create or replace function public.look_save(p_customer bigint, p_last_cut text, p_clipper text, p_grade text, p_beard text, p_notes text)
returns void language plpgsql security definer set search_path to 'public' as $fn$
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  perform p_look_upsert(p_customer, p_last_cut, p_clipper, p_grade, p_beard, p_notes);
end $fn$;

create or replace function public.my_look()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare cid bigint;
begin
  select id into cid from customers where user_id = auth.uid();
  if cid is null then raise exception 'مفيش حساب عميل'; end if;
  return p_look_json(cid);
end $fn$;

revoke all on function public.p_look_json(bigint), public.p_look_upsert(bigint,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.look_for_ticket(bigint), public.look_save_for_ticket(bigint,text,text,text,text,text),
  public.look_get(bigint), public.look_save(bigint,text,text,text,text,text), public.my_look() from public, anon;
grant execute on function public.look_for_ticket(bigint), public.look_save_for_ticket(bigint,text,text,text,text,text),
  public.look_get(bigint), public.look_save(bigint,text,text,text,text,text), public.my_look() to authenticated;
