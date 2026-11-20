-- ترشيح الحلاق للعميل: حلاقه المعتاد (من زياراته الفعلية) + الأعلى تقييمًا (من تقييمات حقيقية، 3 تقييمات على الأقل).
-- قراءة فقط، ومفيهوش بيانات تخص عميل تاني. آمن لو اتشغّل أكتر من مرة.
create or replace function public.barber_hints()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare c customers; v_usual jsonb; v_top jsonb;
begin
  select * into c from customers where user_id = auth.uid() limit 1;
  if not found then raise exception 'غير مصرح'; end if;
  select jsonb_build_object('id', p.id, 'name', p.full_name, 'visits', x.n) into v_usual
    from (select barber_id, count(*) n from appointments where customer_id = c.id and status::text = 'done' and barber_id is not null group by 1 having count(*) >= 2 order by 2 desc limit 1) x
    join profiles p on p.id = x.barber_id where p.role::text = 'barber';
  select jsonb_build_object('id', p.id, 'name', p.full_name, 'rating', x.r, 'n', x.n) into v_top
    from (select barber_id, round(avg(rating), 2) r, count(*) n from reviews where barber_id is not null group by 1 having count(*) >= 3 order by 2 desc, 3 desc limit 1) x
    join profiles p on p.id = x.barber_id where p.role::text = 'barber';
  return jsonb_build_object('usual', v_usual, 'top', v_top);
end $$;
revoke all on function public.barber_hints() from public, anon;
grant execute on function public.barber_hints() to authenticated, service_role;
notify pgrst, 'reload schema';
