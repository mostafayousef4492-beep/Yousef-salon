-- قايمة دعواتي: الاسم الأول + الحالة (سجّل / زار / اتكافأوا). مفيش أرقام ولا بيانات شخصية. آمن للتكرار.
create or replace function public.my_referral_list()
returns table(first_name text, status text, created_at timestamptz)
language sql stable security definer set search_path to 'public' as $$
  select split_part(btrim(x.name), ' ', 1),
         case when x.referral_rewarded_at is not null then 'rewarded'
              when x.visits > 0 or exists (select 1 from invoices i where i.customer_id = x.id) then 'visited'
              else 'registered' end,
         x.created_at
    from customers x join customers me on me.id = x.referred_by
   where me.user_id = auth.uid()
   order by x.created_at desc limit 50 $$;
grant execute on function public.my_referral_list() to authenticated;
