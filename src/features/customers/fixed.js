/* features/customers/fixed.js — مواعيد ثابتة للزباين: حجز تلقائي + إشعار بتذكير واتساب جاهز */

const FX_DAYS=["الأحد","الاتنين","التلات","الأربع","الخميس","الجمعة","السبت"],FX_PER={morning:"الصبح",afternoon:"العصر",evening:"المساء",night:"بعد منتصف الليل"};
const fxMissing=e=>e&&/fixed_reminder|fixed_run/i.test(e.message||"")&&/(does not exist|schema cache|Could not find)/i.test(e.message||"");

V.fix=async function(){
const{data,error}=await sb.rpc("fixed_reminder_list");
if(error)return put(`<h1>مواعيد ثابتة</h1><button class="btn s g" onclick="go('rem')">← التذكير</button><p class="m" style="margin-top:10px">${fxMissing(error)?"الميزة لسه مش متفعّلة: شغّل ملف patch_fixed_reminders.sql في Supabase الأول.":esc(error.message)}</p>`);
C.fx=data||{items:[],pending:[]};
const P=C.fx.pending||[],L=C.fx.items||[];
put(`<h1>مواعيد ثابتة</h1><div style="display:flex;gap:6px;flex-wrap:wrap;margin:6px 0"><button class="btn s g" onclick="go('rem')">← التذكير</button><button class="btn s" onclick="fxEdit(null)">+ ميعاد ثابت جديد</button></div>
<p class="m">في اليوم والساعة اللي تحددهم السيستم يحجز دور للزبون (اختياري) ويبعتلك إشعار، وانت تبعتله رسالة التذكير بالواتساب بضغطة.</p>
${P.length?`<h2>📨 مستني تبعت (${P.length})</h2>`+P.map(x=>`<div class="box" style="margin-top:8px"><b>${esc(x.name)}</b> <span class="m" dir="ltr">${esc(x.phone||"")}</span>${x.note?`<div class="m">${esc(x.note)}</div>`:""}<div class="m" style="margin:6px 0;white-space:pre-wrap">${esc(x.message)}</div>
<div style="display:flex;gap:6px;flex-wrap:wrap"><button class="btn s" onclick="fxSend(${x.id})">📲 ابعت واتساب</button><button class="btn s g" onclick="fxMark(${x.id},'dismissed')">تجاهل</button></div></div>`).join(""):""}
<h2>المواعيد</h2>`+(L.length?L.map(x=>`<div class="row"><div><b>${esc(x.name)}</b> ${x.active?"":`<span class="m">(موقوف)</span>`}<div class="m">كل ${FX_DAYS[x.weekday]} الساعة ${esc(x.time)} · ${x.book?"بيحجز دور "+(x.offset?"بعد "+x.offset+" يوم":"نفس اليوم")+" "+(FX_PER[x.period]||""):"تذكير بس"}${x.last?" · آخر تنفيذ "+esc(x.last):""}</div></div>
<div style="text-align:left"><button class="btn s g" onclick="fxEdit(${x.id})">تعديل</button> <button class="btn s g" onclick="fxDel(${x.id})">مسح</button></div></div>`).join(""):`<p class="m">مفيش مواعيد ثابتة لسه. دوس «+ ميعاد ثابت جديد».</p>`))};

async function fxSend(id){const x=(C.fx.pending||[]).find(a=>a.id==id);if(!x)return;const n=waNum(x.phone);if(!n)return toast("رقم الموبايل ناقص أو غلط");
window.open("https://wa.me/"+n+"?text="+encodeURIComponent(x.message),"_blank","noopener");
if(await askConfirm("بعت الرسالة؟ (هتتشال من القايمة)",{ok:"أيوه بعتها"}))fxMark(id,"sent")}
async function fxMark(id,st){const{error}=await sb.rpc("fixed_run_mark",{p_run:id,p_status:st});error?toast(error.message):V.fix()}
async function fxDel(id){if(!await askConfirm("تمسح الميعاد الثابت ده؟",{danger:true,ok:"مسح"}))return;const{error}=await sb.rpc("fixed_reminder_delete",{p_id:id});error?toast(error.message):V.fix()}

// نموذج بسيط: fields=[{k,label,type:'select'|'text'|'time',opts:[[v,l]],val}]
function fxForm(title,fields){return new Promise(res=>{const o=document.createElement("div");
o.style.cssText="position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:9999;display:flex;align-items:center;justify-content:center;padding:16px";
o.innerHTML=`<div class="box" style="max-width:420px;width:100%;max-height:85vh;overflow:auto;background:var(--card,#fff)"><h3 class="sec">${esc(title)}</h3>${fields.map(f=>`<label class="m">${esc(f.label)}</label>${f.type=="select"?`<select data-k="${f.k}">${f.opts.map(p=>`<option value="${esc(String(p[0]))}" ${String(p[0])==String(f.val)?"selected":""}>${esc(p[1])}</option>`).join("")}</select>`:`<input data-k="${f.k}" type="${f.type=="time"?"time":"text"}" value="${esc(String(f.val??""))}" ${f.ph?`placeholder="${esc(f.ph)}"`:""}>`}`).join("")}<div style="display:flex;gap:8px;margin-top:10px"><button class="btn" id="fxOk" style="flex:1">حفظ</button><button class="btn g" id="fxNo" style="flex:1">إلغاء</button></div></div>`;
document.body.appendChild(o);const done=v=>{o.remove();res(v)};
o.querySelector("#fxOk").onclick=()=>{const r={};o.querySelectorAll("[data-k]").forEach(e=>r[e.dataset.k]=e.value);done(r)};o.querySelector("#fxNo").onclick=()=>done(null)})}

async function fxEdit(id){if(C.fxBusy)return;const x=id?(C.fx.items||[]).find(a=>a.id==id):null;let cid=x?x.customer_id:null;
if(!x){const ph=(await askInput("رقم موبايل الزبون (01xxxxxxxxx)")||"").replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/\D/g,"");if(!ph)return;
 const{data:c}=await sb.from("customers").select("id,name,phone").eq("phone",ph).maybeSingle();if(!c)return toast("مفيش عميل بالرقم ده — سجّله الأول من شاشة العملاء");
 if(!await askConfirm("الزبون: "+c.name+" ("+c.phone+")؟"))return;cid=c.id}
const{data:br}=await sb.from("profiles").select("id,full_name").eq("role","barber");
const f=await fxForm(x?"تعديل الميعاد":"ميعاد ثابت جديد",[
 {k:"wd",label:"اليوم اللي السيستم يشتغل فيه",type:"select",opts:FX_DAYS.map((d,i)=>[i,d]),val:x?x.weekday:2},
 {k:"tm",label:"الساعة",type:"time",val:x?x.time:"22:00"},
 {k:"bk",label:"السيستم يحجز دور للزبون؟",type:"select",opts:[["1","أيوه، يحجز + يبعتلي إشعار"],["0","لأ، إشعار تذكير بس"]],val:x?(x.book?"1":"0"):"1"},
 {k:"off",label:"الدور يبقى لأنهي يوم؟",type:"select",opts:[["0","نفس اليوم"],["1","بكرة"],["2","بعد يومين"],["3","بعد 3 أيام"]],val:x?x.offset:0},
 {k:"per",label:"فترة الدور",type:"select",opts:Object.entries(FX_PER),val:x&&x.period?x.period:"evening"},
 {k:"br",label:"الحلاق",type:"select",opts:[["","أي حلاق متاح"],...(br||[]).map(b=>[b.id,b.full_name])],val:x&&x.barber_id?x.barber_id:""},
 {k:"msg",label:"نص الرسالة (اتساب فاضي = الرسالة الجاهزة). تقدر تكتب {name} و{day}",type:"text",val:x&&x.message?x.message:"",ph:"أهلاً {name} 👋 بنفكرك بميعادك في صالون أبو يوسف ✂️ {day}"}]);
if(!f)return;
if(!/^\d{2}:\d{2}$/.test(f.tm))return toast("اكتب الساعة");
C.fxBusy=1;const{error}=await sb.rpc("fixed_reminder_save",{p_id:x?x.id:null,p_customer:cid,p_weekday:+f.wd,p_time:f.tm,p_book:f.bk=="1",p_offset:+f.off,p_period:f.bk=="1"?f.per:null,p_barber:f.br||null,p_services:x?x.services||[]:[],p_message:f.msg||null,p_active:x?x.active:true});C.fxBusy=0;
error?toast(error.message):(toast("اتحفظ ✓"),V.fix())}
