-- شاشة الموظفين (التابلت): المدير/الكاشير يدخل بكوده وPIN بتاعه فيشوف كل الموظفين وكام زبون مع كل واحد،
-- ويدخل على أي موظف من غير PIN بتاعه. اللي بيتنفّذ بيتسجّل باسم المدير/الكاشير نفسه (مش باسم الموظف).
-- بيعتمد على kiosk_who / kiosk_q الموجودين أصلاً. آمن للتشغيل أكتر من مرة.
create or replace function public.kiosk_team(p_token text, p_code text, p_pin text) returns jsonb
language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare w jsonb; v_staff jsonb;
begin
  w := kiosk_who(p_token, p_code, p_pin);
  if not (w->>'ok')::boolean then return w; end if;
  perform set_config('request.jwt.claim.sub', w->>'id', true);
  if not (is_mgr() or can_use_pos()) then return jsonb_build_object('ok', false, 'msg', 'مش مصرّح'); end if;
  select coalesce(jsonb_agg(to_jsonb(s) order by s.ord, s.name), '[]'::jsonb) into v_staff from (
    select p.id, p.full_name as name, p.role::text as role,
           case p.role::text when 'barber' then 0 when 'assistant' then 1 when 'cashier' then 2 else 3 end as ord,
           exists (select 1 from attendance at where at.staff_id = p.id and at.check_out is null) as present,
           coalesce((select jsonb_agg(t order by t.ord) from (
             select a.id, a.ticket_code as code, c.name as cname, c.phone as cphone, b.full_name as barber,
                    a.status::text as status, (a.called_at is not null) as called, a.call_count as calls,
                    coalesce(a.sort_at, a.created_at) as ord,
                    (select string_agg(s2.name, ' + ') from appointment_services x join services s2 on s2.id = x.service_id where x.appointment_id = a.id) as services
               from appointments a left join customers c on c.id = a.customer_id left join profiles b on b.id = a.barber_id
              where a.barber_id = p.id and a.day between biz_today() - 1 and biz_today()
                and a.status::text in ('upcoming', 'checked_in', 'in_service')) t), '[]'::jsonb) as tickets
      from profiles p where p.role::text not in ('owner', 'customer')) s;
  return jsonb_build_object('ok', true, 'name', w->>'name', 'role', w->>'role', 'staff', v_staff);
end $$;
revoke all on function public.kiosk_team(text, text, text) from public;
grant execute on function public.kiosk_team(text, text, text) to anon, authenticated;
