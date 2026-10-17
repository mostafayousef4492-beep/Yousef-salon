/* features/customer/customer.js — تطبيق العميل: حجز، دور، حسابي */

// ================= نظام الدور + العميل (مرة واحدة) =================

const PERIODS=[["morning","الصبح","6ص–12ظ",12],["afternoon","العصر","12–5م",17],["evening","المساء","5م–12",24],["night","بعد منتصف الليل","12–6ص",6]];

const PLB={morning:"الصبح",afternoon:"العصر",evening:"المساء",night:"بعد منتصف الليل"};

const bkDays=()=>[...Array(+C.cfg.days_ahead)].map((_,i)=>{const d=new Date();d.setDate(d.getDate()+i);return{i,iso:d.toLocaleDateString("en-CA"),off:d.getDay()==C.cfg.weekly_off,l:i?d.toLocaleDateString("ar-EG",{weekday:"short",day:"numeric",month:"numeric"}):"اليوم"}});

V.book=async()=>{if(!C.cfg.booking_open)return put(`<h1>احجز دورك</h1><p class="m">الحجز متوقف حاليًا.</p>`);
const{data}=await sb.from("services").select("*").eq("active",true).order("id");C.sv=data||[];C.b=C.b||{s:[],barber:undefined,day:0,period:null};drawBk()};

function drawBk(){const b=C.b,days=bkDays();
if(b.urgent)return drawUrg();
put(`<div class="hello">أهلاً ${esc((me.full_name||"").split(" ")[0])}</div><h1>احجز دورك</h1>${C.cfg.urgent_enabled!==false?`<button class="row" style="cursor:pointer;width:100%;text-align:right;border-color:var(--red)" onclick="C.b.urgent=1;C.b.barber=undefined;drawBk()"><div><b>⚡ محتاج تدخل دلوقتي؟ (دخول مستعجل)</b><div class="m">بتدخل بعد اللي على الكرسي مباشرة بعد موافقة الصالون · الخدمة بـ ×${+C.cfg.urgent_multiplier||2}</div></div></button>`:""}<h2>الخدمات <span class="m" style="color:${b.s.length?"var(--mute)":"var(--red)"}">${b.s.length?"✓ اخترت "+b.s.length:"(لازم تختار خدمة واحدة على الأقل)"}</span></h2><div class="chips">${C.sv.map(x=>`<button class="chip ${b.s.includes(x.id)?"sel":""}" onclick="tgS(${x.id})">${esc(x.name)} · ${x.price}</button>`).join("")}</div>
<h2>اليوم</h2><div class="chips">${days.map(x=>`<button class="chip ${b.day==x.i?"sel":""}" ${x.off?"disabled":""} onclick="C.b.day=${x.i};C.b.period=null;C.b.barber=undefined;drawBk()">${x.l}</button>`).join("")}</div>
<h2>الفترة</h2><div class="chips">${PERIODS.map(p=>`<button class="chip ${b.period==p[0]?"sel":""}" ${b.day==0&&new Date().getHours()>=p[3]?"disabled":""} onclick="C.b.period='${p[0]}';C.b.barber=undefined;drawBk()">${p[1]} <span class="m">${p[2]}</span></button>`).join("")}</div><div id="bl"></div>`);if(b.period)loadBarbers()}

function tgS(id){const b=C.b;b.s=b.s.includes(id)?b.s.filter(x=>x!=id):[...b.s,id];drawBk()}

async function loadBarbers(){const b=C.b,d=bkDays()[b.day];const{data,error}=await sb.rpc("available_barbers",{p_day:d.iso,p_period:b.period});if(error)return toast(error.message);
const L=data||[],sel=v=>b.barber===v?"border-color:var(--blue);box-shadow:0 0 0 2px var(--blue) inset;":"";
const sv=C.sv.filter(x=>b.s.includes(x.id)),tot=sv.reduce((a,x)=>a+x.price,0),dur=sv.reduce((a,x)=>a+x.duration_min,0);
$("bl").innerHTML=`<h2>الحلاق</h2>`+(L.length?`<button class="row" style="cursor:pointer;${sel(null)}" onclick="C.b.barber=null;loadBarbers()"><b>أي حلاق (الأقل زحمة)</b><span class="m">أسرع دور</span></button>`+L.map(x=>`<button class="row" style="cursor:pointer;${sel(x.id)}" onclick="C.b.barber='${x.id}';loadBarbers()"><b>${esc(x.full_name)}</b><span class="m">${x.waiting} في الدور · ~${x.est_min} دقيقة</span></button>`).join("")+`<button class="btn" style="width:100%;margin-top:8px" ${b.s.length&&b.barber!==undefined?"":"disabled"} onclick="bookNow()">تأكيد وخد رقم دورك · ${fm(tot)} · ~${dur} دقيقة</button>`:`<p class="m">مفيش حلاق متاح في الفترة دي، جرّب فترة تانية.</p>`)}

const curPer=()=>{const h=new Date().getHours();return h>=6&&h<12?"morning":h>=12&&h<17?"afternoon":h>=17?"evening":"night"};
function drawUrg(){const b=C.b,m=+C.cfg.urgent_multiplier||2;
put(`<div class="hello">أهلاً ${esc((me.full_name||"").split(" ")[0])}</div><h1>⚡ دخول مستعجل</h1><div class="box" style="border-color:var(--red)"><div class="m">هتدخل بعد اللي على الكرسي مباشرة لو الصالون وافق على طلبك. حساب الخدمات بيتضرب في ${m}.</div></div><h2>الخدمات <span class="m" style="color:${b.s.length?"var(--mute)":"var(--red)"}">${b.s.length?"✓ اخترت "+b.s.length:"(لازم تختار خدمة)"}</span></h2><div class="chips">${C.sv.map(x=>`<button class="chip ${b.s.includes(x.id)?"sel":""}" onclick="tgS(${x.id})">${esc(x.name)} · ${x.price}</button>`).join("")}</div><div id="bl"></div><button class="btn g" style="width:100%;margin-top:8px" onclick="C.b.urgent=0;drawBk()">‹ رجوع للحجز العادي</button>`);loadUrgBarbers()}
async function loadUrgBarbers(){const b=C.b,m=+C.cfg.urgent_multiplier||2;const{data,error}=await sb.rpc("available_barbers",{p_day:new Date().toLocaleDateString("en-CA"),p_period:curPer()});if(error||!$("bl"))return;
const L=data||[],sel=v=>b.barber===v?"border-color:var(--blue);box-shadow:0 0 0 2px var(--blue) inset;":"",tot=C.sv.filter(x=>b.s.includes(x.id)).reduce((a,x)=>a+x.price,0)*m;
$("bl").innerHTML=`<h2>الحلاق</h2>`+(L.length?`<button class="row" style="cursor:pointer;${sel(null)}" onclick="C.b.barber=null;loadUrgBarbers()"><b>أي حلاق متاح</b></button>`+L.map(x=>`<button class="row" style="cursor:pointer;${sel(x.id)}" onclick="C.b.barber='${x.id}';loadUrgBarbers()"><b>${esc(x.full_name)}</b><span class="m">${x.waiting} في الدور</span></button>`).join("")+`<button class="btn" style="width:100%;margin-top:8px;background:var(--red);color:#fff" ${b.s.length&&b.barber!==undefined?"":"disabled"} onclick="urgNow()">⚡ اطلب دخول مستعجل · ${fm(tot)}</button>`:`<p class="m">مفيش حلاق متاح دلوقتي.</p>`)}
async function urgNow(){const b=C.b;if(!b.s.length)return toast("اختار خدمة واحدة على الأقل");const m=+C.cfg.urgent_multiplier||2,tot=C.sv.filter(x=>b.s.includes(x.id)).reduce((a,x)=>a+x.price,0)*m;
if(!confirm("تطلب دخول مستعجل؟\nالحساب هيبقى "+fm(tot)+" (الخدمات ×"+m+"). الطلب بيستنى موافقة الصالون."))return;
const{error}=await sb.rpc("request_urgent",{p_barber:b.barber||null,p_services:b.s});if(error)return toast(/Could not find the function/i.test(error.message||"")?"الخدمة دي لسه ما اتفعلتش":error.message);C.b=null;toast("اتبعت طلبك المستعجل ⚡ استنى موافقة الصالون");go("queue")}

async function bookNow(){const b=C.b,d=bkDays()[b.day];if(!b.s.length)return toast("اختار خدمة واحدة على الأقل");const{error}=await sb.rpc("book_ticket",{p_barber:b.barber||null,p_day:d.iso,p_period:b.period,p_services:b.s});
if(error)return toast(error.code=="23505"?"حد حجز قبلك، جرّب تاني":error.message);C.b=null;toast("تم الحجز ✓ ده رقم دورك");go("queue")}

V.queue=async()=>{const{data:h}=await sb.rpc("my_history");const L=h||[],act=L.find(x=>["upcoming","checked_in","in_service"].includes(x.status)),fin=L.find(x=>x.status=="done"&&!x.rated);
if(act){const{data:q}=await sb.rpc("queue_status",{p_id:act.id});if(!q?.[0])return;const qs=q[0];try{const{data:v2,error:e2}=await sb.rpc("queue_status_v2",{p_id:act.id});if(!e2&&v2){qs.ahead=v2.ahead;qs.est_min=v2.est_wait_min;qs.current_no=v2.current_no;qs.ticket_no=v2.ticket_no;qs.ticket_code=v2.ticket_code;qs.near_turn=v2.near_turn}}catch(e){}try{const{data:tq}=await sb.from("ticket_transfers").select("id").eq("appointment_id",act.id).eq("status","pending").maybeSingle();qs.trq=tq?tq.id:null}catch(e){}try{const{data:ug}=await sb.rpc("my_urgent");qs.urg=ug}catch(e){}startNotif();drawQ(qs);clearInterval(C.poll);C.poll=setInterval(()=>tab=="queue"&&($("app").classList.add("still"),V.queue()),8000);return}
if(fin)return rateView2(fin.id);
const ns=L[0]&&L[0].status=="no_show"&&L[0].day==new Date().toLocaleDateString("en-CA");
put(`<h1>دوري</h1><div class="box" style="text-align:center">${ns?`<p class="m" style="color:var(--red)">اتلغى دورك لأنك ما حضرتش في الميعاد.</p>`:""}<p class="m">مفيش دور نشط دلوقتي.</p><button class="btn" onclick="go('book')">احجز دورك</button></div>`)};

async function eta(st){const{error}=await sb.rpc("ticket_eta",{p_id:C.qid,p_state:st});error?toast(error.message):(toast(st=="arrived"?"تمام، الصالون عرف إنك وصلت":"تمام، مستنينك"),V.queue())}

async function cancelT(){if(!confirm("تلغي الحجز؟"))return;const{error}=await sb.rpc("cancel_my_appt",{p_id:C.qid});error?toast(error.message):go("book")}

function rateView2(id){C.R2={id,b:0,s:0,p:0,tg:[],note:""};drawR2()}

const stars=(k,v)=>`<div class="stars" style="text-align:center">${[1,2,3,4,5].map(i=>`<button class="${v>=i?"on":""}" aria-label="${i}" onclick="C.R2.${k}=${i};drawR2()">★</button>`).join("")}</div>`;

function drawR2(){const R=C.R2,tags=["نظافة المكان","دقة الدور","مهارة الحلاق","سعر مناسب","تعامل راقي"];
put(`<h1 style="text-align:center">خلصت؟ قيّم تجربتك</h1><p class="m" style="text-align:center">هتاخد ${C.cfg.review_bonus} نقطة هدية على تقييمك 🎁</p><h2>الحلاق</h2>${stars("b",R.b)}<h2>الخدمة</h2>${stars("s",R.s)}<h2>المكان</h2>${stars("p",R.p)}<div class="chips" style="margin-top:8px">${tags.map(t=>`<button class="chip ${R.tg.includes(t)?"sel":""}" onclick="C.R2.tg=C.R2.tg.includes('${t}')?C.R2.tg.filter(x=>x!='${t}'):[...C.R2.tg,'${t}'];drawR2()">${t}</button>`).join("")}</div><input placeholder="ملاحظات (اختياري)" value="${esc(R.note)}" oninput="C.R2.note=this.value"><button class="btn" style="width:100%" ${R.b&&R.s&&R.p?"":"disabled"} onclick="sendR2()">إرسال</button>`)}

async function sendR2(){const R=C.R2;const{error}=await sb.rpc("rate_ticket",{p_appt:R.id,p_barber:R.b,p_service:R.s,p_place:R.p,p_tags:R.tg,p_note:R.note});error?toast(error.message):(toast("شكرًا! اتضافت نقاط لحسابك 🎁"),go("loy"))}

V.mine=async()=>{const{data:h}=await sb.rpc("my_history");const L=h||[],dn=L.filter(x=>x.status=="done"),paid=dn.reduce((a,x)=>a+(+x.paid||0),0);
put(`<h1>حجوزاتي</h1><div style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px"><div class="box" style="text-align:center"><div class="m">زياراتك</div><b>${dn.length}</b></div><div class="box" style="text-align:center"><div class="m">آخر زيارة</div><b style="font-size:13px">${dn[0]?.day||"—"}</b></div><div class="box" style="text-align:center"><div class="m">إجمالي دفعك</div><b style="font-size:14px">${fm(paid)}</b></div></div><h2>السجل</h2>`+(L.length?L.map(x=>`<div class="row"><div><b>${x.day||""}</b> · ${PLB[x.period]||""} · دور ${x.ticket_no||"-"}<div class="m">${esc(x.services)} مع ${esc(x.barber_name||"-")}</div></div><div style="text-align:left"><span class="tag">${ST[x.status]}</span>${x.paid!=null?`<div><b>${fm(x.paid)}</b></div>`:""}${x.points?`<div class="m">+${x.points} نقطة</div>`:""}</div></div>`).join(""):`<p class="m">لسه معندكش حجوزات.</p>`))};

const RSN={purchase:"شراء",welcome:"هدية التسجيل",review:"تقييم",referral:"دعوة صديق",birthday:"هدية عيد ميلاد",visit:"مكافأة زيارات",redeem:"استبدال مكافأة",adjust:"تعديل من الإدارة"};

async function redeem(id){if(!confirm("تستبدل النقاط دي؟"))return;const{data,error}=await sb.rpc("redeem_reward",{p_reward:id});error?toast(error.message):(toast("كود الكوبون: "+data),V.loy())}

V.menu=async()=>{const{data}=await sb.from("services").select("*").eq("active",true).order("category").order("price");const g={};(data||[]).forEach(x=>(g[x.category||"خدمات"]=g[x.category||"خدمات"]||[]).push(x));
put(`<h1>منيو الخدمات</h1>`+Object.entries(g).map(([k,a])=>`<h2>${esc(k)}</h2>`+a.map(x=>`<div class="row"><div><b>${esc(x.name)}</b><div class="m">${esc(x.description||"")} ${x.duration_min} دقيقة</div></div><div style="text-align:left"><b style="color:var(--brass)">${fm(x.price)}</b><br><button class="btn s g" onclick="C.b=C.b||{s:[],barber:undefined,day:0,period:null};C.b.s=[${x.id}];go('book')">احجز</button></div></div>`).join("")).join(""))};

function drawQ(s){C.qid=s.id;C.qcur=s;const st=s.status,steps=[["مستني دورك",1],["اتنادى عليك",s.called||st!="upcoming"],["وصلت الصالون",st=="checked_in"||st=="in_service"],["بدأت الخدمة",st=="in_service"],["خلصت — ادفع عند الكاشير",s.finished]];
let cur=-1;steps.forEach((x,i)=>{if(x[1])cur=i});
put(`<div class="hello">دورك مع ${esc(s.barber_name)}</div><h1>دوري</h1>
<div class="pass"><div class="pass-top"><div class="m">رقم دورك</div><div class="pass-no" dir="ltr">${s.ticket_code||(s.ticket_no==null?"—":num(s.ticket_no))}</div><div class="m">${PLB[s.period]} · ${s.day}</div></div><div class="perf"></div>
<div class="pass-bot"><div><div class="m">بيحلق دلوقتي</div><b class="big2">${s.current_no?"#"+num(s.current_no):"—"}</b></div><div><div class="m">قدامك</div><b class="big2">${s.ahead==null?"—":num(s.ahead)}</b></div><div><div class="m">الوقت المتوقع</div><b class="big2">${s.est_min==null?"—":num(s.est_min)+"<small> دقيقة</small>"}</b></div></div></div>
<div class="row" style="margin-top:14px"><span>${esc(s.services)}</span><b style="color:var(--gold2);font-family:var(--display);font-size:20px">${fm(s.total)}</b></div>
${s.near_turn&&!s.called&&st=="upcoming"?`<div class="nearbox" role="status"><div><b>اقترب دورك</b><div class="m">جهّز نفسك وتعالى الصالون</div></div></div>`:""}
${s.called&&st=="upcoming"?`<div class="callbox"><b>اتنادى عليك</b><div class="m" style="margin:2px 0 10px">قولنا إنت فين</div><div class="chips" style="margin:0"><button class="btn" ${s.eta=="on_way"?"disabled":""} onclick="eta('on_way')">أنا في الطريق</button><button class="btn" style="background:linear-gradient(180deg,#52C08C,#2E8B5E);color:#fff" onclick="eta('arrived')">وصلت</button></div></div>`:""}
<ul class="tl">${steps.map((x,i)=>`<li class="${x[1]?(i==cur?"now":"done"):""}">${x[0]}</li>`).join("")}</ul>
${!s.called&&st=="upcoming"?`<button class="btn g" style="width:100%" onclick="cancelT()">إلغاء الحجز</button>`:""}
${st=="upcoming"||st=="checked_in"?(s.trq?`<div class="box" style="margin-top:8px"><div class="m">طلب النقل لحلاق تاني مستني موافقة</div><button class="btn s g" onclick="trCancel(${s.trq})">إلغاء الطلب</button></div>`:`<button class="btn g" style="width:100%;margin-top:8px" onclick="trForm()">أطلب حلاق تاني</button><div id="trf"></div>`):""}`)}

// طلب نقل لحلاق تاني (بيحتاج موافقة الحلاق أو المدير؛ التذكرة بتفضل مكانها لحد الموافقة)
async function trForm(){const s=C.qcur,e=$("trf");if(!s||!e)return;if(e.innerHTML)return e.innerHTML="";const{data}=await sb.rpc("available_barbers",{p_day:s.day,p_period:s.period});const L=(data||[]).filter(b=>b.full_name!=s.barber_name);e.innerHTML=L.length?`<div class="box" style="margin-top:8px"><div class="m">اختار الحلاق اللي عايز تنتقل له</div><div class="chips">${L.map(b=>`<button class="chip" onclick="trSend('${b.id}')">${esc(b.full_name)} · قدامه ${num(b.waiting)}</button>`).join("")}</div></div>`:`<p class="m">مفيش حلاق تاني متاح دلوقتي.</p>`}

async function trSend(b){const{error}=await sb.rpc("request_transfer",{p_id:C.qid,p_to:b,p_reason:null});error?toast(error.message):(toast("اتبعت الطلب، مستني الموافقة"),V.queue())}

async function trCancel(id){const{error}=await sb.rpc("cancel_transfer_request",{p_req:id});error?toast(error.message):V.queue()}


V.loy=async()=>{const{data:{user}}=await sb.auth.getUser();const{data:c}=await sb.from("customers").select("id,name,phone,points,lifetime_points,visits").eq("user_id",user.id).single();
const[{data:tr},{data:rw},{data:vo},{data:lg}]=await Promise.all([sb.rpc("loyalty_tier",{p_life:c.lifetime_points}),sb.from("loyalty_rewards").select("*").eq("active",true).order("cost"),sb.from("loyalty_redemptions").select("code,loyalty_rewards(name)").eq("customer_id",c.id).eq("status","active"),sb.from("loyalty_ledger").select("*").eq("customer_id",c.id).order("created_at",{ascending:false}).limit(15)]);
const t=tr[0],pct=t.next_at?Math.min(100,c.lifetime_points/t.next_at*100):100,g=C.cfg;
put(`<div class="vip"><div class="vip-top"><span class="vip-brand">${esc(g.salon_name)}</span><span class="vip-tier">${t.name}${t.mult>1?" · ×"+t.mult:""}</span></div><div class="vip-pts">${num(c.points)}<small>نقطة</small></div><div class="vip-bar"><i style="width:${pct}%"></i></div><div class="vip-foot"><span>${t.next_at?"باقي "+num(t.next_at-c.lifetime_points)+" نقطة للمستوى الجاي":"وصلت لأعلى مستوى"}</span><span>${esc(c.name)} · ${esc((c.phone||"").slice(-4))}</span></div></div>
${vo?.length?`<h2>كوبوناتك — قدّم الكود للكاشير</h2>`+vo.map(v=>`<div class="row"><span>${esc(v.loyalty_rewards.name)}</span><b style="font-family:var(--display);font-size:24px;letter-spacing:3px;color:var(--gold2)">${v.code}</b></div>`).join(""):""}
<h2>استبدل نقاطك</h2>`+(rw||[]).map(x=>`<div class="row"><div><b>${esc(x.name)}</b><div class="m">${x.cost} نقطة</div></div><button class="btn s" ${c.points<x.cost?"disabled":""} onclick="redeem(${x.id})">استبدل</button></div>`).join("")+`<div id="refbox"></div><h2>إزاي تكسب نقاط؟</h2><div class="box m" style="line-height:2">كل ${g.points_per_currency} ${g.currency} = نقطة (× مستواك)<br>${g.review_bonus} نقطة على كل تقييم<br>${g.visit_bonus_points} نقطة كل ${g.visit_bonus_every} زيارات<br>${g.welcome_bonus} نقطة هدية التسجيل<br>ادعي صاحبك: انت وهو تاخدوا نقاط لما يدفع أول فاتورة (لو البرنامج شغّال)</div><h2>آخر الحركات</h2>`+((lg||[]).length?lg.map(l=>`<div class="row"><div>${RSN[l.reason]||l.reason}<div class="m">${new Date(l.created_at).toLocaleDateString("ar-EG")}</div></div><b style="color:${l.points>0?"var(--ok)":"var(--red)"}">${l.points>0?"+":""}${l.points}</b></div>`).join(""):`<p class="m">لسه مفيش حركات.</p>`));drawRef()};

async function startNotif(){if(C.nch||APP_MODE!="customer")return;try{const{data:{user}}=await sb.auth.getUser();if(!user)return;C.nch=sb.channel("cn-"+user.id).on("postgres_changes",{event:"INSERT",schema:"public",table:"customer_notifications"},p=>{const n=p.new||{};toast((n.title||"")+(n.body?" — "+n.body:""));try{if(window.Notification&&Notification.permission=="granted")new Notification(n.title||"",{body:n.body||""})}catch(e){}tab=="queue"&&V.queue()}).subscribe();if(window.Notification&&Notification.permission=="default")Notification.requestPermission()}catch(e){}}

// ===== حسابي (العميل): النقاط + بياناتي + المنيو + خروج في مكان واحد =====

const loy0=V.loy;

V.loy=async()=>{await loy0();if(tab!="loy")return;const{data:{user}}=await sb.auth.getUser(),{data:c}=await sb.from("customers").select("name,phone,visits").eq("user_id",user.id).maybeSingle();if(!c||tab!="loy")return;const pf=await myProfile(true);if(tab!="loy")return;
$("app").insertAdjacentHTML("afterbegin",myPhotoBox(pf));$("app").insertAdjacentHTML("beforeend",`<h2>بياناتي</h2><div class="box"><b>${esc(c.name)}</b><div class="m" dir="ltr" style="text-align:right">${esc(c.phone||"")}</div><div class="m">${c.visits||0} زيارة</div></div><div class="chips" style="margin-top:10px"><button class="btn g" onclick="go('menu')">منيو الخدمات</button><button class="btn s g" onclick="go('out')">تسجيل خروج</button></div>`)};

function okFlash(t,m){const d=document.createElement("div");d.className="okf";d.setAttribute("role","status");d.innerHTML=`<div class="okc"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></div><b>${esc(t)}</b><div class="m">${esc(m||"")}</div>`;document.body.appendChild(d);setTimeout(()=>d.classList.add("out"),1100);setTimeout(()=>d.remove(),1400)}

// كود العميل السري: بيظهر بضغطة زرار بس (مش مكشوف على الشاشة)

async function drawRef(){const o=$("refbox");if(!o)return;const{data:r,error}=await sb.rpc("my_referral");if(error||!r||r.enabled===false)return;
const msg="تعالى جرّب صالون أبو يوسف! سجّل من هنا "+location.origin+" واكتب كود الدعوة "+r.code+" — واحنا الاتنين هنكسب نقاط 🎁";
window._refMsg=msg;
o.innerHTML=`<h2>ادعي صاحبك واكسبوا نقاط 🎁</h2><div class="box"><div class="m">كودك — لما صاحبك يدفع أول فاتورة، هو ياخد ${r.points} نقطة وانت تاخد ${r.referrer_points}</div><div class="code-big" dir="ltr">${esc(r.code)}</div><div class="chips"><a class="btn s" target="_blank" rel="noopener" href="https://wa.me/?text=${encodeURIComponent(msg)}">ابعت على واتساب</a><button class="btn s g" onclick="copyRef()">نسخ الدعوة</button></div><div class="m" style="margin-top:8px">دعيت ${r.invited} · اتكافأوا ${r.rewarded} · كسبت ${r.earned} نقطة</div></div>`+(r.can_apply?`<div class="box" style="margin-top:8px"><div class="m">جاي عن طريق صاحبك؟ اكتب كود الدعوة أو رقم موبايله</div><input id="refin" placeholder="كود أو رقم الموبايل" autocomplete="off"><button class="btn s" onclick="applyRef()">تأكيد</button></div>`:r.referrer?`<div class="m" style="margin-top:8px">جيت عن طريق: ${esc(r.referrer)}</div>`:"")}
function copyRef(){try{navigator.clipboard.writeText(window._refMsg).then(()=>toast("اتنسخت ✓"),()=>toast("مقدرتش أنسخ"))}catch(e){toast("مقدرتش أنسخ")}}
async function applyRef(){const v=($("refin")?.value||"").trim();if(!v)return toast("اكتب الكود أو الرقم");const{data,error}=await sb.rpc("apply_referral",{p_key:v});if(error)return toast(error.message);toast("تم ✓ هتاخد نقاطك بعد أول فاتورة (دعوة "+data+")");drawRef()}


// بانر حالة الطلب المستعجل فوق صفحة الدور
const drawQ0=drawQ;drawQ=function(qs){drawQ0(qs);const u=qs&&qs.urg;if(!u||!u.state)return;const a=$("app");if(!a)return;
a.insertAdjacentHTML("afterbegin",`<div class="box" style="border-color:var(--red);margin-bottom:10px"><b>⚡ ${u.state=="requested"?"طلبك المستعجل في انتظار موافقة الصالون":u.state=="approved"?"اتوافق على دخولك المستعجل — هتدخل بعد اللي على الكرسي مباشرة":"الصالون ماقدرش يوافق على المستعجل، دورك العادي محفوظ"}</b>${u.state=="approved"?`<div class="m">حساب الخدمات ×${+u.multiplier||2}</div>`:""}</div>`)};
