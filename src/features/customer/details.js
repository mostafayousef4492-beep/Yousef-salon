/* features/customer/details.js — تفاصيل كل كارت في تطبيق العميل (بتفتح في ورقة تفاصيل) */

const cdRow=(l,v,b)=>dsKv(l,v,b);
const cdBook=(label,fn)=>`<button class="btn" style="width:100%;margin-top:12px" onclick="svcClose();${fn}">${label}</button>`;
const cdDay=d=>{try{return new Date(d).toLocaleDateString("ar-EG",{weekday:"long",day:"numeric",month:"long"})}catch(e){return d||""}};

// ---- كروت الرئيسية ----
function cdPoints(){const H=C.hm;if(!H)return;const c=H.c,t=H.t;
  dsOpen("نقاطك",`<div class="box" style="text-align:center"><div class="m">رصيدك الحالي</div><b style="font-size:34px">${num(c.points||0)}</b> <span class="m">نقطة</span></div>
<div class="box" style="margin-top:8px">${cdRow("إجمالي اللي جمعته",num(c.lifetime_points||0)+" نقطة")}${cdRow("مستواك",esc(t.name||"عضو")+(t.mult>1?" · ×"+t.mult:""))}${t.next_at?cdRow("باقي للمستوى الجاي",num(Math.max(0,t.next_at-c.lifetime_points))+" نقطة"):cdRow("المستوى","أعلى مستوى")}</div>
<div id="cd_lg"></div>${cdBook("استبدل نقاطك","go('loy')")}`);
  (async()=>{try{const r=await sb.from("loyalty_ledger").select("points,reason,note,created_at").eq("customer_id",c.id).order("created_at",{ascending:false}).limit(8),e=$("cd_lg");if(!e||!r.data||!r.data.length)return;e.innerHTML=`<h2>آخر الحركات</h2>`+r.data.map(l=>`<div class="row"><div>${esc((l.reason=="adjust"&&l.note&&l.note.trim())||RSN[l.reason]||l.reason)}<div class="m">${new Date(l.created_at).toLocaleDateString("ar-EG")}</div></div><b style="color:${l.points>0?"var(--ok)":"var(--red)"}">${l.points>0?"+":""}${l.points}</b></div>`).join("")}catch(e){}})()}

function cdTier(){const H=C.hm;if(!H)return;const c=H.c,t=H.t,pct=t.next_at?Math.min(100,c.lifetime_points/t.next_at*100):100;
  dsOpen("مستواك",`<div class="box" style="text-align:center"><div class="m">مستواك الحالي</div><b style="font-size:26px">${esc(t.name||"عضو")}</b>${t.mult>1?`<div class="m">نقاطك بتتضاعف ×${t.mult}</div>`:""}</div>
<div class="vip-bar" style="margin:12px 0"><i style="width:${pct}%"></i></div>
<div class="box">${cdRow("نقاطك المجمّعة",num(c.lifetime_points||0))}${t.next_at?cdRow("المستوى الجاي عند",num(t.next_at)+" نقطة")+cdRow("باقي",num(Math.max(0,t.next_at-c.lifetime_points))+" نقطة",1):cdRow("الحالة","وصلت لأعلى مستوى ✓",1)}</div>
<div class="m" style="margin-top:8px">كل ${esc(C.cfg.points_per_currency)} ${esc(C.cfg.currency)} بتدفعها = نقطة، بتتضرب في مضاعف مستواك.</div>`)}

async function cdVisits(){const{data:h}=await sb.rpc("my_history");const L=(h||[]).filter(x=>x.status=="done");C.hist=h||[];
  dsOpen("زياراتك",L.length?`<div class="m" style="margin-bottom:8px">${L.length} زيارة · إجمالي دفعك <b>${fm(L.reduce((a,x)=>a+(+x.paid||0),0))}</b></div>`+L.map(x=>`<div class="row" role="button" tabindex="0" style="cursor:pointer" onclick="cdVisit(${x.id})"><div><b>${esc(x.day||"")}</b><div class="m">${esc(x.services||"")} مع ${esc(x.barber_name||"-")}</div></div><div style="text-align:left">${x.paid!=null?`<b>${fm(x.paid)}</b>`:""}<div class="m">تفاصيل ‹</div></div></div>`).join(""):`<p class="m">لسه معندكش زيارات خلصت.</p>`)}

async function cdSuggest(){const lv=C.lastVisit,{data}=await sb.from("services").select("id,name,price,duration_min,description,category").eq("active",true).order("price");const S=data||[];C.svcs=C.svcs||{};S.forEach(x=>C.svcs[x.id]=x);
  dsOpen("مناسب لك",(lv?`<div class="box"><div class="m">آخر زيارة</div><b>${esc(lv.services||"—")}</b>${lv.barber_name?`<div class="m">مع ${esc(lv.barber_name)}</div>`:""}<button class="btn" style="width:100%;margin-top:8px" onclick="svcClose();repeatVisit()">كرّر آخر زيارة</button></div>`:"")+`<h2>الخدمات</h2>`+(S.length?S.slice(0,8).map(x=>`<div class="row" role="button" tabindex="0" style="cursor:pointer" onclick="cdSvc(${x.id})"><div><b>${esc(x.name)}</b><div class="m">${x.duration_min} دقيقة</div></div><b style="color:var(--brass)">${fm(x.price)}</b></div>`).join(""):`<p class="m">مفيش خدمات متاحة دلوقتي.</p>`)+cdBook("منيو الخدمات الكامل","go('menu')"),{list:1})}

// ---- تفاصيل زيارة / حجز ----
async function cdVisit(id){const x=(C.hist||[]).find(r=>r.id==id);if(!x)return;
  dsOpen("تفاصيل الزيارة",`<div class="box">${cdRow("اليوم",esc(cdDay(x.day)))}${x.period?cdRow("الفترة",PLB[x.period]||""):""}${cdRow("رقم الدور",esc(x.ticket_code||x.ticket_no||"-"))}${cdRow("الحلاق",esc(x.barber_name||"-"))}${cdRow("الخدمات",esc(x.services||"-"))}${cdRow("الحالة",ST[x.status]||x.status)}${x.points?cdRow("نقاط",`+${x.points}`):""}</div><div id="cd_bill"></div>
${x.status=="done"||x.status=="cancelled"||x.status=="no_show"?cdBook("احجز تاني","C.b=null;go('book')"):cdBook("شوف دورك","go('queue')")}`,{back:1});
  try{const{data:b}=await sb.rpc("ticket_bill",{p_id:x.id});const e=$("cd_bill");if(e&&b&&(+b.total>0||b.paid)){e.innerHTML=`<h2>الحساب</h2><div class="box">${b.subtotal!=null?cdRow("الخدمات",fm(+b.subtotal)):""}${+b.discount>0?cdRow("خصم","- "+fm(+b.discount)):""}${+b.urgent_fee>0?cdRow("رسوم مستعجل",fm(+b.urgent_fee)):""}${+b.extra>0?cdRow("زيادة",fm(+b.extra)):""}${cdRow(b.paid?"اتدفع":"المطلوب",fm(+b.total),1)}</div>`}}catch(e){}}

// ---- تفاصيل خدمة ----
function cdSvc(id){const x=(C.svcs||{})[id];if(!x)return;
  dsOpen(x.name,`<div class="box" style="text-align:center"><b style="font-size:28px;color:var(--brass)">${fm(x.price)}</b></div>
<div class="box" style="margin-top:8px">${x.category?cdRow("القسم",esc(x.category)):""}${cdRow("المدة",num(x.duration_min)+" دقيقة")}${x.description?`<div class="m" style="margin-top:6px;line-height:1.8">${esc(x.description)}</div>`:""}</div>
${cdBook("احجز الخدمة دي","C.b=C.b||{s:[],barber:undefined,day:0,period:null};C.b.s=["+(+x.id)+"];go('book')")}`,{back:1})}

// ---- تفاصيل مكافأة / حركة / كوبون ----
function cdReward(id){const x=(C.rws||{})[id],pts=+((C.lc||{}).points)||0;if(!x)return;const miss=Math.max(0,x.cost-pts);
  dsOpen(x.name,`<div class="box" style="text-align:center"><b style="font-size:28px">${num(x.cost)}</b> <span class="m">نقطة</span></div>
<div class="box" style="margin-top:8px">${cdRow("رصيدك",num(pts)+" نقطة")}${miss>0?cdRow("ناقصك",num(miss)+" نقطة",1):cdRow("الحالة","تقدر تستبدلها ✓",1)}${x.description?`<div class="m" style="margin-top:6px">${esc(x.description)}</div>`:""}</div>
${miss>0?`<div class="m" style="margin-top:8px">كل ${esc(C.cfg.points_per_currency)} ${esc(C.cfg.currency)} = نقطة. كمّل زياراتك وهتوصل.</div>`:`<button class="btn" style="width:100%;margin-top:12px" onclick="svcClose();redeem(${x.id})">استبدل دلوقتي</button>`}`)}

function cdLedger(i){const l=(C.lgs||[])[i];if(!l)return;
  dsOpen("تفاصيل الحركة",`<div class="box"><div style="text-align:center"><b style="font-size:28px;color:${l.points>0?"var(--ok)":"var(--red)"}">${l.points>0?"+":""}${l.points}</b> <span class="m">نقطة</span></div>${cdRow("النوع",esc((l.reason=="adjust"&&l.note&&l.note.trim())||RSN[l.reason]||l.reason))}${cdRow("التاريخ",new Date(l.created_at).toLocaleString("ar-EG"))}${l.note&&l.reason!="adjust"?cdRow("ملاحظة",esc(l.note)):""}</div>`)}

function cdCoupon(code,name){dsOpen("كوبونك",`<div class="box" style="text-align:center"><div class="m">${esc(name)}</div><b style="font-family:var(--display);font-size:38px;letter-spacing:5px;color:var(--gold2)">${esc(code)}</b></div><div class="m" style="margin-top:8px">قدّم الكود ده للكاشير وقت الحساب.</div>`)}
