/* features/control/autopilot.js — التشغيل الذاتي: المالك يحدد السياسة مرة، والسيستم يقرر لوحده في حدودها ويرجعله بالاستثناءات */

const apAMissing=e=>e&&/autopilot_/i.test(e.message||"")&&/(does not exist|schema cache|Could not find)/i.test(e.message||"");
const AP_K={discount:"خصم",void:"إلغاء فاتورة",policy:"تغيير السياسة"},AP_A={book:"الحجوزات والطابور",members:"الأعضاء والمتجر",stock:"المخزون",cash:"الخزنة وقفل اليوم",team:"الفريق",cust:"العملاء",debt:"الديون",cafe:"الكوفي"},AP_D={approved:"✅ اتنفّذ تلقائي",escalated:"⬆️ اترفع للمالك",error:"⚠️ خطأ",changed:"✎"};
const apN=v=>{const s=String(v??"").trim().replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d));const n=Number(s);return s!==""&&Number.isFinite(n)&&n>=0?n:NaN};

V.auto=async function(){
if(!(me.role=="owner"||me.role=="manager"))return put(`<h1>التشغيل الذاتي</h1><p class="m">الشاشة دي للإدارة بس.</p>`);
const{data,error}=await sb.rpc("autopilot_get");
if(error)return put(`<h1>التشغيل الذاتي</h1><p class="m">${apAMissing(error)?"الميزة لسه مش متفعّلة: شغّل ملف patch_autopilot.sql في Supabase الأول.":esc(error.message)}</p>`);
const p=data.policy,own=!!data.owner,L=data.log||[],SG=data.suggestions||[];C.apPol=p;
const row=(t,k,v,sub)=>`<div class="row"><div><b>${t}</b>${sub?`<div class="m">${sub}</div>`:""}</div><div style="text-align:left"><b>${v}</b>${own?` <button class="btn s g" onclick="apEdit('${k}')">تعديل</button>`:""}</div></div>`;
const tg=(t,k,on,sub)=>`<div class="row"><div><b>${t}</b>${sub?`<div class="m">${sub}</div>`:""}</div><div>${own?`<button class="btn s ${on?"":"g"}" onclick="apToggle('${k}')">${on?"شغّال":"مقفول"}</button>`:`<b>${on?"شغّال":"مقفول"}</b>`}</div></div>`;
put(`<h1>التشغيل الذاتي</h1>
<p class="m">انت بتحدد الحدود مرة واحدة، والسيستم بيقرر لوحده جواها من غير ما حد يستنى حد. أي حاجة برّه الحدود بتتوقف وبتوصلك. كل قرار تلقائي بيتسجّل وبيوصلك إشعار. مفيش خصم رواتب ولا جزاءات ولا تغيير عمولات.</p>
${tg("التشغيل الذاتي (الزرار الرئيسي)","enabled",p.enabled,p.enabled?"السيستم بيقرر في حدود السياسة":"مقفول: كل الطلبات بتستنى قرار يدوي زي الأول")}
<h2>الخصومات</h2>
${tg("موافقة تلقائية على الخصم فوق حدّ الكاشير","disc_auto",p.disc_auto)}
${row("أقصى نسبة خصم تلقائي","disc_auto_max_pct",+p.disc_auto_max_pct+"%","فوقها بتستنى قرارك")}
${row("سقف الخصومات التلقائية في اليوم","disc_auto_daily_total",fm(p.disc_auto_daily_total),"إجمالي مبالغ الخصم")}
<h2>إلغاء الفواتير</h2>
${tg("إلغاء تلقائي لغلطة الموظف في فاتورته","void_auto",p.void_auto,"بس لفاتورة الموظف نفسه، واليوم مش مقفول")}
${row("مدة السماح بعد إنشاء الفاتورة","void_auto_minutes",p.void_auto_minutes+" دقيقة")}
${row("أقصى قيمة فاتورة","void_auto_max_total",fm(p.void_auto_max_total))}
${row("أقصى عدد إلغاءات تلقائية في اليوم","void_auto_daily_max",p.void_auto_daily_max)}
<h2>اقتراحات السيستم</h2>
<p class="m">باقي الأقسام «اقتراح فقط»: السيستم يفحص كل 15 دقيقة ويقترح، وإنت بتضغط تم أو تجاهل. مفيش أي حركة فلوس بتتم لوحدها.</p>
${tg("الحجوزات والطابور","book_on",p.book_on,"ينبّه لحجز عدّى ميعاده والعميل لسه ماوصلش")}
${row("التأخير قبل التنبيه","book_late_min",p.book_late_min+" دقيقة")}
${tg("الأعضاء والمتجر","members_on",p.members_on,"اشتراك قرّب يخلص، وحجز منتج واقف من فترة")}
${row("ينبّه قبل انتهاء الاشتراك بـ","mem_expiry_days",p.mem_expiry_days+" يوم")}
${row("حجز المنتج الواقف أكتر من","reserve_days",p.reserve_days+" يوم")}
${tg("المخزون","stock_on",p.stock_on,"خامة وصلت للحد الأدنى")}
${tg("الخزنة وقفل اليوم","cash_on",p.cash_on,"اليوم ماتقفلش، أو فرق في الدُرج")}
${row("ينبّه لو اليوم ماتقفلش بعد الساعة","cash_close_hour",p.cash_close_hour+":00")}
${row("أقصى فرق مقبول في الدُرج","cash_diff_limit",fm(p.cash_diff_limit))}
${tg("الفريق","team_on",p.team_on,"حضور مفتوح من غير انصراف، وتحديات وطلبات نقاط مستنية")}
${row("حضور مفتوح أكتر من","team_open_hours",p.team_open_hours+" ساعة")}
${tg("العملاء","cust_on",p.cust_on,"طلبات استبدال نقاط ومدفوعات العملاء اللي محدش راجعها")}
${tg("الديون","debt_on",p.debt_on,"فواتير آجلة قديمة لسه مسدّدتش")}
${row("الدين القديم بعد","debt_days",p.debt_days+" يوم")}
${tg("الكوفي","cafe_on",p.cafe_on,"منتج كوفي وصل للحد الأدنى")}
<h2>الاقتراحات المفتوحة</h2>
${SG.length?SG.map(x=>`<div class="row"><div><b>${esc(x.title)}</b><div class="m">${AP_A[x.area]||""} · ${esc(x.body||"")}</div></div><div style="text-align:left"><button class="btn s" onclick="apDecide(${x.id},true)">تم</button> <button class="btn s g" onclick="apDecide(${x.id},false)">تجاهل</button></div></div>`).join(""):`<p class="m">مفيش اقتراحات دلوقتي.</p>`}
<h2>سجل القرارات التلقائية</h2>
${L.length?L.map(x=>{const d=x.detail||{};return `<div class="row"><div><b>${AP_K[x.kind]||esc(x.kind)} · ${AP_D[x.decision]||esc(x.decision)}</b><div class="m">${esc(d.why||d.reason||d.err||(d.invoice_no?"فاتورة "+d.invoice_no+" · "+fm(d.total):"")||(d.pct?d.pct+"% · "+fm(d.amount):""))}</div><div class="m">${new Date(x.at).toLocaleString("ar-EG",{dateStyle:"short",timeStyle:"short"})}</div></div></div>`}).join(""):`<p class="m">لسه مفيش قرارات.</p>`}`)};

async function apSave(o){const{error}=await sb.rpc("autopilot_save",{p_policy:o});error?toast(error.message):(toast("اتحفظ ✓"),V.auto())}
async function apDecide(id,ok){const{error}=await sb.rpc("autopilot_suggestion_decide",{p_id:id,p_done:ok});error?toast(error.message):V.auto()}
async function apToggle(k){const p=C.apPol||{},on=!p[k];
if(k=="enabled"&&on&&!await askConfirm("تشغيل التشغيل الذاتي؟ السيستم هيوافق على الخصومات ويلغي الفواتير لوحده في حدود السياسة اللي تحتها. راجع الأرقام الأول."))return;
apSave({[k]:on})}
async function apEdit(k){const p=C.apPol||{},L={disc_auto_max_pct:"أقصى نسبة خصم تلقائي (%)",disc_auto_daily_total:"سقف الخصومات التلقائية في اليوم (جنيه)",void_auto_minutes:"مدة السماح بعد إنشاء الفاتورة (دقيقة، 0 إلى 240)",void_auto_max_total:"أقصى قيمة فاتورة تتلغي تلقائي (جنيه)",book_late_min:"التأخير قبل التنبيه (دقيقة، 5 إلى 240)",mem_expiry_days:"قبل انتهاء الاشتراك بكام يوم (1 إلى 60)",reserve_days:"حجز المنتج الواقف أكتر من كام يوم (1 إلى 30)",cash_close_hour:"الساعة (0 إلى 23)",team_open_hours:"حضور مفتوح أكتر من كام ساعة (6 إلى 24)",debt_days:"الدين القديم بعد كام يوم (1 إلى 90)",cash_diff_limit:"أقصى فرق مقبول في الدُرج (جنيه)",void_auto_daily_max:"أقصى عدد إلغاءات تلقائية في اليوم"};
const v=apN(await askInput(L[k],String(p[k])));if(Number.isNaN(v))return toast("الرقم غلط");apSave({[k]:v})}
