/* ui/details.js — نوافذ التفاصيل */

// ================= تفاصيل الـ KPI + تفاصيل الفاتورة =================
// أي كارت رقم بيتضغط عليه بيفتح نافذة فيها الداتا اللي اتحسب منها الرقم، والفاتورة بتفتح بتفاصيلها كاملة.
// PAYL متعرّف فوق في ملف التقارير

const LYR={redeem:"استبدال",visit:"زيارة",purchase:"فاتورة",invoice:"فاتورة",review:"تقييم",welcome:"هدية تسجيل",admin:"تعديل إداري",adjust:"تعديل إداري",visit_bonus:"مكافأة زيارات"};

const dsT=d=>d?new Date(d).toLocaleString("ar-EG",{hourCycle:"h23",day:"numeric",month:"numeric",hour:"2-digit",minute:"2-digit"}):"—";

const dsPh=()=>!!me&&(isAdm(me)||can("view_customer_phone"));

const dsRow=(a,b,c)=>`<div class="row"><div>${a}${b?`<div class="m">${b}</div>`:""}</div>${c?`<div style="text-align:left">${c}</div>`:""}</div>`;

const dsKv=(l,v,b)=>`<div style="display:flex;justify-content:space-between;gap:10px;padding:4px 0;${b?"font-weight:800;border-top:1px solid var(--line);margin-top:4px":""}"><span>${l}</span><span>${v}</span></div>`;

const dsEmpty=m=>`<p class="m">${m||"مفيش بيانات في الفترة دي."}</p>`;

function dsOpen(title,html,o){o=o||{};if(o.list)C.dsL={t:title,h:html};
  const old=$("sheet");if(old)old.remove();
  const w=document.createElement("div");w.id="sheet";w.className="sheet-bg";w.onclick=e=>{if(e.target==w)svcClose()};
  w.innerHTML=`<div class="sheet" role="dialog" aria-modal="true"><div class="sheet-h"><b>${esc(title)}</b><span>${o.back&&C.dsL?`<button class="btn g s" onclick="dsBack()">‹ رجوع</button> `:""}<button class="btn g s" onclick="svcClose()" aria-label="إغلاق">✕</button></span></div>${html}</div>`;
  permApply(w);document.body.appendChild(w)}

const dsLoad=t=>dsOpen(t,`<p class="m">بنحمّل...</p>`);

function dsBack(){const L=C.dsL;if(L)dsOpen(L.t,L.h,{list:1})}

async function dsQ(t,p,f){dsLoad(t);const{data,error}=await p;if(error)return dsOpen(t,dsEmpty(error.message));const L=data||[];dsOpen(t,L.length?f(L):dsEmpty(),{list:1})}
