// صالون أبو يوسف — صفحة الحجز المستقلة (/book): من غير تسجيل ولا تحميل تطبيق، الحجز برقم الموبايل
// مستقلة عن app.js: بتستخدم Supabase بدون جلسة (anon) فمبتأثرش على دخول الموظفين أو العملاء في المتصفح ده.
const sb=supabase.createClient(SUPABASE_URL,SUPABASE_KEY,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
const $=i=>document.getElementById(i),put=h=>$("app").innerHTML=h;
const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const C={cfg:{salon_name:"صالون أبو يوسف",phone:"",address:"",currency:"ج.م",days_ahead:5,weekly_off:5,booking_open:true},sv:[],b:{s:[],day:0,period:null,barber:undefined},f:{n:"",p:""}};
const fm=n=>Math.round(n).toLocaleString("ar-EG")+" "+C.cfg.currency;
const toast=t=>{const e=document.createElement("div");e.className="toast";e.textContent=t;document.body.appendChild(e);setTimeout(()=>e.remove(),2600)};
const store={get(k){try{return JSON.parse(localStorage.getItem(k))}catch(e){return null}},set(k,v){try{localStorage.setItem(k,JSON.stringify(v))}catch(e){}},del(k){try{localStorage.removeItem(k)}catch(e){}}};
const dig=s=>String(s||"").replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/\D/g,"");
const PERIODS=[["morning","الصبح","6ص–12ظ",12],["afternoon","العصر","12–5م",17],["evening","المساء","5م–12",24],["night","بعد منتصف الليل","12–6ص",6]];
const PLB={morning:"الصبح",afternoon:"العصر",evening:"المساء",night:"بعد منتصف الليل"};
const ST={upcoming:"قادم",checked_in:"وصل",in_service:"على الكرسي",done:"خلص",cancelled:"ملغي"};
const bkDays=()=>[...Array(Math.max(+C.cfg.days_ahead||5,1))].map((_,i)=>{const d=C.biz&&C.biz.open&&C.biz.day?new Date(C.biz.day+"T12:00:00"):new Date();d.setDate(d.getDate()+i);return{i,iso:d.toLocaleDateString("en-CA"),off:d.getDay()==C.cfg.weekly_off,l:i?d.toLocaleDateString("ar-EG",{weekday:"short",day:"numeric",month:"numeric"}):"اليوم"}});
const contact=()=>`<div class="foot m">${C.cfg.phone?`للاستفسار: <a href="tel:${esc(C.cfg.phone)}">${esc(C.cfg.phone)}</a>`:""}${C.cfg.address?`<div>${esc(C.cfg.address)}</div>`:""}<div style="margin-top:8px"><a href="/">تطبيق الصالون (النقاط والعروض)</a></div></div>`;

async function init(){
  try{const{data:bz}=await sb.rpc("business_day_state");if(bz)C.biz=bz}catch(e){}
  const{data}=await sb.from("app_settings").select("*");(data||[]).forEach(r=>C.cfg[r.key]=r.value);
  document.title="احجز دورك - "+C.cfg.salon_name;$("bn").textContent=C.cfg.salon_name;
  const i=store.get("salon_book_info");if(i){C.f.n=i.n||"";C.f.p=i.p||""}
  try{const q=new URLSearchParams(location.search),tid=q.get("t"),tp=(q.get("p")||"").replace(/\D/g,"");
    if(tid&&/^\d+$/.test(tid)&&tp){store.set("salon_book_last",{id:+tid,p:tp});history.replaceState(null,"",location.pathname)}}catch(e){}
  if(store.get("salon_book_last"))return showTicket();
  start()}
async function start(){
  if(C.cfg.booking_open===false||C.cfg.booking_open==="false")return put(`<h1>احجز دورك</h1><div class="box"><p class="m">الحجز أونلاين متوقف حاليًا.</p></div>${contact()}`);
  const{data,error}=await sb.from("services").select("*").eq("active",true).order("id");
  if(error)return put(`<h1>احجز دورك</h1><p class="m">مقدرناش نحمّل الخدمات، جرّب تاني بعد شوية.</p>`);
  C.sv=data||[];await BN.load(sb);C.b={s:[],bd:null,day:0,period:null,barber:undefined};draw()}

function draw(){const b=C.b,days=bkDays();
  put(`<h1>احجز دورك</h1><p class="m" style="margin:0 0 4px">من غير تسجيل ولا تحميل تطبيق — اختار وخد رقم دورك.</p>
${BN.html(b,"tgB",fm)}<h2>الخدمات <span class="m" style="color:${b.s.length?"var(--mute)":"var(--red,#d9534f)"}">${b.s.length?"✓ اخترت "+b.s.length:"(لازم تختار خدمة واحدة على الأقل)"}</span></h2>${SG.render(C.sv,b.s,(x,s,sh)=>`<button class="chip ${s?"sel":""}" onclick="tgS(${x.id})">${BN.star(b,x.id)}${esc(sh?SG.label(x):x.name)} · ${x.price}</button>`)}${BN.summary(b,C.sv,fm)}
<h2>اليوم</h2><div class="chips">${days.map(x=>`<button class="chip ${b.day==x.i?"sel":""}" ${x.off?"disabled":""} onclick="C.b.day=${x.i};C.b.period=null;C.b.barber=undefined;draw()">${x.l}</button>`).join("")}</div>
<h2>الفترة</h2><div class="chips">${PERIODS.map(p=>`<button class="chip ${b.period==p[0]?"sel":""}" ${b.day==0&&new Date().getHours()>=p[3]?"disabled":""} onclick="C.b.period='${p[0]}';C.b.barber=undefined;draw()">${p[1]} <span class="m">${p[2]}</span></button>`).join("")}</div>
<div id="bl"></div>
<h2>بياناتك</h2><div class="box"><input id="fn" placeholder="اسمك" value="${esc(C.f.n)}" autocomplete="name" oninput="C.f.n=this.value"><input id="fp" type="tel" inputmode="numeric" pattern="[0-9٠-٩]{11}" placeholder="رقم موبايلك (01xxxxxxxxx)" value="${esc(C.f.p)}" autocomplete="tel" oninput="C.f.p=this.value">
<button class="btn" id="cbtn" style="width:100%" onclick="bookNow()" disabled>تأكيد وخد رقم دورك</button></div>${contact()}`);
  if(b.period)loadBarbers();upd()}
function tgS(id){const b=C.b;b.s=SG.tog(b.s,id,C.sv);BN.sync(b);draw()}
function tgB(id){BN.pick(C.b,id);draw()}
function upd(){const b=C.b,sv=C.sv.filter(x=>b.s.includes(x.id)),tot=BN.calc(b,C.sv).total,dur=sv.reduce((a,x)=>a+(x.duration_min||0),0),btn=$("cbtn");if(!btn)return;
  btn.disabled=!(b.s.length&&b.period&&b.barber!==undefined)||!!C.busy;
  btn.textContent=!b.s.length?"اختار الخدمة الأول":b.s.length?`تأكيد وخد رقم دورك · ${fm(tot)}${dur?" · ~"+dur+" دقيقة":""}`:"تأكيد وخد رقم دورك"}
function barberLoad(x){const n=+x.waiting||0;return (n?`<b style="color:var(--gold,#c9a24a)">معاه ${n} ${n==1?"زبون":n==2?"زبونين":"زباين"}</b>`:`<b style="color:var(--ok,#6fe3a4)">فاضي دلوقتي</b>`)+` · ~${x.est_min||0} دقيقة`}
async function arrMap(day){try{const{data,error}=await sb.rpc("barbers_arrival",{p_day:day});if(error||!data)return{};const m={};data.forEach(r=>{m[r.barber_id]=r.arrived});return m}catch(e){return{}}}
const arrTag=(m,id)=>m[id]===false?` <small style="font-weight:400;color:var(--gold,#c9a24a)">⏳ لسه مجاش</small>`:m[id]===true?` <small style="font-weight:400;color:var(--ok,#6fe3a4)">✅ وصل</small>`:"";
async function loadBarbers(){const b=C.b,d=bkDays()[b.day];
  const{data,error}=await sb.rpc("available_barbers",{p_day:d.iso,p_period:b.period});if(error)return toast(error.message);
  const AR=await arrMap(d.iso),L=data||[],sel=v=>b.barber===v?"border-color:var(--blue);box-shadow:0 0 0 2px var(--blue) inset;":"";
  if(b.barber&&!L.some(x=>x.id==b.barber))b.barber=undefined;
  $("bl").innerHTML=`<h2>الحلاق</h2>`+(L.length?`<button class="row" style="cursor:pointer;${sel(null)}" onclick="C.b.barber=null;loadBarbers();upd()"><b>أي حلاق (الأقل زحمة)</b><span class="m">أسرع دور</span></button>`+L.map(x=>`<button class="row" style="cursor:pointer;${sel(x.id)}" onclick="C.b.barber='${x.id}';loadBarbers();upd()"><b>${esc(x.full_name)}${arrTag(AR,x.id)}</b><span class="m">${barberLoad(x)}</span></button>`).join(""):`<p class="m">مفيش حلاق متاح في الفترة دي، جرّب فترة تانية.</p>`);upd()}

const isNetErr=e=>!!e&&!e.code&&!e.hint&&!e.details;
async function bookNow(){if(C.busy)return;const b=C.b,d=bkDays()[b.day],n=(C.f.n||"").trim(),ph=dig(C.f.p);
  if(!b.s.length)return toast("اختار خدمة واحدة على الأقل");if(n.length<2)return toast("اكتب اسمك");if(!/^01\d{9}$/.test(ph))return toast("الموبايل لازم 11 رقم ويبدأ بـ 01");
  const btn=$("cbtn");C.busy=true;btn.disabled=true;
  const args={p_name:n,p_phone:ph,p_barber:b.barber||null,p_day:d.iso,p_period:b.period,p_services:b.s};
  let r=await sb.rpc("public_book_v2",args),t=null,existing=false;
  if(!r.error&&r.data&&r.data.ticket){t=r.data.ticket;existing=!!r.data.existing}
  // مفيش fallback للدالة القديمة: public_book_v2 هي اللي بتضمن حجز نشط واحد + القفل. لو مش موجودة الحجز بيتوقف برسالة واضحة.
  else if(r.error&&(r.error.code=="PGRST202"||r.error.code=="42883"||/public_book_v2/.test(r.error.message||""))){C.busy=false;if(btn)btn.disabled=false;return toast("الحجز الأونلاين متوقف مؤقتًا لتحديث النظام. كلّمنا على الصالون.")}
  C.busy=false;
  if(r.error||!t){if(btn)btn.disabled=false;
    // مفيش تأكيد وهمي: الحجز ما اتأكدش. لو الرد ضاع بعد ما اتحفظ، إعادة المحاولة هترجّع نفس الحجز (حجز نشط واحد لكل رقم).
    return toast(isNetErr(r.error)?"الحجز لم يتأكد — النت واقف. جرّب تاني (مش هيتكرر).":(r.error?.code=="23505"?"حد حجز قبلك، جرّب تاني":(r.error?.message||"الحجز لم يتأكد، جرّب تاني")))}
  C.f.p=ph;store.set("salon_book_info",{n,p:ph});store.set("salon_book_last",{id:t.id,p:ph});
  if(b.bd&&!existing&&!(await BN.attach(sb,b,t.id,ph)))toast("اتحجز دورك، بس الباقة ماتسجّلتش — قول للكاشير");
  toast(existing?"عندك حجز نشط بالفعل — ده دورك":"تم الحجز ✓ ده رقم دورك");showTicket()}

// ===== تذكرة الدور (بتتحدّث لوحدها كل 8 ثواني) =====
async function showTicket(quiet){const L=store.get("salon_book_last");if(!L)return start();
  const{data,error}=await sb.rpc("public_ticket",{p_id:L.id,p_phone:L.p});const s=data?.[0];
  if(!error&&s){try{const{data:tb}=await sb.rpc("ticket_bundle",{p_id:L.id,p_phone:L.p});s.bundle=tb||null}catch(e){}try{const{data:v2,error:e2}=await sb.rpc("public_queue_status_v2",{p_id:L.id,p_phone:L.p});if(!e2&&v2){s.ahead=v2.ahead;s.est_min=v2.est_wait_min;s.current_no=v2.current_no;s.ticket_no=v2.ticket_no;s.near_turn=v2.near_turn;s.barber_arrived=v2.barber_arrived}}catch(e){}}
  if(!error&&s){try{const{data:nq}=await sb.rpc("public_queue_names",{p_id:L.id,p_phone:L.p});s.names=Array.isArray(nq)?nq:[]}catch(e){s.names=[]}}
  if(error||!s){clearInterval(C.poll);store.del("salon_book_last");return start()}
  if(s.status=="done"||s.status=="cancelled"||s.status=="no_show"){clearInterval(C.poll);store.del("salon_book_last");
    return put(`<h1>${s.status=="done"?"شكرًا لزيارتك 🙏":s.status=="no_show"?"الكاشير تخطّى دورك":"اتلغى الحجز"}</h1><div class="box" style="text-align:center"><p class="m">${s.status=="done"?"نورتنا — نتمنى نشوفك تاني قريب.":s.status=="no_show"?"الكاشير سجّل إنك مش موجود وقت دورك. كلّم الصالون أو احجز دور جديد.":"تقدر تحجز دور جديد في أي وقت."}</p><button class="btn" onclick="start()">احجز دور جديد</button></div>${contact()}`)}
  drawT(s,quiet);clearInterval(C.poll);C.poll=setInterval(()=>showTicket(true),8000)}
function namesBox(L){if(!L||!L.length)return"";const ST={in_service:"على الكرسي دلوقتي",checked_in:"وصل ومستني",upcoming:"مستني"};return `<div class="box" style="margin:10px 0"><b>اللي قبلك (${L.length})</b>${L.map((x,i)=>`<div class="row" style="margin-top:6px"><div><span class="m">${i+1}.</span> <b>${esc(x.name||"عميل")}</b></div><span class="tag">${ST[x.status]||""}</span></div>`).join("")}<div class="m" style="margin-top:6px">بنعرض الاسم الأول بس لخصوصية الزباين.</div></div>`}
function arrivalBox(s){if(s.barber_arrived===false)return `<div class="box" role="status" style="margin:10px 0"><b>⏳ الصنايعي لسه مجاش</b><div class="m">حجزك متسجّل وفي الطابور، والحالة بتتحدّث لوحدها أول ما يوصل</div></div>`;if(s.barber_arrived===true)return `<div class="box" role="status" style="margin:10px 0"><b>✅ الصنايعي وصل</b></div>`;return ""}
function drawT(s,quiet){C.qid=s.id;const st=s.status,steps=[["مستني دورك",1],["اتنادى عليك",s.called||st!="upcoming"],["وصلت الصالون",st=="checked_in"||st=="in_service"],["بدأت الخدمة",st=="in_service"],["خلصت — ادفع عند الكاشير",s.finished]];
  put(`<h1>دورك</h1><div class="box" style="text-align:center"><div class="m">رقمك</div><div style="font-size:64px;font-weight:800;color:var(--red);line-height:1.1">${s.ticket_no==null?"—":s.ticket_no}</div><div class="m">${PLB[s.period]||""} · ${s.day}</div>
<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:12px"><div><div class="m">بيحلق دلوقتي مع ${esc(s.barber_name||"—")}</div><b style="font-size:22px">${s.current_no?"رقم "+s.current_no:"لسه محدش"}</b></div><div><div class="m">قدامك</div><b style="font-size:22px">${s.ahead==null?"—":s.ahead+" زبون"}</b></div></div>${s.est_min==null?"":`<div class="m" style="margin-top:8px">الوقت المتوقع: حوالي ${s.est_min} دقيقة</div>`}</div>
${arrivalBox(s)}
${namesBox(s.names)}
${s.near_turn&&!s.called&&st=="upcoming"?`<div class="box" style="margin:10px 0;border-color:var(--gold2)"><b>اقترب دورك</b><div class="m">جهّز نفسك وتعالى الصالون</div></div>`:""}
<div class="row" style="margin-top:10px"><span>${esc(s.services)}</span><b>${fm(s.total)}</b></div>${s.bundle?`<div class="box" style="margin:10px 0;border-color:var(--gold2)"><b>🎁 ${esc(s.bundle.name)}</b><div style="display:flex;justify-content:space-between;padding-top:6px"><span>خصم الباقة</span><b>− ${fm(s.bundle.saving)}</b></div><div style="display:flex;justify-content:space-between;border-top:1px solid var(--line);margin-top:6px;padding-top:6px"><b>حسابك بعد الباقة</b><b>${fm(s.bundle.price)}</b></div></div>`:""}
${s.called&&st=="upcoming"?`<div class="box" style="margin:10px 0;border-color:var(--red)"><b>🔔 اتنادى عليك!</b><div class="chips" style="margin-top:8px"><button class="btn" ${s.eta=="on_way"?"disabled":""} onclick="eta('on_way')">أنا في الطريق</button><button class="btn" style="background:var(--ok)" onclick="eta('arrived')">وصلت</button></div></div>`:""}
<div style="margin:12px 0">${steps.map(x=>`<div style="padding:3px 0;${x[1]?"":"opacity:.4"}">${x[1]?"✓":"○"} ${x[0]}</div>`).join("")}</div>
${!s.called&&st=="upcoming"?`<button class="btn g" style="width:100%;margin-bottom:8px" onclick="changeB()">تغيير الحلاق</button><button class="btn g" style="width:100%" onclick="cancelT()">إلغاء الحجز</button>`:""}${contact()}`)}
async function eta(state){const L=store.get("salon_book_last");if(!L)return;const{error}=await sb.rpc("public_eta",{p_id:L.id,p_phone:L.p,p_state:state});error?toast(error.message):(toast(state=="arrived"?"تمام، الصالون عرف إنك وصلت":"تمام، مستنينك"),showTicket())}
async function changeB(){const L=store.get("salon_book_last");if(!L)return;
  const{data:t}=await sb.rpc("public_ticket",{p_id:L.id,p_phone:L.p});const s=t?.[0];if(!s)return toast("مقدرناش نحمّل الحجز");
  const{data,error}=await sb.rpc("available_barbers",{p_day:s.day,p_period:s.period});if(error)return toast(error.message);
  const O=(data||[]).filter(x=>x.full_name!==s.barber_name);if(!O.length)return toast("مفيش حلاق تاني متاح في الفترة دي");
  put(`<h1>غيّر الحلاق</h1><p class="m">هتفضل محتفظ بأسبقية تسجيلك قدر الإمكان.</p>${O.map(x=>`<button class="row" style="cursor:pointer" onclick="doChangeB('${x.id}')"><b>${esc(x.full_name)}</b><span class="m">${x.waiting} في الدور</span></button>`).join("")}<button class="btn g" style="width:100%;margin-top:10px" onclick="showTicket()">رجوع</button>`)}
async function doChangeB(id){const L=store.get("salon_book_last");if(!L||C.busy)return;C.busy=true;
  const{error}=await sb.rpc("public_change_barber",{p_id:L.id,p_phone:L.p,p_barber:id});C.busy=false;
  if(error)return toast(isNetErr(error)?"التغيير لم يتأكد — النت واقف":error.message);toast("تم تغيير الحلاق ✓");showTicket()}
async function cancelT(){if(!confirm("تلغي الحجز؟"))return;const L=store.get("salon_book_last");if(!L)return;const{error}=await sb.rpc("public_cancel",{p_id:L.id,p_phone:L.p});
  if(error)return toast(error.message);clearInterval(C.poll);store.del("salon_book_last");toast("اتلغى الحجز");start()}
init();
