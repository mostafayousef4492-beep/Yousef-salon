/* features/control/settings.js — الإعدادات والنسخ الاحتياطي */

// ================= الإعدادات: تاب لكل قسم + تصفير =================

const SEC=[["general","عام"],["book","الحجوزات"],["staff","الموظفين"],["pos","الكاشير"],["stock","المخزون"],["loy","العملاء والولاء"],["danger","تصفير"]];

const DAYS7=["الأحد","الاثنين","الثلاثاء","الأربعاء","الخميس","الجمعة","السبت"];

const FLD={general:[["salon_name","اسم الصالون"],["phone","التليفون"],["address","العنوان"],["currency","العملة"],["timezone","المنطقة الزمنية (مثال: Africa/Cairo)"]],
book:[["urgent_enabled","السماح بالدخول المستعجل (الزبون يطلب من تطبيقه والإدارة توافق)","bool"],["urgent_multiplier","معامل حساب الخدمات في المستعجل (2 = الخدمة ×2)","number"],["booking_open","الحجز أونلاين شغّال","bool"],["days_ahead","الحجز قبلها بكام يوم","number"],["weekly_off","يوم الإجازة الأسبوعي","day"],["max_queue_per_period","أقصى زباين في الفترة لكل حلاق","number"],["max_daily_bookings","أقصى حجوزات في اليوم (0 = بلا حد)","number"],["max_active_per_customer","أقصى حجوزات نشطة للعميل (0 = بلا حد)","number"],["no_show_after_minutes","مهلة عدم الحضور بعد النداء بالدقايق (0 = مقفول)","number"],["near_turn_threshold","نبّه العميل لما يبقى قدامه كام واحد","number"],["smart_assignment_enabled","توزيع تلقائي على أقل حلاق زحمة (لو العميل ما اختارش حلاق)","bool"],["show_queue_number","إظهار رقم الدور للعميل","bool"],["show_people_ahead","إظهار عدد اللي قدامه","bool"],["show_estimated_wait","إظهار وقت الانتظار المتوقع","bool"],["near_turn_notifications","إشعار \"اقترب دورك\" للعميل","bool"],["smart_assignment_require_checkin","التوزيع التلقائي يختار الحلاقين اللي سجّلوا حضور بس","bool"],["duration_learning_enabled","تقدير مدة الخدمة من الشغل الفعلي","bool"]],
staff:[["default_commission","عمولة الحلاق الجديد (افتراضي) %","number"],["attendance_radius_m","نطاق تسجيل الحضور بالمتر","number"],["salon_lat","خط عرض الصالون","number"],["salon_lng","خط طول الصالون","number"],["leaderboard_show_sales","إظهار مبالغ المبيعات في المتصدرين (للإدارة بس، الافتراضي مقفول)","bool"],["daily_salary_adjustment_enabled","تفعيل تعديل الراتب اليومي بالساعات","bool"],["week_start_dow","بداية الأسبوع في التارجت","day"],["late_fine_enabled","غرامة التأخير التلقائية (تتخصم من حساب الموظف)","bool"],["late_fine_grace_min","فترة السماح قبل الغرامة (دقيقة)","number"],["late_fine_per_min","الغرامة لكل دقيقة تأخير (جنيه) — بتتحسب من أول الميعاد","number"]],
pos:[["max_discount_pct","أقصى خصم للكاشير %","number"],["vodafone_cash_number","رقم فودافون كاش بتاع المحل"],["instapay_address","عنوان إنستا باي بتاع المحل (مثال: name@instapay)"]],
stock:[["low_stock_default","الحد الأدنى الافتراضي للمنتج الجديد","number"]],
loy:[["points_per_currency","كل كام جنيه = نقطة ولاء","number"],["welcome_bonus","هدية التسجيل (نقاط)","number"],["review_bonus","نقاط التقييم","number"],["referral_enabled","برنامج دعوة الأصدقاء شغّال","bool"],["referral_points","نقاط الصاحب الجديد (بعد أول فاتورة)","number"],["referral_referrer_points","نقاط اللي رشّحه (فاضي = نفس نقاط الصاحب)","number"],["referral_min_total","أقل إجمالي لأول فاتورة عشان النقاط تتصرف (0 = أي فاتورة)","number"],["referral_max_per_customer","أقصى عدد دعوات بتتكافأ للعميل الواحد (0 = بلا حد)","number"],["birthday_enabled","هدية عيد الميلاد شغّالة","bool"],["birthday_points","نقاط هدية عيد الميلاد","number"],["visit_bonus_every","مكافأة كل كام زيارة","number"],["visit_bonus_points","نقاط مكافأة الزيارات","number"],["tier_silver","نقاط المستوى الفضي (إجمالي)","number"],["tier_gold","نقاط المستوى الذهبي","number"],["tier_vip","نقاط مستوى VIP","number"]]};

const RST={book:[["queue","تصفير الدور الحالي (مسح كل الحجوزات غير المنتهية)"],["appointments","مسح كل الحجوزات وتقييماتها"]],staff:[["attendance","تصفير سجل الحضور"],["staff_tx","تصفير السحب والخصومات والمكافآت"]],pos:[["invoices","مسح كل الفواتير"]],stock:[["stock","تصفير كميات المخزون وحركاته"]],loy:[["loyalty","تصفير نقاط وكوبونات كل العملاء"]],danger:[["reviews","مسح كل التقييمات"],["expenses","مسح كل المصروفات"],["finance","مسح كل بيانات المالية (قفل الخزنة، الموردين، المشتريات، صرف الرواتب)"],["customers","مسح كل العملاء وبياناتهم"],["all","تصفير كل البيانات (فواتير، حجوزات، عملاء، حضور، مخزون، نقاط، مصروفات)"]]};

const BK_TABLES=["profiles","app_settings","services","products","stock_movements","customers","appointments","appointment_services","invoices","invoice_items","reviews","expenses","staff_transactions","staff_shifts","staff_leaves","attendance","loyalty_ledger","loyalty_rewards","loyalty_redemptions","expense_categories","suppliers","purchases","purchase_items","supplier_payments","salary_payments","cash_moves","cash_closings"];

const BK_ORDER={app_settings:["key"],appointment_services:["appointment_id","service_id"]};

async function bkTable(t){const ord=BK_ORDER[t]||["id"];
  for(const useOrd of [true,false]){let all=[],from=0,err=null;
    for(;;){let q=sb.from(t).select(t=="profiles"?PCOLS:"*");if(useOrd)ord.forEach(c=>q=q.order(c));const{data,error}=await q.range(from,from+999);
      if(error){err=error;break}all.push(...data);if(data.length<1000)break;from+=1000}
    if(!err){if(t=="profiles")await addSalary(all);return{rows:all}}if(!useOrd)return{error:err.message}}}

async function backupAll(){const btn=$("bkb"),msg=$("bkm");btn.disabled=true;
  const out={app:"salon-backup",version:1,created_at:new Date().toISOString(),tables:{},errors:{}};let rows=0;
  for(const t of BK_TABLES){btn.textContent="بنسحب: "+t+"…";const r=await bkTable(t);if(r.error)out.errors[t]=r.error;else{out.tables[t]=r.rows;rows+=r.rows.length}}
  const n=Object.keys(out.tables).length,bad=Object.keys(out.errors);
  if(!n){btn.disabled=false;btn.textContent="⬇️ تنزيل نسخة احتياطية الآن";return msg.textContent="فشل السحب: "+(bad.map(k=>k+" ("+out.errors[k]+")").join("، "))}
  const day=new Date().toLocaleDateString("en-CA"),blob=new Blob([JSON.stringify(out)],{type:"application/json"}),a=document.createElement("a");
  a.href=URL.createObjectURL(blob);a.download="salon-backup-"+day+".json";document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(a.href),4000);
  try{localStorage.setItem("salon_last_backup",new Date().toISOString())}catch(e){}
  btn.disabled=false;btn.textContent="⬇️ تنزيل نسخة احتياطية الآن";
  msg.textContent=`تم ✓ ${n} جدول · ${rows} سجل`+(bad.length?` — مقدرناش نسحب: ${bad.join("، ")}`:"");toast(bad.length?"النسخة نزلت بس فيها جداول ناقصة":"تم تنزيل النسخة الاحتياطية ✓")}

const lastBk=()=>{let d=null;try{d=localStorage.getItem("salon_last_backup")}catch(e){}return d?"آخر نسخة من الجهاز ده: "+new Date(d).toLocaleString("ar-EG"):"لسه معملتش نسخة من الجهاز ده."};

V.set=async()=>{await loadCfg();
const[{data:sv},{data:pr},{data:rw}]=await Promise.all([sb.from("services").select("*").order("id"),sb.from("products").select("*").order("id"),sb.from("loyalty_rewards").select("*").order("cost")]);C.cat={services:sv,products:pr};
const sec=C.sec||"general",c=C.cfg;const{data:stf}=sec=="staff"?await sb.from("profiles").select("id,full_name,role").in("role",["cashier","barber","assistant"]).order("full_name"):{data:[]};
const fld=([k,l,t])=>t=="bool"?`<label class="row" style="cursor:pointer"><span>${l}</span><input type="checkbox" id="s_${k}" ${c[k]?"checked":""} style="width:22px;height:22px;margin:0"></label>`:t=="day"?`<label class="m">${l}</label><select id="s_${k}">${DAYS7.map((d,i)=>`<option value="${i}" ${c[k]==i?"selected":""}>${d}</option>`).join("")}<option value="-1" ${c[k]==-1?"selected":""}>مفيش إجازة</option></select>`:`<label class="m">${l}</label><input id="s_${k}" type="${t||"text"}" step="any" value="${esc(c[k])}">`;
let h=`<h1>الإعدادات</h1><div class="chips">${SEC.map(x=>`<button class="chip ${sec==x[0]?"sel":""}" onclick="C.sec='${x[0]}';V.set()">${x[1]}</button>`).join("")}</div>`;
if(FLD[sec])h+=`<div class="box">${FLD[sec].map(fld).join("")}${sec=="staff"?`<button class="btn g s" style="margin-bottom:8px" onclick="setHere()">📍 استخدم موقعي الحالي (وانت في الصالون)</button>`:""}<button class="btn" style="width:100%" onclick="saveSec()">حفظ</button></div>`;
if(sec=="staff")h+=`<h2>شاشة وصلاحيات كل موظف</h2>`+((stf||[]).length?stf.map(p=>`<button class="row" style="cursor:pointer" onclick="C.pb='set';openPerms('${p.id}')"><div><b>${esc(p.full_name)}</b><div class="m">${RL[p.role]||""}</div></div><span class="tag">افتح شاشته ‹</span></button>`).join(""):`<p class="m">مفيش موظفين لسه.</p>`);
const row=(t,x,d)=>`<div class="row"><div><b>${esc(x.name)}</b><div class="m">${d}${x.active?"":" · موقوف"}</div></div><div><button class="btn s g" onclick="editItem('${t}',${x.id})">تعديل</button> <button class="btn s g" onclick="toggleItem('${t}',${x.id},${!x.active})">${x.active?"إيقاف":"تفعيل"}</button></div></div>`;
if(sec=="general")h+=`<h2>روابط التطبيقات</h2>`+[["تطبيق العملاء","/"],["تطبيق الموظفين","/staff"],["تطبيق الإدارة (ده)","/admin"]].map(x=>`<div class="row"><div><b>${x[0]}</b><div class="m" dir="ltr" style="text-align:right">${esc(location.host+x[1])}</div></div><button class="btn s g" onclick="copyLink('${x[1]}')">نسخ</button></div>`).join("")+`<h2>نسخة احتياطية</h2><div class="box"><p class="m" style="margin-top:0">بتنزّل ملف واحد (JSON) فيه كل بيانات الصالون: الفواتير والعملاء والموظفين والمخزون والإعدادات. احتفظ بيه في مكان آمن، لأن فيه أرقام العملاء.</p><button class="btn" id="bkb" style="width:100%" onclick="backupAll()">⬇️ تنزيل نسخة احتياطية الآن</button><div class="m" id="bkm" style="margin-top:8px">${lastBk()}</div></div>`;
if(sec=="book")h+=`<h2>صفحة الحجز المستقلة</h2><div class="chips"><a class="btn g s" style="text-decoration:none" href="/qr" target="_blank">🔳 باركود تطبيق الحجز</a><button class="btn g s" onclick="copyBook()">نسخ رابط الحجز</button></div><div class="m" style="margin-bottom:6px">العملاء بيحجزوا من الرابط ده من غير تسجيل ولا تطبيق.</div><h2>منيو الخدمات</h2><button class="btn g s" onclick="go('svc')">إدارة الخدمات (إضافة / تعديل / إيقاف)</button>`;
if(sec=="stock")h+=`<h2>المنتجات</h2>`+pr.map(x=>row("products",x,`بيع ${x.price} · شراء ${x.cost} · الحد الأدنى ${x.min_stock}`)).join("")+`<button class="btn g s" onclick="addItem('products')">+ منتج جديد</button>`;
if(sec=="loy")h+=`<h2>مكافآت الولاء</h2>`+(rw||[]).map(x=>`<div class="row"><div><b>${esc(x.name)}</b><div class="m">${x.cost} نقطة ${x.active?"":"· موقوفة"}</div></div><button class="btn s g" onclick="togRw(${x.id},${!x.active})">${x.active?"إيقاف":"تفعيل"}</button></div>`).join("")+`<button class="btn g s" onclick="addRw()">+ مكافأة جديدة</button>`;
if(sec=="staff")h+=`<h2>إدارة الموظفين</h2><div class="chips"><button class="btn g" onclick="go('team')">الموظفين والصلاحيات والشيفتات</button><button class="btn g" onclick="resetAllPerms()">إرجاع صلاحيات الكل للافتراضي</button></div>`;
if(RST[sec])h+=`<h2 style="color:var(--red)">${sec=="danger"?"منطقة الخطر":"تصفير"}</h2>`+RST[sec].map(r=>`<button class="row" style="cursor:pointer;color:var(--red);font-weight:600" onclick="doReset('${r[0]}',this.textContent)">${r[1]}</button>`).join("");
put(h)};

async function saveSec(){const rows=[];(FLD[C.sec]||[]).forEach(([k,l,t])=>{const e=$("s_"+k);if(!e)return;if(t=="bool")rows.push({key:k,value:e.checked});else if(t=="number"||t=="day"){if(e.value!=="")rows.push({key:k,value:+e.value})}else rows.push({key:k,value:e.value})});
const{error}=await sb.from("app_settings").upsert(rows);error?toast(error.message):(toast("تم الحفظ ✓"),loadCfg())}

async function doReset(scope,label){const w=prompt(label+"\n\nالعملية دي مش هتترجّع. اكتب كلمة: تصفير");if(w!=="تصفير")return toast("اتلغى");const{data,error}=await sb.rpc("reset_data",{p_scope:scope,p_confirm:w});error?toast(error.message):toast(data||"تم التصفير ✓")}

async function resetAllPerms(){if(!confirm("ترجّع صلاحيات كل الحلاقين والكاشير للافتراضي؟"))return;const{error}=await sb.from("profiles").update({perms:{}}).in("role",["barber","cashier","assistant"]);error?toast(error.message):toast("تم ✓")}
