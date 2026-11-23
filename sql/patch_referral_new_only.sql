-- patch_referral_new_only.sql — نقاط الدعوة للعميل الجديد بس
-- القاعدة: لو العميل اللي اتدعى سبق وحلق/دفع عندنا قبل كده، مفيش نقاط لا ليه ولا للي دعاه.
-- (تسجيل الدعوة من العميل نفسه كان بيرفض العميل القديم أصلًا. الثغرة كانت في ربط الدعوة من الموظف وفي صرف المكافأة نفسها.)
-- آمن للتشغيل أكتر من مرة. مفيش تغيير في بيانات موجودة.

-- 1) ربط الداعي من الموظف: للعملاء الجداد بس
create or replace function public.staff_set_referrer(p_customer bigint, p_key text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare c customers; v_r bigint; v_n text;
begin
  if not (is_mgr() or has_perm('use_pos')) then raise exception 'غير مصرح'; end if;
  if not p_ref_on() then raise exception 'برنامج الدعوات متوقف دلوقتي'; end if;
  select * into c from customers where id = p_customer for update;
  if c.id is null then raise exception 'العميل مش موجود'; end if;
  if c.referral_rewarded_at is not null then raise exception 'مكافأة الدعوة اتصرفت قبل كده'; end if;
  if c.visits > 0 or exists (select 1 from invoices i where i.customer_id = c.id) then raise exception 'الدعوة للعملاء الجداد بس: العميل ده زارنا قبل كده'; end if;
  v_r := p_ref_find(p_key, c.id);
  if v_r is null then raise exception 'الكود أو الرقم ده مش صحيح'; end if;
  if exists (select 1 from customers r where r.id = v_r and r.referred_by = c.id) then raise exception 'مينفعش'; end if;
  update customers set referred_by = v_r where id = c.id;
  select name into v_n from customers where id = v_r;
  return v_n;
end $function$;

-- 2) صرف المكافأة: لو للعميل فاتورة سابقة (غير الفاتورة دي) مفيش نقاط
create or replace function public.trg_referral_award()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare c customers; v_pts int := p_ref_cfg('referral_points',50)::int; v_rp int := p_ref_cfg('referral_referrer_points', p_ref_cfg('referral_points',50))::int;
        v_min numeric := p_ref_cfg('referral_min_total',0); v_max int := p_ref_cfg('referral_max_per_customer',0)::int;
begin
  begin
    if new.customer_id is null or coalesce(new.total,0) <= 0 or coalesce(old.total,0) > 0 then return new; end if;
    if not p_ref_on() or not p11_cfg_bool('ff_loyalty', true) then return new; end if;
    if new.total < v_min then return new; end if;
    select * into c from customers where id = new.customer_id for update;
    if c.referred_by is null or c.referral_rewarded_at is not null then return new; end if;
    -- عميل قديم (له فاتورة سابقة): مفيش نقاط
    if exists (select 1 from invoices i where i.customer_id = c.id and i.id <> new.id and i.settles_invoice is null and (i.total > 0 or i.unpaid > 0) and i.created_at <= new.created_at) then return new; end if;
    if not exists (select 1 from customers where id = c.referred_by) then return new; end if;
    if v_max > 0 and (select count(*) from customers x where x.referred_by = c.referred_by and x.referral_rewarded_at is not null) >= v_max then return new; end if;
    update customers set referral_rewarded_at = now() where id = c.id;
    if v_pts > 0 then perform add_points(c.id, v_pts, 'referral', new.id, 'هدية دعوة'); end if;
    if v_rp > 0 then perform add_points(c.referred_by, v_rp, 'referral', new.id, 'مكافأة دعوة ' || c.name); end if;
  exception when others then
    raise warning 'referral award: %', sqlerrm;
  end;
  return new;
end $function$;
-- تراجع: أعد تشغيل النسخة القديمة من patch_referrals.sql
