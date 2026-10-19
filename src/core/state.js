/* core/state.js — الحالة العامة، الأدوات، الصلاحيات */

const APP_MODE=window.SALON_MODE||"customer";

// جلسة منفصلة لكل تطبيق: الدخول في تطبيق العملاء أو الموظفين مايأثرش على الإدارة والعكس (العملاء بتفضل على المفتاح الافتراضي عشان جلساتهم الحالية)
const sb=supabase.createClient(SUPABASE_URL,SUPABASE_KEY,APP_MODE=="customer"?undefined:{auth:{storageKey:"salon-auth-"+APP_MODE}});

const $=i=>document.getElementById(i),esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));

const fm=n=>Math.round(n).toLocaleString("ar-EG")+" "+C.cfg.currency;

const toast=t=>{const e=document.createElement("div"),x=String(t||""),k=/✓|^تم|تمام|اتحفظ|اتسجل/.test(x)?" ok":/غلط|خطأ|مش |ممنوع|غير مصرح|تعذر|فشل|error|failed|invalid|violat|حد /i.test(x)?" err":"";e.className="toast"+k;e.textContent=x;document.body.appendChild(e);setTimeout(()=>e.remove(),2600)};



const RL={owner:"مالك",manager:"مدير",cashier:"كاشير",barber:"حلاق",assistant:"مساعد",customer:"عميل"};

const ST={upcoming:"قادم",checked_in:"وصل",in_service:"على الكرسي",done:"خلص",cancelled:"ملغي",no_show:"لم يحضر"};

let me=null,tab="";

const C={cfg:{salon_name:"صالون أبو يوسف",phone:"",address:"",currency:"ج.م",open_hour:10,close_hour:20,slot_minutes:60,days_ahead:5,weekly_off:5,cancel_before_hours:2,points_per_currency:10,max_discount_pct:20,booking_open:true,referral_enabled:true,birthday_enabled:true,birthday_points:50,referral_points:50,referral_min_total:0,referral_max_per_customer:0,urgent_enabled:true,urgent_multiplier:2,late_fine_enabled:true,late_fine_grace_min:15,late_fine_per_min:1}};

const PD={cashier:{use_attendance:1,use_pos:1,view_stock:1,view_invoices:1,manage_appts:1,view_customers:1,view_customer_phone:1,cash_ops:1},barber:{use_attendance:1,view_own_sales:1,view_own_commission:1,view_own_finance:1,view_own_reviews:1,view_own_schedule:1,view_own_target:1},assistant:{use_attendance:1,view_own_finance:1}};

const isAdm=p=>!!p&&(p.role=="owner"||p.role=="manager");

const can=(k,p=me)=>p.role=="owner"||(p.perms&&k in p.perms?!!p.perms[k]:(p.role=="manager"||!!(PD[p.role]||{})[k]));

async function loadCfg(){const{data}=await sb.from("app_settings").select("*");(data||[]).forEach(r=>C.cfg[r.key]=r.value);const sfx=APP_MODE=="staff"?" · الموظفين":APP_MODE=="admin"?" · الإدارة":"";document.title=C.cfg.salon_name+sfx;$("brand").innerHTML=ic("menu")+"<span>"+esc(C.cfg.salon_name)+sfx+"</span>"}

const staffTabs=p=>{const T=[],cn=k=>can(k,p);if(cn("use_pos"))T.push(["pos","الكاشير"]);if(cn("use_pos"))T.push(["cash","الخزنة"]);if(cn("manage_appts"))T.push(["appts","الحجوزات"]);if(cn("view_stock"))T.push(["stock","المخزون"]);if(cn("view_invoices"))T.push(["inv","الفواتير"]);if(cn("view_customers"))T.push(["cust","العملاء"]);if(cn("view_customers"))T.push(["rem","التذكير","cust"]);if(cn("view_reports"))T.push(["rep","التقارير"]);if(p.role=="barber"||p.role=="assistant"||cn("use_attendance"))T.push(["me","شاشتي"]);T.push(["ann","الإعلانات"]);if(p.role!="assistant"&&p.role!="customer")T.push(["lb","المتصدرين"]);if(isAdm(p)||(p.role=="barber"&&cn("view_own_target")))T.push(["tgt","التارجت"]);return T};

// المرتبات: المالك بس بيقراها (عمود salary مقفول عن الـ API لباقي المستخدمين)

const PCOLS="id,full_name,role,commission_pct,created_at,perms,code";

async function addSalary(rows){if(!isAdm(me)||!rows)return;try{const{data}=await sb.rpc("owner_salaries"),m=Object.fromEntries((data||[]).map(r=>[r.id,r.salary]));rows.forEach(p=>{if(p.id in m)p.salary=m[p.id]})}catch(e){}}
