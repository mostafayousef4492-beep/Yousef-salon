/* features/floor/appts.js — الحجوزات والطابور */

// ================= موظفين: الدور والحضور بالموقع =================

V.appts=async()=>{const t=new Date().toLocaleDateString("en-CA");
if(+C.cfg.no_show_after_minutes>0){try{await sb.rpc("run_no_show_sweep")}catch(e){}}
let q=sb.from("appointments").select("id,day,period,ticket_no,status,called_at,eta,finished_at,customer_id,barber_id,customers(name),profiles(full_name),appointment_services(service_id,services(name))");q=dfOn("ap")?dfQ(q,"day","ap"):q.gte("day",t).not("status","in","(cancelled,done)");const{data}=await q.order("day").order("ticket_no");
C.A=(data||[]).filter(a=>a.status!="no_show");put(`<h1>الدور</h1><button class="btn s" onclick="admForm()">+ حجز إداري</button><div id="adm"></div>${dfBar("ap","V.appts()")}`+(C.A.length?C.A.map(a=>`<div class="row"><div><b>#${a.ticket_no}</b> · ${esc(a.customers?.name)}<div class="m">${a.day} · ${PLB[a.period]} · ${a.appointment_services.map(x=>esc(x.services.name)).join(" + ")} · ${esc(a.profiles?.full_name||"-")}</div></div><div style="text-align:left"><span class="tag">${a.finished_at?"خلص":a.called_at&&a.status=="upcoming"?"مستدعى"+(a.eta=="on_way"?" (في الطريق)":""):ST[a.status]}</span><br>${a.status=="upcoming"&&!a.called_at?`<button class="btn s" onclick="tk('call_ticket',${a.id})">استدعاء</button> `:""}${a.status=="upcoming"||a.status=="checked_in"?`<button class="btn s g" onclick="setS(${a.id},'in_service')">ابدأ</button> `:""}${a.status=="in_service"?`<button class="btn s" onclick="payAppt(${a.id})">دفع</button> `:""}${(a.status=="upcoming"||a.status=="checked_in")&&a.called_at?`<button class="btn s g" onclick="noShow(${a.id})">لم يحضر</button> `:""}${a.status!="in_service"?`<button class="btn s g" onclick="setS(${a.id},'cancelled')">إلغاء</button>`:""}${me.role=="owner"?` <button class="btn s g" style="color:var(--red)" onclick="delAppt('${a.id}')">حذف</button>`:""}</div></div>`).join(""):`<p class="m">${dfOn("ap")?"مفيش حجوزات في الفترة دي.":"مفيش دور محجوز."}</p>`));clearInterval(C.poll);C.poll=setInterval(()=>{if(tab=="appts"&&!($("adm")&&$("adm").innerHTML)){$("app").classList.add("still");V.appts()}},30000)};

// ===== الرئيسية: مركز قيادة الصالون (بيانات حقيقية، من غير أي شيء شكلي) =====

function qa(t,f,id){go(t);let n=0;const w=setInterval(()=>{if($(id)||++n>40){clearInterval(w);if($(id))window[f]()}},100)}

async function homeCall(id){const{error}=await sb.rpc("call_ticket",{p_id:id});error?toast(error.message):(toast("تم الاستدعاء ✓"),go("home"))}

async function tk(f,id){const{error}=await sb.rpc(f,{p_id:id});error?toast(error.message):(tab=="appts"?go("appts"):C.reload())}

async function loadV(){const P=C.P,keep=P.rid;P.rid="";P.vs=[];if(P.cid&&C.cfg.ff_loyalty!==false){const{data}=await sb.from("loyalty_redemptions").select("id,code,loyalty_rewards(name)").eq("customer_id",P.cid).eq("status","active");P.vs=data||[];if(keep&&P.vs.some(v=>String(v.id)==String(keep)))P.rid=String(keep)}drawPos()}

const getPos=()=>new Promise(r=>navigator.geolocation?navigator.geolocation.getCurrentPosition(p=>r({lat:p.coords.latitude,lng:p.coords.longitude}),()=>r({}),{enableHighAccuracy:true,timeout:12000,maximumAge:0}):r({}));

// ---- الحجز الإداري + لم يحضر ----

async function admForm(){const e=$("adm");if(e.innerHTML)return e.innerHTML="";const[{data:sv},{data:br}]=await Promise.all([sb.from("services").select("id,name,price").eq("active",true).order("id"),sb.from("profiles").select("id,full_name").eq("role","barber").order("full_name")]);C.ad={s:[],sv:sv||[],br:br||[]};drawAdm()}

function drawAdm(){const A=C.ad,e=$("adm");if(!e)return;const nm=$("ad_n")?$("ad_n").value:"",ph=$("ad_p")?$("ad_p").value:"",day=$("ad_d")?$("ad_d").value:ymd(new Date()),pe=$("ad_pe")?$("ad_pe").value:"evening",bb=$("ad_b")?$("ad_b").value:"";
  e.innerHTML=`<div class="box" style="margin:10px 0"><div class="m">حجز إداري (بيدخل الدور زي أي حجز)</div><input id="ad_n" placeholder="اسم العميل" value="${esc(nm)}"><input id="ad_p" type="tel" inputmode="numeric" placeholder="موبايل العميل" value="${esc(ph)}"><div class="chips">${A.sv.map(x=>`<button class="chip ${A.s.includes(x.id)?"sel":""}" onclick="admTg(${x.id})">${esc(x.name)} · ${x.price}</button>`).join("")}</div><select id="ad_b"><option value="">أي حلاق (الأقل زحمة)</option>${A.br.map(x=>`<option value="${x.id}" ${bb==x.id?"selected":""}>${esc(x.full_name)}</option>`).join("")}</select><input id="ad_d" type="date" value="${day}" min="${ymd(new Date())}"><select id="ad_pe">${Object.entries(PLB).map(([k,v])=>`<option value="${k}" ${pe==k?"selected":""}>${v}</option>`).join("")}</select><div class="chips"><button class="btn" onclick="admSave()">حجز</button><button class="btn g" onclick="$('adm').innerHTML=''">إلغاء</button></div></div>`}

function admTg(id){const A=C.ad;A.s=A.s.includes(id)?A.s.filter(x=>x!=id):[...A.s,id];drawAdm()}

async function admSave(){const A=C.ad,n=$("ad_n").value.trim(),ph=($("ad_p").value||"").replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/\D/g,"");if(n.length<2)return toast("اكتب اسم العميل");if(!/^01\d{9}$/.test(ph))return toast("الموبايل لازم 11 رقم ويبدأ بـ 01");if(!A.s.length)return toast("اختار خدمة");
  const{error}=await sb.rpc("admin_book_ticket",{p_name:n,p_phone:ph,p_barber:$("ad_b").value||null,p_day:$("ad_d").value,p_period:$("ad_pe").value,p_services:A.s});error?toast(error.message):(toast("تم الحجز ✓"),go("appts"))}

async function noShow(id){if(!confirm("تسجّل العميل ده \"لم يحضر\"؟"))return;const{error}=await sb.from("appointments").update({status:"no_show"}).eq("id",id);error?toast(/enum|no_show/i.test(error.message)?"حالة no_show مش مضافة في قاعدة البيانات — شغّل: alter type appt_status add value if not exists 'no_show';":error.message):go("appts")}

async function copyBook(){const u=location.origin+"/book";try{await navigator.clipboard.writeText(u);toast("تم نسخ الرابط ✓")}catch(e){prompt("انسخ الرابط:",u)}}
