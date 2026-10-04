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
const bkDays=()=>[...Array(Math.max(+C.cfg.days_ahead||5,1))].map((_,i)=>{const d=new Date();d.setDate(d.getDate()+i);return{i,iso:d.toLocaleDateString("en-CA"),off:d.getDay()==C.cfg.weekly_off,l:i?d.toLocaleDateString("ar-EG",{weekday:"short",day:"numeric",month:"numeric"}):"اليوم"}});
const contact=()=>`<div class="foot m">${C.cfg.phone?`للاستفسار: <a href="tel:${esc(C.cfg.phone)}">${esc(C.cfg.phone)}</a>`:""}${C.cfg.address?`<div>${esc(C.cfg.address)}</div>`:""}<div style="margin-top:8px"><a href="/">تطبيق الصالون (النقاط والعروض)</a></div></div>`;

async function init(){
  const{data}=await sb.from("app_settings").select("*");(data||[]).forEach(r=>C.cfg[r.key]=r.value);
  document.title="احجز دورك - "+C.cfg.salon_name;$("bn").textContent=C.cfg.salon_name;
  const i=store.get("salon_book_info");if(i){C.f.n=i.n||"";C.f.p=i.p||""}
  if(store.get("salon_book_last"))return showTicket();
  start()}
async function start(){
  if(C.cfg.booking_open===false||C.cfg.booking_open==="false")return put(`<h1>احجز دورك</h1><div class="box"><p class="m">الحجز أونلاين متوقف حاليًا.</p></div>${contact()}`);
  const{data,error}=await sb.from("services").select("*").eq("active",true).order("id");
  if(error)return put(`<h1>احجز دورك</h1><p class="m">مقدرناش نحمّل الخدمات، جرّب تاني بعد شوية.</p>`);
  C.sv=data||[];C.b={s:[],day:0,period:null,barber:undefined};draw()}

function draw(){const b=C.b,days=bkDays();
  put(`<h1>احجز دورك</h1><p class="m" style="margin:0 0 4px">من غير تسجيل ولا تحميل تطبيق — اختار وخد رقم دورك.</p>
<h2>الخدمات</h2><div class="chips">${C.sv.map(x=>`<button class="chip ${b.s.includes(x.id)?"sel":""}" onclick="tgS(${x.id})">${esc(x.name)} · ${x.price}</button>`).join("")}</div>
<h2>اليوم</h2><div class="chips">${days.map(x=>`<button class="chip ${b.day==x.i?"sel":""}" ${x.off?"disabled":""} onclick="C.b.day=${x.i};C.b.period=null;C.b.barber=undefined;draw()">${x.l}</button>`).join("")}</div>
<h2>الفترة</h2><div class="chips">${PERIODS.map(p=>`<button class="chip ${b.period==p[0]?"sel":""}" ${b.day==0&&new Date().getHours()>=p[3]?"disabled":""} onclick="C.b.period='${p[0]}';C.b.barber=undefined;draw()">${p[1]} <span class="m">${p[2]}</span></button>`).join("")}</div>
<div id="bl"></div>
<h2>بياناتك</h2><div class="box"><input id="fn" placeholder="اسمك" value="${esc(C.f.n)}" autocomplete="name" oninput="C.f.n=this.value"><input id="fp" type="tel" inputmode="numeric" placeholder="رقم موبايلك (01xxxxxxxxx)" value="${esc(C.f.p)}" autocomplete="tel" oninput="C.f.p=this.value">
<button class="btn" id="cbtn" style="width:100%" onclick="bookNow()" disabled>تأكيد وخد رقم دورك</button></div>${contact()}`);
  if(b.period)loadBarbers();upd()}
function tgS(id){const b=C.b;b.s=b.s.includes(id)?b.s.filter(x=>x!=id):[...b.s,id];draw()}
function upd(){const b=C.b,sv=C.sv.filter(x=>b.s.includes(x.id)),tot=sv.reduce((a,x)=>a+x.price,0),dur=sv.reduce((a,x)=>a+(x.duration_min||0),0),btn=$("cbtn");if(!btn)return;
  btn.disabled=!(b.s.length&&b.period&&b.barber!==undefined);
  btn.textContent=b.s.length?`تأكيد وخد رقم دورك · ${fm(tot)}${dur?" · ~"+dur+" دقيقة":""}`:"تأكيد وخد رقم دورك"}
async function loadBarbers(){const b=C.b,d=bkDays()[b.day];
  const{data,error}=await sb.rpc("available_barbers",{p_day:d.iso,p_period:b.period});if(error)return toast(error.message);
  const L=data||[],sel=v=>b.barber===v?"border-color:var(--blue);box-shadow:0 0 0 2px var(--blue) inset;":"";
  if(b.barber&&!L.some(x=>x.id==b.barber))b.barber=undefined;
  $("bl").innerHTML=`<h2>الحلاق</h2>`+(L.length?`<button class="row" style="cursor:pointer;${sel(null)}" onclick="C.b.barber=null;loadBarbers();upd()"><b>أي حلاق (الأقل زحمة)</b><span class="m">أسرع دور</span></button>`+L.map(x=>`<button class="row" style="cursor:pointer;${sel(x.id)}" onclick="C.b.barber='${x.id}';loadBarbers();upd()"><b>${esc(x.full_name)}</b><span class="m">${x.waiting} في الدور · ~${x.est_min} دقيقة</span></button>`).join(""):`<p class="m">مفيش حلاق متاح في الفترة دي، جرّب فترة تانية.</p>`);upd()}

async function bookNow(){const b=C.b,d=bkDays()[b.day],n=(C.f.n||"").trim(),ph=dig(C.f.p);
  if(n.length<2)return toast("اكتب اسمك");if(!/^01\d{9}$/.test(ph))return toast("الموبايل لازم 11 رقم ويبدأ بـ 01");
  const btn=$("cbtn");btn.disabled=true;
  const{data,error}=await sb.rpc("public_book",{p_name:n,p_phone:ph,p_barber:b.barber||null,p_day:d.iso,p_period:b.period,p_services:b.s});
  if(error){btn.disabled=false;return toast(error.code=="23505"?"حد حجز قبلك، جرّب تاني":error.message)}
  C.f.p=ph;store.set("salon_book_info",{n,p:ph});store.set("salon_book_last",{id:data[0].t_id,p:ph});toast("تم الحجز ✓ ده رقم دورك");showTicket()}

// ===== تذكرة الدور (بتتحدّث لوحدها كل 8 ثواني) =====
async function showTicket(quiet){const L=store.get("salon_book_last");if(!L)return start();
  const{data,error}=await sb.rpc("public_ticket",{p_id:L.id,p_phone:L.p});const s=data?.[0];
  if(!error&&s){try{const{data:v2,error:e2}=await sb.rpc("public_queue_status_v2",{p_id:L.id,p_phone:L.p});if(!e2&&v2){s.ahead=v2.ahead;s.est_min=v2.est_wait_min;s.current_no=v2.current_no;s.ticket_no=v2.ticket_no;s.near_turn=v2.near_turn}}catch(e){}}
  if(error||!s){clearInterval(C.poll);store.del("salon_book_last");return start()}
  if(s.status=="done"||s.status=="cancelled"||s.status=="no_show"){clearInterval(C.poll);store.del("salon_book_last");
    return put(`<h1>${s.status=="done"?"شكرًا لزيارتك 🙏":s.status=="no_show"?"اتلغى دورك":"اتلغى الحجز"}</h1><div class="box" style="text-align:center"><p class="m">${s.status=="done"?"نورتنا — نتمنى نشوفك تاني قريب.":s.status=="no_show"?"اتلغى دورك لأنك ما حضرتش في الميعاد. تقدر تحجز دور جديد.":"تقدر تحجز دور جديد في أي وقت."}</p><button class="btn" onclick="start()">احجز دور جديد</button></div>${contact()}`)}
  drawT(s,quiet);clearInterval(C.poll);C.poll=setInterval(()=>showTicket(true),8000)}
function drawT(s,quiet){C.qid=s.id;const st=s.status,steps=[["مستني دورك",1],["اتنادى عليك",s.called||st!="upcoming"],["وصلت الصالون",st=="checked_in"||st=="in_service"],["بدأت الخدمة",st=="in_service"],["خلصت — ادفع عند الكاشير",s.finished]];
  put(`<h1>دورك</h1><div class="box" style="text-align:center"><div class="m">رقمك</div><div style="font-size:64px;font-weight:800;color:var(--red);line-height:1.1">${s.ticket_no==null?"—":s.ticket_no}</div><div class="m">${PLB[s.period]||""} · ${s.day}</div>
<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:12px"><div><div class="m">بيحلق دلوقتي مع ${esc(s.barber_name||"—")}</div><b style="font-size:22px">${s.current_no?"رقم "+s.current_no:"لسه محدش"}</b></div><div><div class="m">قدامك</div><b style="font-size:22px">${s.ahead==null?"—":s.ahead+" زبون"}</b></div></div>${s.est_min==null?"":`<div class="m" style="margin-top:8px">الوقت المتوقع: حوالي ${s.est_min} دقيقة</div>`}</div>
${s.near_turn&&!s.called&&st=="upcoming"?`<div class="box" style="margin:10px 0;border-color:var(--gold2)"><b>اقترب دورك</b><div class="m">جهّز نفسك وتعالى الصالون</div></div>`:""}
<div class="row" style="margin-top:10px"><span>${esc(s.services)}</span><b>${fm(s.total)}</b></div>
${s.called&&st=="upcoming"?`<div class="box" style="margin:10px 0;border-color:var(--red)"><b>🔔 اتنادى عليك!</b><div class="chips" style="margin-top:8px"><button class="btn" ${s.eta=="on_way"?"disabled":""} onclick="eta('on_way')">أنا في الطريق</button><button class="btn" style="background:var(--ok)" onclick="eta('arrived')">وصلت</button></div></div>`:""}
<div style="margin:12px 0">${steps.map(x=>`<div style="padding:3px 0;${x[1]?"":"opacity:.4"}">${x[1]?"✓":"○"} ${x[0]}</div>`).join("")}</div>
${!s.called&&st=="upcoming"?`<button class="btn g" style="width:100%" onclick="cancelT()">إلغاء الحجز</button>`:""}${contact()}`)}
async function eta(state){const L=store.get("salon_book_last");if(!L)return;const{error}=await sb.rpc("public_eta",{p_id:L.id,p_phone:L.p,p_state:state});error?toast(error.message):(toast(state=="arrived"?"تمام، الصالون عرف إنك وصلت":"تمام، مستنينك"),showTicket())}
async function cancelT(){if(!confirm("تلغي الحجز؟"))return;const L=store.get("salon_book_last");if(!L)return;const{error}=await sb.rpc("public_cancel",{p_id:L.id,p_phone:L.p});
  if(error)return toast(error.message);clearInterval(C.poll);store.del("salon_book_last");toast("اتلغى الحجز");start()}
init();
