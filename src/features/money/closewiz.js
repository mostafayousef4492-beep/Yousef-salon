/* features/money/closewiz.js — قفل اليوم خطوة بخطوة (واجهة بس: بيستخدم نفس دوال القفل close_day_preview / close_day بدون أي تغيير فيها)
   ١ جاهزية (اللي لسه مقفولش) ← ٢ العدّ ← ٣ المراجعة ← ٤ القفل + مشاركة الملخص. لو أي حاجة هنا فشلت، شاشة القفل القديمة بتفضل شغّالة زي ما هي. */

const CW={step:1};
const CW_ST=["جاهزية","العدّ","المراجعة","القفل"];
(()=>{if(typeof V=="undefined"||!V.cash)return;const c0=V.cash;
  V.cash=async function(){const r=await c0.apply(this,arguments);try{await cwInject()}catch(e){try{const b=$("kc_cash");if(b&&b.closest(".box"))b.closest(".box").style.display=""}catch(_){}}return r};
  if(typeof doClose=="function"){const d0=doClose;doClose=async function(){const r=await d0.apply(this,arguments);try{if(C.clp)cwStep(3)}catch(e){}return r}}})();

function cwPills(){return `<div id="cw_pills" style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:8px">${CW_ST.map((t,i)=>`<span class="tag" style="${CW.step==i+1?"background:var(--gold,#c9a35a);color:#14110b;font-weight:700":CW.step>i+1?"opacity:.9":"opacity:.55"}">${CW.step>i+1?"✓":i+1} ${t}</span>`).join("")}</div>`}
function cwStep(n){CW.step=n;const p=$("cw_pills");if(p)p.outerHTML=cwPills()}
function cwShowCount(){const b=$("kc_cash"),bx=b&&b.closest(".box");if(bx){bx.style.display="";cwStep(2);try{bx.scrollIntoView({behavior:"smooth",block:"start"})}catch(e){}}const g=$("cw_go");if(g)g.remove()}

async function cwInject(){const day=C.cd||bizToday(),inp=$("kc_cash"),bx=inp&&inp.closest(".box");
  if(!bx){cwShare(day);return}
  CW.step=1;bx.style.display="none";
  const holder=document.createElement("div");holder.id="cw_panel";holder.className="box";holder.innerHTML=cwPills()+`<b>قبل ما تقفل اليوم</b><div class="m" id="cw_list">بنراجع اليوم...</div>`;
  bx.parentNode.insertBefore(holder,bx);
  let pend=0,upc=0,alerts=[];
  try{const{data:pv}=await sb.rpc("close_day_preview",{p_day:day});if(pv){pend=+pv.pending||0;upc=+pv.upcoming||0}}catch(e){}
  if(isAdm(me)){try{const{data:rp}=await sb.rpc("day_report",{p_day:day});if(rp&&Array.isArray(rp.alerts))alerts=rp.alerts}catch(e){}}
  const row=(ok,t,go)=>`<div class="row"><span>${ok?"✅":"⚠️"} ${t}</span>${go||""}</div>`,warn=alerts.filter(a=>a.level!="info");
  const L=[row(!pend,pend?`فيه ${pend} حجز لسه في الدور (دخل أو على الكرسي)`:"مفيش حجوزات معلّقة",pend?`<button class="btn s g" onclick="go('appts')">افتح الحجوزات</button>`:"")];
  if(upc)L.push(`<div class="m">${upc} حجز لسه ما جاش، هيفضل زي ما هو.</div>`);
  alerts.forEach(a=>L.push(row(a.level=="info",esc(a.text))));
  const blocked=pend>0||warn.length>0;
  $("cw_list").innerHTML=L.join("")+`<button class="btn" id="cw_go" style="width:100%;margin-top:10px" onclick="cwShowCount()">${blocked?"كمّل للعدّ برغم كده":"كله تمام، كمّل للعدّ"}</button>`}

async function cwShare(day){const h=[...document.querySelectorAll("#app h2")].find(x=>(x.textContent||"").startsWith("اتقفل يوم"));if(!h||$("cw_share"))return;
  let r=C.cres&&C.cres.day==day?C.cres:null;
  if(!r){try{const{data}=await sb.from("cash_closings").select("*").eq("day",day).limit(1);r=data&&data[0]}catch(e){}}
  if(!r)return;
  const n=v=>fm(+v||0),dd=k=>{const d=+r["diff_"+k];return d==0?"مظبوط":(d>0?"زيادة ":"عجز ")+n(Math.abs(d))};
  const txt=`قفل يوم ${day}\nكاش: متوقع ${n(r.expected_cash)} · معدود ${n(r.counted_cash)} · ${dd("cash")}\nكارت: متوقع ${n(r.expected_card)} · معدود ${n(r.counted_card)} · ${dd("card")}\nمحفظة: متوقع ${n(r.expected_wallet)} · معدود ${n(r.counted_wallet)} · ${dd("wallet")}`;
  const b=document.createElement("div");b.id="cw_share";b.innerHTML=`<div id="cw_pills" style="display:flex;gap:6px;flex-wrap:wrap;margin:6px 0">${CW_ST.map((t,i)=>`<span class="tag">✓ ${t}</span>`).join("")}</div><button class="btn s" onclick="window.open('https://wa.me/?text='+encodeURIComponent(CW.txt))">📤 شارك ملخص القفل</button>`;
  CW.txt=txt;h.after(b)}
