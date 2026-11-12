-- مكافأة متابعة السوشيال: العميل يدوس «تابعت» والكاشير/المدير يوافق بعد ما يتأكد، فبيتضاف له N نقطة (مرة واحدة لكل عميل على أي منصة).
-- مفيش تحقق تلقائي من المتابعة (المنصات مفيهاش API للصالون)، فالموافقة يدوية. آمن للتكرار.
create table if not exists public.social_follow_claims (
  id bigserial primary key,
  customer_id bigint not null references public.customers(id) on delete cascade,
  platform text not null check (platform in ('tiktok','instagram','facebook')),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  decided_by uuid, decided_at timestamptz,
  unique (customer_id, platform)
);
alter table public.social_follow_claims enable row level security;

-- اللينكات وعدد النقط (بتتعدّل من app_settings)
insert into public.app_settings(key, value) values
  ('social_tiktok',    to_jsonb('https://www.tiktok.com/@mostafayousef100'::text)),
  ('social_instagram', to_jsonb('https://www.instagram.com/abo_yosef_33'::text)),
  ('social_facebook',  to_jsonb('https://www.facebook.com/share/1J3SYqw9KK/'::text)),
  ('social_follow_points', to_jsonb(10))
on conflict (key) do nothing;

create or replace function public.my_social_claims()
returns table(platform text, status text) language sql stable security definer set search_path to 'public' as $$
  select s.platform, s.status from social_follow_claims s join customers c on c.id = s.customer_id where c.user_id = auth.uid() $$;

create or replace function public.claim_social_follow(p_platform text)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_c bigint;
begin
  if p_platform not in ('tiktok','instagram','facebook') then raise exception 'منصة غير معروفة'; end if;
  select id into v_c from customers where user_id = auth.uid() and guardian_id is null;
  if v_c is null then raise exception 'سجّل بياناتك الأول'; end if;
  if exists (select 1 from social_follow_claims where customer_id = v_c and status = 'approved') then raise exception 'خدت المكافأة قبل كده'; end if;
  insert into social_follow_claims(customer_id, platform) values (v_c, p_platform) on conflict (customer_id, platform) do nothing;
end $$;

create or replace function public.admin_social_claims()
returns table(id bigint, platform text, created_at timestamptz, customer_id bigint, name text, phone text)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not (is_mgr() or has_perm('use_pos')) then raise exception 'غير مصرح'; end if;
  return query select s.id, s.platform, s.created_at, c.id, c.name, c.phone
    from social_follow_claims s join customers c on c.id = s.customer_id where s.status = 'pending' order by s.id;
end $$;

create or replace function public.admin_decide_social(p_id bigint, p_ok boolean)
returns integer language plpgsql security definer set search_path to 'public' as $$
declare s social_follow_claims; v_pts int;
begin
  if not (is_mgr() or has_perm('use_pos')) then raise exception 'غير مصرح'; end if;
  select * into s from social_follow_claims where id = p_id for update;
  if s.id is null then raise exception 'الطلب مش موجود'; end if;
  if s.status <> 'pending' then raise exception 'الطلب ده اتقرر قبل كده'; end if;
  if not p_ok then
    update social_follow_claims set status = 'rejected', decided_by = auth.uid(), decided_at = now() where id = p_id;
    return 0;
  end if;
  if exists (select 1 from social_follow_claims where customer_id = s.customer_id and status = 'approved') then
    raise exception 'العميل ده خد المكافأة قبل كده على منصة تانية'; end if;
  v_pts := coalesce((select nullif(value #>> '{}','')::numeric from app_settings where key = 'social_follow_points' and jsonb_typeof(value) = 'number'), 10)::int;
  update social_follow_claims set status = 'approved', decided_by = auth.uid(), decided_at = now() where id = p_id;
  if v_pts > 0 then perform add_points(s.customer_id, v_pts, 'social', null, 'مكافأة متابعة ' || s.platform); end if;
  return v_pts;
end $$;

grant execute on function public.my_social_claims(), public.claim_social_follow(text), public.admin_social_claims(), public.admin_decide_social(bigint, boolean) to authenticated;
