/* features/control/autopilot.js — التشغيل الذاتي: المالك يحدد السياسة مرة، والسيستم يقرر لوحده في حدودها ويرجعله بالاستثناءات */

const apAMissing=e=>e&&/autopilot_/i.test(e.message||"")&&/(does not exist|schema cache|Could not find)/i.test(e.message||"");
const AP_K={discount:"خصم",void:"إلغاء فاتورة",policy:"تغيير السياسة"},AP_D={approved:"✅ اتنفّذ تلقائي",escalated:"⬆️ اترفع للمالك",error:"⚠️ خطأ",changed:"✎"};
const apN=v=>{const s=String(v??"").trim().replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d));const n=Number(s);return s!==""&&Number.isFinite(n)&&n>=0?n:NaN};

V.auto=async function(){
if(!(me.role=="owner"||me.role=="manager"))return put(`<h1>التشغيل الذاتي</h1><p class="m">الشاشة دي للإدارة بس.</p>`);
const{data,error}=await sb.rpc("autopilot_get");
if(error)return put(`<h1>التشغيل الذاتي</h1><p class="m">${apAMissing(error)?"الميزة لسه مش متفعّلة: شغّل ملف patch_autopilot.sql في Supabase الأول.":esc(error.message)}</p>`);
const p=data.policy,own=!!data.owner,L=data.log||[];C.apPol=p;
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
<h2>سجل القرارات التلقائية</h2>
${L.length?L.map(x=>{const d=x.detail||{};return `<div class="row"><div><b>${AP_K[x.kind]||esc(x.kind)} · ${AP_D[x.decision]||esc(x.decision)}</b><div class="m">${esc(d.why||d.reason||d.err||(d.invoice_no?"فاتورة "+d.invoice_no+" · "+fm(d.total):"")||(d.pct?d.pct+"% · "+fm(d.amount):""))}</div><div class="m">${new Date(x.at).toLocaleString("ar-EG",{dateStyle:"short",timeStyle:"short"})}</div></div></div>`}).join(""):`<p class="m">لسه مفيش قرارات.</p>`}`)};

async function apSave(o){const{error}=await sb.rpc("autopilot_save",{p_policy:o});error?toast(error.message):(toast("اتحفظ ✓"),V.auto())}
async function apToggle(k){const p=C.apPol||{},on=!p[k];
if(k=="enabled"&&on&&!await askConfirm("تشغيل التشغيل الذاتي؟ السيستم هيوافق على الخصومات ويلغي الفواتير لوحده في حدود السياسة اللي تحتها. راجع الأرقام الأول."))return;
apSave({[k]:on})}
async function apEdit(k){const p=C.apPol||{},L={disc_auto_max_pct:"أقصى نسبة خصم تلقائي (%)",disc_auto_daily_total:"سقف الخصومات التلقائية في اليوم (جنيه)",void_auto_minutes:"مدة السماح بعد إنشاء الفاتورة (دقيقة، 0 إلى 240)",void_auto_max_total:"أقصى قيمة فاتورة تتلغي تلقائي (جنيه)",void_auto_daily_max:"أقصى عدد إلغاءات تلقائية في اليوم"};
const v=apN(await askInput(L[k],String(p[k])));if(Number.isNaN(v))return toast("الرقم غلط");apSave({[k]:v})}
