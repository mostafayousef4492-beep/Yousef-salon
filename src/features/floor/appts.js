/* features/floor/appts.js — الحجوزات والطابور */

// ================= موظفين: الدور والحضور بالموقع =================

const TC=a=>(a.is_urgent?"⚡ ":"")+(a.ticket_code||("#"+a.ticket_no));

// حالة التذكرة بالعربي: انتظار / تم الاستدعاء / حاضر / جارٍ تنفيذ / مكتملة / متخطّاة
const tkState=a=>a.status=="no_show"?"متخطّاة":a.status=="done"?"مكتملة":a.status=="in_service"?"جارٍ تنفيذ":a.status=="checked_in"?"حاضر":a.called_at?("تم الاستدعاء"+(a.call_count>1?" ×"+a.call_count:"")+(a.eta=="on_way"?" (في الطريق)":a.eta=="arrived"?" (بيقول وصل)":"")):"انتظار";

V.appts=async()=>{const t=new Date().toLocaleDateString("en-CA");
if(+C.cfg.no_show_after_minutes>0){try{await sb.rpc("run_no_show_sweep")}catch(e){}}
const SEL="id,day,period,ticket_no,ticket_code,is_urgent,urgent_state,sort_at,call_count,status,called_at,eta,finished_at,customer_id,barber_id,customers(name),profiles(full_name),appointment_services(service_id,services(name))";
let q=sb.from("appointments").select(SEL);q=dfOn("ap")?dfQ(q,"day","ap"):q.or("day.gte."+t+",status.eq.in_service").not("status","in","(cancelled,done)");
const[{data},{data:aw},{data:tr}]=await Promise.all([q.order("day").order("sort_at"),sb.rpc("tickets_awaiting_payment"),sb.rpc("pending_transfers")]);
const all=data||[];let awT=[];if(aw&&aw.length){const{data:d2}=await sb.from("appointments").select(SEL).in("id",aw.map(x=>x.id));awT=d2||[]}
C.A=[...all.filter(a=>a.status!="no_show"),...awT.filter(a=>!all.some(x=>x.id==a.id))];const sk=all.filter(a=>a.status=="no_show"&&a.day==t);
const nm=a=>esc(a.customers?.name||"عميل"),sv=a=>(a.appointment_services||[]).map(x=>esc(x.services?.name||"")).filter(Boolean).join(" + ");
const live=all.filter(a=>a.status!="no_show");
const stale=(can("use_pos")||isAdm(me))?live.filter(a=>a.status=="in_service"&&a.day<t):[],qlive=live.filter(a=>!stale.includes(a));
put(`<h1>الدور</h1><button class="btn s" onclick="admForm()">+ حجز إداري</button><div id="adm"></div>${dfBar("ap","V.appts()")}`
+(tr&&tr.length?`<h2>طلبات نقل لحلاق تاني</h2>`+tr.map(r=>`<div class="row"><div><b dir="ltr">${esc(r.old_code||"")}</b> · ${esc(r.customer_name||"عميل")}<div class="m">من ${esc(r.from_name||"—")} ← إلى ${esc(r.to_name||"—")}${r.reason?" · "+esc(r.reason):""}</div></div><div><button class="btn s" onclick="trDecide(${r.id},true)">موافقة</button> <button class="btn s g" onclick="trDecide(${r.id},false)">رفض</button></div></div>`).join(""):"")
+(awT.length?`<h2>خلصت وبانتظار الدفع</h2>`+awT.map(a=>`<div class="row"><div><b dir="ltr">${TC(a)}</b> · ${nm(a)}<div class="m">${sv(a)} · ${esc(a.profiles?.full_name||"-")}</div></div>${can("use_pos")?`<button class="btn s" onclick="payAppt(${a.id})">دفع</button>`:""}</div>`).join(""):"")
+(stale.length?`<h2>⚠️ تذاكر عالقة من أيام فاتت</h2>`+stale.map(a=>`<div class="row"><div><b dir="ltr">${TC(a)}</b> · ${nm(a)}<div class="m">يوم ${a.day} · ${sv(a)} · ${esc(a.profiles?.full_name||"-")}</div></div><button class="btn s" onclick="closeStale(${a.id},'${TC(a)}')">قفل</button></div>`).join(""):"")
+`<h2>الطابور</h2>`
+(qlive.length?qlive.map(a=>`<div class="row"><div><b dir="ltr">${TC(a)}</b> · ${nm(a)}<div class="m">${a.day} · ${PLB[a.period]} · ${sv(a)} · ${esc(a.profiles?.full_name||"-")}</div></div><div style="text-align:left"><span class="tag">${tkState(a)}</span>${a.is_urgent?` <span class="tag" style="background:var(--red);color:#fff">⚡ مستعجل</span>`:(isAdm(me)&&C.cfg.urgent_enabled!==false&&["upcoming","checked_in"].includes(a.status)?` <button class="btn s g" onclick="if(confirm('تحوّل التذكرة دي لمستعجل؟ هتبقى أول الدور والحساب ×'+(+C.cfg.urgent_multiplier||2))){tk('make_urgent',${a.id})}">⚡ مستعجل</button>`:"")}<br>${a.status=="upcoming"?`<button class="btn s" onclick="tk('call_ticket',${a.id})">${a.called_at?"إعادة نداء":"استدعاء"}</button> <button class="btn s g" onclick="tk('confirm_arrival',${a.id})">حضر</button> `:""}${a.status=="checked_in"?`<button class="btn s" onclick="setS(${a.id},'in_service')">ابدأ الخدمة</button> `:""}${a.status=="in_service"?`<button class="btn s g" onclick="tk('finish_ticket',${a.id})">انتهت</button> `:""}${["upcoming","checked_in","in_service"].includes(a.status)&&can("use_pos")?`<button class="btn s" onclick="payAppt(${a.id})">دفع مباشر</button> `:""}${a.status=="upcoming"||a.status=="checked_in"?`<button class="btn s g" onclick="moveT(${a.id})">نقل</button> <button class="btn s g" onclick="skipT(${a.id})">تخطّي</button> `:""}${a.status=="upcoming"||a.status=="checked_in"?`<button class="btn s g" onclick="setS(${a.id},'cancelled')">إلغاء</button>`:""}${isAdm(me)?` <button class="btn s g" style="color:var(--red)" onclick="delAppt('${a.id}')">حذف</button>`:""}</div></div>`).join(""):`<p class="m">${dfOn("ap")?"مفيش حجوزات في الفترة دي.":"مفيش دور محجوز."}</p>`)
+(sk.length?`<h2>متخطّين النهارده</h2>`+sk.map(a=>`<div class="row"><div><b dir="ltr">${TC(a)}</b> · ${nm(a)}<div class="m">${esc(a.profiles?.full_name||"-")}</div></div><button class="btn s" onclick="tk('return_ticket',${a.id})">رجّعه لآخر الطابور</button></div>`).join(""):""));
clearInterval(C.poll);C.poll=setInterval(()=>{if(tab=="appts"&&!($("adm")&&$("adm").innerHTML)){$("app").classList.add("still");V.appts()}},30000)};

// قفل تذكرة عالقة "جارٍ تنفيذ" من يوم فات (لو ليها فاتورة تتقفل مكتملة، ولو مالهاش تتلغي)
async function closeStale(id,lbl){
  if(!confirm("تقفل التذكرة "+lbl+" العالقة؟\nلو ليها فاتورة هتتقفل مكتملة، ولو مالهاش هتتلغي."))return;
  const{data,error}=await sb.rpc("close_stale_ticket",{p_id:id});
  if(error)return toast(error.code=="PGRST202"?"شغّل patch_close_stale.sql في Supabase الأول":error.message);
  toast(data=="done"?"اتقفلت (مكتملة) ✓":"اتلغت ✓");V.appts();
}

// تخطّي بسبب إجباري، وقرار طلب النقل
async function skipT(id){const r=prompt("سبب التخطّي (لازم تكتب سبب)","لم يحضر");if(r==null)return;const{error}=await sb.rpc("skip_ticket",{p_id:id,p_reason:r});error?toast(error.message):(tab=="appts"?go("appts"):C.reload())}

async function trDecide(id,ok){const note=ok?null:(prompt("سبب الرفض (اختياري)")||null);const{error}=await sb.rpc("decide_transfer",{p_req:id,p_ok:ok,p_note:note});error?toast(error.message):(toast(ok?"اتنقلت ✓":"اترفض"),tab=="home"?go("home"):tab=="appts"?go("appts"):C.reload())}

// ===== الرئيسية: مركز قيادة الصالون (بيانات حقيقية، من غير أي شيء شكلي) =====

function qa(t,f,id){go(t);let n=0;const w=setInterval(()=>{if($(id)||++n>40){clearInterval(w);if($(id))window[f]()}},100)}

async function homeCall(id){const{error}=await sb.rpc("call_ticket",{p_id:id});error?toast(error.message):(toast("تم الاستدعاء ✓"),go("home"))}

async function tk(f,id){const{error}=await sb.rpc(f,{p_id:id});error?toast(error.message):(tab=="appts"?go("appts"):C.reload())}

async function loadV(){const P=C.P,keep=P.rid;P.rid="";P.vs=[];if(P.cid&&C.cfg.ff_loyalty!==false){const{data}=await sb.from("loyalty_redemptions").select("id,code,loyalty_rewards(name)").eq("customer_id",P.cid).eq("status","active");P.vs=data||[];if(keep&&P.vs.some(v=>String(v.id)==String(keep)))P.rid=String(keep)}drawPos()}

const getPos=()=>new Promise(r=>navigator.geolocation?navigator.geolocation.getCurrentPosition(p=>r({lat:p.coords.latitude,lng:p.coords.longitude}),()=>r({}),{enableHighAccuracy:true,timeout:12000,maximumAge:0}):r({}));

// ---- الحجز الإداري + لم يحضر ----

async function admForm(){const e=$("adm");if(e.innerHTML)return e.innerHTML="";const[{data:sv},{data:br}]=await Promise.all([sb.from("services").select("id,name,price,group_name,option_label").eq("active",true).order("id"),sb.from("profiles").select("id,full_name").eq("role","barber").order("full_name")]);await BN.load(sb);C.ad={s:[],bd:null,walk:false,sv:sv||[],br:br||[]};drawAdm()}

function drawAdm(){const A=C.ad,e=$("adm");if(!e)return;const nm=$("ad_n")?$("ad_n").value:"",ph=$("ad_p")?$("ad_p").value:"",day=$("ad_d")?$("ad_d").value:ymd(new Date()),pe=$("ad_pe")?$("ad_pe").value:"evening",bb=$("ad_b")?$("ad_b").value:"";
  e.innerHTML=`<div class="box" style="margin:10px 0"><div class="m">حجز إداري (بيدخل الدور زي أي حجز) — الخدمات اختيارية</div><div class="chips"><button class="chip ${A.walk?"sel":""}" onclick="admWk()">وصل الصالون دلوقتي (Walk-in)</button>${isAdm(me)&&C.cfg.urgent_enabled!==false?`<button class="chip ${A.urgent?"sel":""}" onclick="C.ad.urgent=!C.ad.urgent;drawAdm()">⚡ مستعجل (حاضر دلوقتي · أول الدور · الحساب ×${+C.cfg.urgent_multiplier||2})</button>`:""}</div><input id="ad_n" placeholder="اسم العميل" value="${esc(nm)}"><input id="ad_p" type="tel" inputmode="numeric" placeholder="موبايل العميل" value="${esc(ph)}">${BN.html(A,"admBn",fm)}${SG.render(A.sv,A.s,(x,s,sh)=>`<button class="chip ${s?"sel":""}" onclick="admTg(${x.id})">${BN.star(A,x.id)}${esc(sh?SG.label(x):x.name)} · ${x.price}</button>`)}${BN.summary(A,A.sv,fm)}<select id="ad_b"><option value="">أي حلاق (الأقل زحمة)</option>${A.br.map(x=>`<option value="${x.id}" ${bb==x.id?"selected":""}>${esc(x.full_name)}</option>`).join("")}</select>${A.walk?`<div class="m">هيتسجّل في دور الحلاق المختار النهارده (لو سيبته فاضي بيقترح الأقل زحمة).</div>`:`<input id="ad_d" type="date" value="${day}" min="${ymd(new Date())}"><select id="ad_pe">${Object.entries(PLB).map(([k,v])=>`<option value="${k}" ${pe==k?"selected":""}>${v}</option>`).join("")}</select>`}<div class="chips"><button class="btn" onclick="admSave()">حجز</button><button class="btn g" onclick="$('adm').innerHTML=''">إلغاء</button></div></div>`}

function admTg(id){const A=C.ad;A.s=SG.tog(A.s,id,A.sv);BN.sync(A);drawAdm()}
function admBn(id){BN.pick(C.ad,id);drawAdm()}

async function admSave(){if(C.admBusy)return;const A=C.ad,n=$("ad_n").value.trim(),ph=($("ad_p").value||"").replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/\D/g,"");if(n.length<2)return toast("اكتب اسم العميل");if(!/^01\d{9}$/.test(ph))return toast("الموبايل لازم 11 رقم ويبدأ بـ 01");
  const br=$("ad_b").value||null;C.admBusy=true;
  if(A.urgent){if(!A.s.length)return toast("اختار الخدمة الأول عشان الحساب ×"+(+C.cfg.urgent_multiplier||2));C.admBusy=true;const ur=await sb.rpc("admin_urgent_ticket",{p_name:n,p_phone:ph,p_barber:br,p_services:A.s});C.admBusy=false;if(ur.error)return toast(netErr(ur.error)?"فشل — النت واقف، جرّب تاني":/Could not find the function/i.test(ur.error.message||"")?"شغّل ملف patch_urgent.sql في Supabase الأول":ur.error.message);toast("اتفتحت تذكرة مستعجلة ⚡ وبقت أول الدور");return go("appts")}
  const r=A.walk?await sb.rpc("walk_in_ticket_v2",{p_customer:null,p_name:n,p_phone:ph,p_barber:br,p_services:A.s}):await sb.rpc("admin_book_ticket",{p_name:n,p_phone:ph,p_barber:br,p_day:$("ad_d").value,p_period:$("ad_pe").value,p_services:A.s});
  C.admBusy=false;const{data,error}=r;
  if(error)return toast(netErr(error)?"فشل — النت واقف، الحجز لم يتأكد. جرّب تاني (مش هيتكرر)":/walk_in_ticket_v2|PGRST202/.test(error.message||"")?"لازم تطبّق تحديث الداتابيز الأول (sql/booking_queue_upgrade.sql)":error.message);
  if(data&&data.existing){toast("العميل عنده حجز نشط بالفعل (دور #"+(data.no||data.ticket?.no||"-")+") — اتعرض بدل ما نكرره. أكّد وصوله من القايمة لو وصل.");return go("appts")}
  if(A.bd){const tid=data&&((data.ticket&&data.ticket.id)||data.id);if(!(await BN.attach(sb,A,tid)))toast("اتحجز، بس الباقة ماتسجّلتش — طبّقها من الكاشير")}
  toast(A.walk?"اتسجّل في دور الحلاق ✓":"تم الحجز ✓");
  const bo=$("ad_b"),bn=bo&&bo.value?bo.options[bo.selectedIndex].text:"",card=waTicketCard(n,ph,data,bn),ae=$("adm");
  if(card&&ae){ae.innerHTML=card;return}
  go("appts")}

async function noShow(id){return skipT(id)}

async function copyBook(){const u=location.origin+"/book";try{await navigator.clipboard.writeText(u);toast("تم نسخ الرابط ✓")}catch(e){prompt("انسخ الرابط:",u)}}

function admWk(){C.ad.walk=!C.ad.walk;drawAdm()}

async function moveT(id){const{data:br}=await sb.from("profiles").select("id,full_name").eq("role","barber").order("full_name");if(!br?.length)return toast("مفيش حلاقين");
  const k=prompt("انقل لأي حلاق؟ اكتب الرقم:\n"+br.map((x,i)=>(i+1)+") "+x.full_name).join("\n"));if(!k)return;const x=br[+k-1];if(!x)return toast("رقم غلط");
  const{data,error}=await sb.rpc("reassign_ticket",{p_id:id,p_barber:x.id});if(error)return toast(netErr(error)?"النقل لم يتأكد — النت واقف":error.message);
  toast(data&&data.changed===false?"الحجز عند نفس الحلاق":"اتنقل ✓");go("appts")}
