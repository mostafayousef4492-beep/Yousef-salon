-- آراء العملاء: رسالة من العميل للإدارة. وضعين (إعداد feedback_mode): named = باسم العميل دايمًا · choice = العميل يختار «باسمي» أو «من غير اسم» · off = متوقفة.
-- الرسالة «من غير اسم» مجهولة فعلًا: customer_id = null والتاريخ بيتسجّل باليوم بس، فمفيش حد (ولا المالك) يقدر يعرف صاحبها.
create table if not exists public.customer_feedback (
  id bigserial primary key,
  customer_id bigint references customers(id) on delete set null,   -- null = مجهول
  message text not null check (length(message) between 3 and 1000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
alter table public.customer_feedback enable row level security;
drop policy if exists "mgr feedback" on public.customer_feedback;
create policy "mgr feedback" on public.customer_feedback for all to authenticated using (is_mgr()) with check (is_mgr());
grant select, update, delete on public.customer_feedback to authenticated;
grant usage, select on sequence public.customer_feedback_id_seq to authenticated;

-- عدّاد يومي لمنع الإزعاج (من غير ربط بالرسالة)
create table if not exists public.feedback_quota (customer_id bigint not null, day date not null, n int not null default 0, primary key (customer_id, day));
alter table public.feedback_quota enable row level security;

create or replace function public.send_feedback(p_message text, p_anonymous boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare c customers; v_mode text; m text := btrim(coalesce(p_message, '')); v_n int; v_anon boolean;
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
  if v_anon then
    insert into customer_feedback(customer_id, message, created_at) values (null, m, date_trunc('day', now()));
  else
    insert into customer_feedback(customer_id, message) values (c.id, m);
  end if;
end $$;
revoke all on function public.send_feedback(text, boolean) from public, anon;
grant execute on function public.send_feedback(text, boolean) to authenticated;
