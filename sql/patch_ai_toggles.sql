-- مفاتيح تفعيل/إلغاء المساعدات من الإعدادات (قسم «المساعد الذكي»):
--   assistant_enabled            — يقفل المساعد للكل (موجود من patch_assistant.sql)
--   assistant_analytics_enabled  — مساعد التحليل للمالك (افتراضي true). false = المالك يشتغل بمساعد التشغيل بس
--   assistant_manager_enabled    — مساعد المدير (من patch_manager_assistant.sql)
-- ai_admin_ok() = مالك + مفتاح التحليل شغّال. وai_mode() (من patch_manager_assistant.sql) بترجّع 'manager' للمالك لو التحليل مقفول.
-- شغّله بعد patch_manager_assistant.sql. آمن للتكرار. مفيش بيانات بتتغير.
create or replace function public.ai_admin_ok() returns boolean
language plpgsql stable security definer set search_path to 'public' as $$
declare v_set text;
begin
  if not coalesce((select p.role::text = 'owner' from profiles p where p.id = auth.uid()), false) then return false; end if;
  select trim(both '"' from value::text) into v_set from app_settings where key = 'assistant_analytics_enabled';
  return coalesce(v_set, 'true') not in ('false', '0', 'off');
end $$;
revoke all on function public.ai_admin_ok() from public, anon;
grant execute on function public.ai_admin_ok() to authenticated;
