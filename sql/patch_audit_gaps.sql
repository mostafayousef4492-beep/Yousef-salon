-- سدّ ثغرات الأرشيف (التدقيق):
-- 1) أرشيف المحذوفات (deletion_log) وسجل التدقيق (audit_log) يتقفلوا ضد التعديل والمسح والتفريغ.
-- 2) إضافة التدقيق على الجداول الجديدة (الشركات، المواعيد الثابتة، الخامات).
-- آمن لو اتشغّل أكتر من مرة، ومبيغيّر أي بيانات قديمة. التدقيق بيتسجّل بنفس آلية p20_audit الموجودة.
-- لو احتجت تتراجع: drop trigger deletion_log_lock on deletion_log; drop trigger audit_log_no_truncate on audit_log;

create or replace function public.p20_stmt_lock() returns trigger language plpgsql as $$
begin raise exception 'الأرشيف للقراءة فقط'; end $$;

do $$
begin
  if to_regclass('public.deletion_log') is not null then
    drop trigger if exists deletion_log_lock on public.deletion_log;
    create trigger deletion_log_lock before update or delete on public.deletion_log for each row execute function public.p20_audit_lock();
    drop trigger if exists deletion_log_no_truncate on public.deletion_log;
    create trigger deletion_log_no_truncate before truncate on public.deletion_log for each statement execute function public.p20_stmt_lock();
  end if;
  drop trigger if exists audit_log_no_truncate on public.audit_log;
  create trigger audit_log_no_truncate before truncate on public.audit_log for each statement execute function public.p20_stmt_lock();
end $$;

-- تدقيق الجداول الجديدة (لو موجودة ومفيهاش تدقيق)
do $$
declare t text;
begin
  foreach t in array array['companies', 'company_excluded_services', 'fixed_reminders', 'materials', 'service_materials', 'approval_requests']
  loop
    if to_regclass('public.' || t) is not null then
      if not exists (select 1 from pg_trigger where tgname = 'zz_audit' and tgrelid = to_regclass('public.' || t)) then
        execute format('create trigger zz_audit after insert or update or delete on public.%I for each row execute function public.p20_audit()', t);
      end if;
    end if;
  end loop;
end $$;
