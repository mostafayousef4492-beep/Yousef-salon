-- patch_member_notice.sql — إشعار للعميل قبل الخصم الأسبوعي من هدية الاشتراك
-- لازم patch_membership.sql متشغّل. بيستخدم نظام الإشعارات الموجود (push_send) من غير أي edge function جديدة.
-- member_notice_run(): لعميل عنده اشتراك شغّال + رصيد هدية + ناقصه زيارات + باقي له يوم أو أقل على نهاية أسبوعه (لحد 3 الفجر من اليوم الأخير)،
-- بيبعتله إشعار مرة واحدة فقط في الأسبوع (جدول member_notices بيمنع التكرار). مبيبعتش لعميل مالوش حساب أو مفعّلش الإشعارات (بيشوف التنبيه جوه التطبيق).
-- الإشعار معلومة بس، مفيش أي حركة فلوس. آمن للتشغيل أكتر من مرة.
create table if not exists public.member_notices(
  account_id bigint not null references public.member_accounts(id),
  cycle int not null,
  week_no int not null,
  sent_at timestamptz not null default now(),
  primary key (account_id, cycle, week_no)
);
alter table public.member_notices enable row level security;
drop policy if exists "member notices mgr read" on public.member_notices;
create policy "member notices mgr read" on public.member_notices for select using (coalesce(is_mgr(),false));

create or replace function public.member_notice_run() returns int
language plpgsql security definer set search_path to 'public' as $$
declare r record; v_today date := p_mb_today(); v_cur int; v_s date; v_e date; v_vis int; v_pen numeric; v_n int := 0; v_uid uuid; v_ins int;
begin
  for r in select a.* from member_accounts a where a.status = 'active' and a.bonus_bal > 0 and v_today <= a.expires_on loop
    begin
      perform p_mb_settle(r.id);
      select * into r from member_accounts where id = r.id;
      continue when r.status <> 'active' or r.bonus_bal <= 0;
      v_cur := ((v_today - r.started_on) / 7) + 1; v_s := r.started_on + 7 * (v_cur - 1); v_e := v_s + 7;   -- آخر يوم في الأسبوع = v_e - 1
      continue when (v_e - 1) - v_today > 1;
      v_vis := p_mb_visits(r.customer_id, v_s, v_e);
      continue when v_vis >= r.weekly_visits;
      select user_id into v_uid from customers where id = r.customer_id;
      continue when v_uid is null;
      insert into member_notices(account_id, cycle, week_no) values (r.id, r.cycle, v_cur) on conflict do nothing;
      get diagnostics v_ins = row_count;
      continue when v_ins = 0;
      v_pen := round(r.bonus_bal * r.penalty_pct / 100, 2);
      perform push_send(array[v_uid], 'ناقصك ' || (r.weekly_visits - v_vis) || ' زيارة 💈',
        'لو ماكمّلتش زياراتك قبل نهاية ' || case when v_e - 1 = v_today then 'النهارده' else 'بكرة' end || '، هيتخصم ' || trim(to_char(v_pen, 'FM999999990.##')) || ' جنيه من رصيد الهدية بس. رصيدك الأساسي في أمان.',
        'home', 'mnotice-' || r.id || '-' || r.cycle || '-' || v_cur, false);
      v_n := v_n + 1;
    exception when others then null;
    end;
  end loop;
  return v_n;
end $$;
revoke all on function public.member_notice_run() from public, anon, authenticated;
grant execute on function public.member_notice_run() to service_role;

-- الجدولة: كل ساعة (بتتخطّى بسرعة لو مفيش اشتراكات). شغّله مرة واحدة:
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'member-notice') then perform cron.unschedule('member-notice'); end if;
    perform cron.schedule('member-notice', '20 * * * *', 'select public.member_notice_run()');
  end if;
end $$;
-- أمان الإعادة: مفيش حاجة تتكرر لو الدالة اتنادت أكتر من مرة في نفس الأسبوع.
-- تراجع: select cron.unschedule('member-notice'); drop function member_notice_run(); drop table member_notices;
