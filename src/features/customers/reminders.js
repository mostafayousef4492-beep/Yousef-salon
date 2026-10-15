/* features/customers/reminders.js — تذكير العملاء الغايبين */

const remDays=()=>Math.max(1,+C.cfg.reminder_days||30);

const remMsg=(n,d)=>`أهلاً ${n||""} 👋\nوحشتنا في ${waSalon()}! بقالك ${d} يوم مجيتش، تحب نحجزلك دور؟\nاحجز من هنا: ${location.origin}/book`;

V.rem=async()=>{const{data,error}=await sb.rpc("customers_overview");if(error)return put(`<h1>التذكير</h1><p class="m">${esc(error.message)}</p>`);
 C.REM=(data||[]).filter(x=>x.last_visit).map(x=>({...x,days:Math.floor((Date.now()-new Date(x.last_visit).getTime())/864e5)})).filter(x=>x.days>=remDays()).sort((a,b)=>b.days-a.days);
 put(`<h1>التذكير</h1><div class="box"><div class="m">العملاء اللي غايبين من</div><div class="chips" style="align-items:center"><input id="rem_d" type="number" min="1" max="365" value="${remDays()}" style="width:90px"><span class="m">يوم أو أكتر</span>${isAdm(me)?`<button class="btn s" onclick="saveRemDays()">حفظ المدة</button>`:""}</div></div>
 <input placeholder="ابحث بالاسم أو الموبايل" oninput="C.rq=this.value;$('rl').innerHTML=remRows()"><div id="rl">${remRows()}</div>`)};

function remRows(){const q=(C.rq||"").trim().toLowerCase(),L=(C.REM||[]).filter(x=>!q||(x.name||"").toLowerCase().includes(q)||String(x.phone||"").includes(q));
 return L.length?`<p class="m">${L.length} عميل</p>`+L.map(x=>`<div class="row"><div><b>${esc(x.name)}</b><div class="m">${esc(x.phone||"")} · آخر زيارة من ${x.days} يوم · ${x.visits||0} زيارة</div></div><div>${waBtn(x.phone,0,remMsg(x.name,x.days))}</div></div>`).join(""):`<p class="m empty">مفيش عملاء غايبين المدة دي.</p>`}

async function saveRemDays(){const v=Math.round(+$("rem_d").value);if(!(v>=1&&v<=365))return toast("اكتب عدد أيام من 1 لـ 365");const{error}=await sb.from("app_settings").upsert([{key:"reminder_days",value:v}]);error?toast(error.message):(C.cfg.reminder_days=v,toast("تم حفظ المدة ✓"),V.rem())}
