/* features/customers/reminders.js — تذكير العملاء الغايبين */

const remDays=()=>Math.max(1,+C.cfg.reminder_days||30);

const remMsg=(n,d)=>`أهلاً ${n||""} 👋\nوحشتنا في ${waSalon()}! بقالك ${d} يوم مجيتش، تحب نحجزلك دور؟\nاحجز من هنا: ${location.origin}/book`;

V.rem=async()=>{const{data,error}=await sb.rpc("customers_overview");if(error)return put(`<h1>التذكير</h1><p class="m">${esc(error.message)}</p>`);
 C.REM=(data||[]).filter(x=>x.last_visit).map(x=>({...x,days:Math.floor((Date.now()-new Date(x.last_visit).getTime())/864e5)})).filter(x=>x.days>=remDays()).sort((a,b)=>b.days-a.days);
 put(`<h1>التذكير</h1><button class="btn s" onclick="go('fix')" style="margin-bottom:8px">📅 مواعيد ثابتة (حجز + تذكير تلقائي)</button><div class="box"><div class="m">العملاء اللي غايبين من</div><div class="chips" style="align-items:center"><input id="rem_d" type="number" min="1" max="365" value="${remDays()}" style="width:90px"><span class="m">يوم أو أكتر</span>${isAdm(me)?`<button class="btn s" onclick="saveRemDays()">حفظ المدة</button>`:""}</div></div>
 <input placeholder="ابحث بالاسم أو الموبايل" oninput="C.rq=this.value;$('rl').innerHTML=remRows()"><div id="rl">${remRows()}</div>`)};

function remRows(){const q=(C.rq||"").trim().toLowerCase(),L=(C.REM||[]).filter(x=>!q||(x.name||"").toLowerCase().includes(q)||String(x.phone||"").includes(q));
 return L.length?`<p class="m">${L.length} عميل</p>`+L.map(x=>`<div class="row"><div><b>${esc(x.name)}</b><div class="m">${esc(x.phone||"")} · آخر زيارة من ${x.days} يوم · ${x.visits||0} زيارة</div></div><div>${waBtn(x.phone,0,remMsg(x.name,x.days))}</div></div>`).join(""):`<p class="m empty">مفيش عملاء غايبين المدة دي.</p>`}

async function saveRemDays(){const v=Math.round(+$("rem_d").value);if(!(v>=1&&v<=365))return toast("اكتب عدد أيام من 1 لـ 365");const{error}=await sb.from("app_settings").upsert([{key:"reminder_days",value:v}]);error?toast(error.message):(C.cfg.reminder_days=v,toast("تم حفظ المدة ✓"),V.rem())}

// كارت في رئيسية الإدارة: كام عميل غايب (بيتحدّث كل ٥ دقايق مش مع كل تحديث للرئيسية)
(()=>{const q=typeof V!="undefined"&&V.home;if(!q)return;V.home=async()=>{await q();try{
  if(typeof tab!="undefined"&&tab!="home")return;if(!(isAdm(me)||can("view_customers")))return;
  const A=document.querySelector(".dash-side");if(!A||document.getElementById("remCard"))return;
  if(!C.remN||Date.now()-C.remN.t>3e5){const{data}=await sb.rpc("customers_overview");const d=remDays();C.remN={t:Date.now(),n:(data||[]).filter(x=>x.last_visit&&Math.floor((Date.now()-new Date(x.last_visit).getTime())/864e5)>=d).length,d}}
  if(!document.querySelector(".dash-side")||document.getElementById("remCard"))return;
  const c=document.createElement("div");c.id="remCard";c.innerHTML=`<h2>عملاء غابوا</h2><div class="box cc-stat" role="button" style="cursor:pointer" onclick="go('rem')"><div class="cc-l">غايبين من ${C.remN.d} يوم أو أكتر</div><div class="cc-n">${num(C.remN.n)}</div><div class="m">اضغط تبعتلهم رسالة واتساب جاهزة</div></div>`;
  A.prepend(c)}catch(e){}}})();

