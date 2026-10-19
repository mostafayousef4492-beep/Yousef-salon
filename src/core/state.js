/* core/state.js — الحالة العامة، الأدوات، الصلاحيات */

const APP_MODE=window.SALON_MODE||"customer";

const sb=supabase.createClient(SUPABASE_URL,SUPABASE_KEY);

const $=i=>document.getElementById(i),esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));

const fm=n=>Math.round(n).toLocaleString("ar-EG")+" "+C.cfg.currency;

const toast=t=>{const e=document.createElement("div"),x=String(t||""),k=/✓|^تم|تمام|اتحفظ|اتسجل/.test(x)?" ok":/غلط|خطأ|مش |ممنوع|غير مصرح|تعذر|فشل|error|failed|invalid|violat|حد /i.test(x)?" err":"";e.className="toast"+k;e.textContent=x;document.body.appendChild(e);setTimeout(()=>e.remove(),2600)};



const RL={owner:"مالك",manager:"مدير",cashier:"كاشير",barber:"حلاق",assistant:"مساعد",customer:"عميل"};

const ST={upcoming:"قادم",checked_in:"وصل",in_service:"على الكرسي",done:"خلص",cancelled:"ملغي",no_show:"لم يحضر"};

let me=null,tab="";

const C={cfg:{salon_name:"صالون أبو يوسف",phone:"",address:"",currency:"ج.م",open_hour:10,close_hour:20,slot_minutes:60,days_ahead:5,weekly_off:5,cancel_before_hours:2,points_per_currency:10,max_discount_pct:20,booking_open:true,referral_enabled:true,birthday_enabled:true,birthday_points:50,referral_points:50,referral_min_total:0,referral_max_per_customer:0,urgent_enabled:true,urgent_multiplier:2,late_fine_enabled:true,late_fine_grace_min:15,late_fine_per_min:1}};

const PD={cashier:{use_attendance:1,use_pos:1,view_stock:1,view_invoices:1,manage_appts:1,view_customers:1,view_customer_phone:1,cash_ops:1},barber:{use_attendance:1,view_own_sales:1,view_own_commission:1,view_own_finance:1,view_own_reviews:1,view_own_schedule:1,view_own_target:1},assistant:{use_attendance:1,view_own_finance:1}};

const isAdm=p=>!!p&&(p.role=="owner"||p.role=="manager");

const can=(k,p=me)=>p.role=="owner"||(p.perms&&k in p.perms?!!p.perms[k]:(k in CAT_DEF?CAT_DEF[k].includes({manager:"m",cashier:"c",barber:"b",assistant:"a"}[p.role]||"-"):(p.role=="manager"||!!(PD[p.role]||{})[k])));

async function loadCfg(){const{data}=await sb.from("app_settings").select("*");(data||[]).forEach(r=>C.cfg[r.key]=r.value);const sfx=APP_MODE=="staff"?" · الموظفين":APP_MODE=="admin"?" · الإدارة":"";document.title=C.cfg.salon_name+sfx;$("brand").innerHTML=ic("menu")+"<span>"+esc(C.cfg.salon_name)+sfx+"</span>"}

const staffTabs=p=>{const T=[],cn=k=>can(k,p);if(cn("use_pos"))T.push(["pos","الكاشير"]);if(cn("use_pos"))T.push(["cash","الخزنة"]);if(cn("manage_appts"))T.push(["appts","الحجوزات"]);if(cn("view_stock"))T.push(["stock","المخزون"]);if(cn("view_invoices"))T.push(["inv","الفواتير"]);if(cn("view_customers"))T.push(["cust","العملاء"]);if(cn("view_customers"))T.push(["rem","التذكير","cust"]);if(cn("view_reports"))T.push(["rep","التقارير"]);if(p.role=="barber"||p.role=="assistant"||cn("use_attendance"))T.push(["me","شاشتي"]);T.push(["ann","الإعلانات"]);if(p.role!="assistant"&&p.role!="customer")T.push(["lb","المتصدرين"]);if(isAdm(p)||(p.role=="barber"&&cn("view_own_target")))T.push(["tgt","التارجت"]);return T};

// المرتبات: المالك بس بيقراها (عمود salary مقفول عن الـ API لباقي المستخدمين)

const PCOLS="id,full_name,role,commission_pct,created_at,perms,code";

async function addSalary(rows){if(!isAdm(me)||!rows)return;try{const{data}=await sb.rpc("owner_salaries"),m=Object.fromEntries((data||[]).map(r=>[r.id,r.salary]));rows.forEach(p=>{if(p.id in m)p.salary=m[p.id]})}catch(e){}}

/* core/perms.js — كتالوج صلاحيات الإجراءات والأسطر
   الفكرة: كل زرار/كارت/قسم ليه مفتاح. المالك دايمًا بيشوف كل حاجة. باقي الموظفين: القيمة المحفوظة على الموظف (profiles.perms)،
   ولو مفيش فالافتراضي من العمود الرابع هنا (m=مدير c=كاشير b=حلاق a=مساعد؛ لو m مش موجودة يبقى للمالك بس افتراضيًا).
   الإخفاء من الشاشة بس: السيرفر له قواعده الخاصة، فالصلاحية بتقفل حاجة، لكنها مش بتفتح حاجة السيرفر مانعها. */
const CAT=[
// الرئيسية والبحث
["الرئيسية والبحث","h_revenue","كارت إيراد اليوم وعدد الفواتير","mc"],
["الرئيسية والبحث","h_expenses","كروت المصروفات وصافي اليوم","m"],
["الرئيسية والبحث","cash_inout","أزرار إيداع وسحب في الرئيسية","m"],
["الرئيسية والبحث","search_money","نتايج البحث المالية (مصروفات، سحب موظفين، درج، رواتب، موردين)","m"],
["الرئيسية والبحث","urgent_decide","الموافقة على الدخول المستعجل أو رفضه","m"],
["الرئيسية والبحث","transfer_decide","الموافقة على طلبات نقل الحجز","mc"],
// الدور والحجوزات
["الدور والحجوزات","q_call","استدعاء العميل","mcb"],
["الدور والحجوزات","q_arrive","تأكيد وصول العميل","mcb"],
["الدور والحجوزات","q_start","بدء الخدمة","mcb"],
["الدور والحجوزات","q_finish","إنهاء الخدمة","mcb"],
["الدور والحجوزات","q_skip","تخطّي عميل وإرجاعه","mcb"],
["الدور والحجوزات","appt_admin_book","حجز إداري وWalk-in","mc"],
["الدور والحجوزات","appt_urgent","تحويل تذكرة لمستعجل","m"],
["الدور والحجوزات","appt_move","نقل حجز لحلاق تاني","mc"],
["الدور والحجوزات","appt_cancel","إلغاء حجز","mc"],
["الدور والحجوزات","appt_close_stale","قفل الخدمات العالقة من أيام فاتت","mc"],
// الكاشير
["الكاشير","pos_discount","إدخال خصم يدوي","mc"],
["الكاشير","pos_paid","كتابة المدفوع الفعلي لو دفع أكتر","mc"],
["الكاشير","pos_bundle","تطبيق أو إلغاء باقة","mc"],
["الكاشير","pos_cancel","إلغاء الفاتورة المفتوحة وتفضية الكرسي","mc"],
// الفواتير
["الفواتير","inv_attach","ربط عميل بفاتورة قديمة","m"],
["الفواتير","inv_paid","تعديل المدفوع الفعلي بعد الفاتورة",""],
["الفواتير","edit_dates","تعديل تاريخ فاتورة أو مصروف أو حركة موظف",""],
["الفواتير","backfill_sales","تسجيل مبيعات يوم فات",""],
["الفواتير","inv_commission","أسطر عمولة المساعد والكاشير في تفاصيل الفاتورة","m"],
// الخزنة والمصروفات
["الخزنة والمصروفات","cash_summary","المتوقع في الدرج وتفصيل الدفع الإلكتروني","m"],
["الخزنة والمصروفات","cash_kpi","كروت الأرقام فوق شاشة الخزنة","m"],
["الخزنة والمصروفات","cash_close","قفل اليوم وعدّ الدرج","mc"],
["الخزنة والمصروفات","cash_moves","سحب وإضافة للدرج","m"],
["الخزنة والمصروفات","exp_add","تسجيل مصروف","m"],
// التقارير
["التقارير","rep_sum","تقرير: الملخص","m"],
["التقارير","rep_daily","تقرير: يوم بيوم","m"],
["التقارير","rep_sales","تقرير: المبيعات","m"],
["التقارير","rep_staff","تقرير: الموظفين","m"],
["التقارير","rep_cust","تقرير: العملاء","m"],
["التقارير","rep_queue","تقرير: الدور والتقييم","m"],
["التقارير","rep_stock","تقرير: المخزون","m"],
["التقارير","rep_exp","تقرير: المصروفات","m"],
["التقارير","rep_export","التصدير والطباعة (Excel / CSV / PDF)","m"],
// العملاء
["العملاء","cust_add","إضافة عميل جديد","mc"],
["العملاء","cust_points","تعديل نقاط العميل","m"],
["العملاء","cust_birthday","تعديل تاريخ ميلاد العميل","m"],
["العملاء","cust_attach","ربط عميل برقم موبايل","mc"],
["العملاء","cust_code","إصدار كود دخول للعميل","mc"],
// الموظفين والحضور
["الموظفين والحضور","team_add","إضافة موظف جديد","m"],
["الموظفين والحضور","team_tx","تسجيل سحب أو خصم أو مكافأة لموظف","m"],
["الموظفين والحضور","team_salary","شوف مرتبات الموظفين","m"],
["الموظفين والحضور","att_edit","تعديل الحضور والانصراف يدويًا","m"],
["الموظفين والحضور","att_codes","أكواد تسجيل الحضور","m"],
["الموظفين والحضور","shift_edit","تعديل مواعيد الشيفتات","m"],
["الموظفين والحضور","leave_add","تسجيل إجازات","m"],
["الموظفين والحضور","late_rules","قواعد خصم التأخير",""]
];
const CAT_DEF=Object.fromEntries(CAT.map(x=>[x[1],x[3]]));
const PRM=["manager","cashier","barber","assistant"];

// الزراير: الدالة (+ قيمة أول/تاني باراميتر لو لازم) ← المفتاح
const PH=[
{f:"cfOpen",k:"cash_inout"},{f:"urgDecide",k:"urgent_decide"},{f:"trDecide",k:"transfer_decide"},
{f:"tk",a:"call_ticket",k:"q_call"},{f:"homeCall",k:"q_call"},{f:"tk",a:"confirm_arrival",k:"q_arrive"},
{f:"setS",b:"in_service",k:"q_start"},{f:"tk",a:"finish_ticket",k:"q_finish"},{f:"tk",a:"return_ticket",k:"q_skip"},{f:"skipT",k:"q_skip"},
{f:"admForm",k:"appt_admin_book"},{f:"tk",a:"make_urgent",k:"appt_urgent"},{f:"moveT",k:"appt_move"},{f:"setS",b:"cancelled",k:"appt_cancel"},{f:"closeStale",k:"appt_close_stale"},
{f:"pickDisc",k:"pos_discount"},{f:"pickFix",k:"pos_discount"},{f:"posBnSet",k:"pos_bundle"},{f:"chCancel",k:"pos_cancel"},
{f:"invAttach",k:"inv_attach"},{f:"invNew",k:"inv_attach"},{f:"invPaid",k:"inv_paid"},{f:"editDate",k:"edit_dates"},{f:"bfOpen",k:"backfill_sales"},
{f:"doClose",k:"cash_close"},{f:"addMove",k:"cash_moves"},{f:"addExp",k:"exp_add"},
{f:"exportXlsx",k:"rep_export"},{f:"exportCsv",k:"rep_export"},{f:"exportMonthly",k:"rep_export"},
{f:"addCustForm",k:"cust_add"},{f:"saveCust",k:"cust_add"},{f:"adjP",k:"cust_points"},{f:"cuBday",k:"cust_birthday"},{f:"cuBdaySave",k:"cust_birthday"},{f:"attachPh",k:"cust_attach"},{f:"custCode",k:"cust_code"},
{f:"addStaff",k:"team_add"},{f:"addTx",k:"team_tx"},{f:"attSave",k:"att_edit"},{f:"attEdit",k:"att_edit"},{f:"attCode",k:"att_codes"},{f:"saveShift",k:"shift_edit"},{f:"addLeave",k:"leave_add"},{f:"lateRules",k:"late_rules"},{f:"lateGlobal",k:"late_rules"}
];
const PHM={};PH.forEach(h=>(PHM[h.f]=PHM[h.f]||[]).push(h));

const permHit=(f,a)=>(PHM[f]||[]).find(x=>(x.a===undefined||a[0]==x.a)&&(x.b===undefined||a[1]==x.b));
const permOn=()=>!!me&&PRM.includes(me.role);

// إخفاء الأزرار (حسب الدالة اللي بتنادي عليها) والعناصر المعلّمة data-perm اللي مش مسموحة للمستخدم
function permApply(root){if(!permOn()||!root)return;
  root.querySelectorAll("[data-perm]").forEach(e=>{if(!can(e.dataset.perm))e.remove()});
  root.querySelectorAll("[onclick]").forEach(e=>{const s=e.getAttribute("onclick")||"";let m,re=/\b(\w+)\(([^()]*)\)/g;
    while((m=re.exec(s))){if(!PHM[m[1]])continue;const a=m[2].split(",").map(x=>x.trim().replace(/^['"]|['"]$/g,"")),h=permHit(m[1],a);if(h&&!can(h.k)){e.remove();break}}})}

// حماية إضافية: لو الدالة اتنفّذت بأي طريقة تانية غير الزرار، نرفضها لو الصلاحية مقفولة
let PWR=0;
function permWrap(){if(PWR)return;PWR=1;Object.keys(PHM).forEach(f=>{const o=window[f];if(typeof o!="function"||o.__pw)return;
  const w=function(...a){const h=permHit(f,a);if(h&&permOn()&&!can(h.k)){toast("الإجراء ده مش متاح لحسابك");return}return o.apply(this,a)};w.__pw=1;window[f]=w})}
