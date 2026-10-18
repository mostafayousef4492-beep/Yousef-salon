/* ui/bundles-ui.js — الباقات في شاشات الحجز (تطبيق العميل، /book، التابلت)
   الحالة المشتركة: b = {s:[ids الخدمات], bd: id الباقة المختارة أو null}. لو الباقة اتقفلت أو الجدول مش موجود، القايمة بتبقى فاضية والحجز عادي. */
const BN={L:[]};

BN.load=async function(client){try{const{data,error}=await client.rpc("bundles_list");BN.L=!error&&Array.isArray(data)?data:[]}catch(e){BN.L=[]}};
BN.get=id=>BN.L.find(x=>x.id==id);
BN.ids=bd=>(bd.services||[]).map(x=>x.id);

// اختيار/إلغاء باقة: بتنوّر خدماتها (بتتضاف لـ b.s) وبتشيل خدمات الباقة اللي قبلها
BN.pick=function(b,id){
  const old=b.bd&&BN.get(b.bd);
  if(b.bd==id){b.s=b.s.filter(x=>!BN.ids(old).includes(x));b.bd=null;return}
  if(old)b.s=b.s.filter(x=>!BN.ids(old).includes(x));
  const nw=BN.get(id);if(!nw)return;
  b.s=[...new Set([...b.s,...BN.ids(nw)])];b.bd=id};

// بعد أي تعديل في الخدمات: لو خدمات الباقة ما بقتش كلها موجودة، الباقة بتتشال (الخدمات الباقية بتتحسب بسعرها)
BN.sync=function(b){if(!b.bd)return;const bd=BN.get(b.bd);if(!bd||!BN.ids(bd).every(x=>b.s.includes(x)))b.bd=null};

BN.calc=function(b,SV){const sv=SV.filter(x=>b.s.includes(x.id)),full=sv.reduce((a,x)=>a+(+x.price||0),0),bd=b.bd&&BN.get(b.bd),saving=bd?+bd.saving||0:0;
  return{full,saving,total:Math.max(full-saving,0),dur:sv.reduce((a,x)=>a+(+x.duration_min||0),0),bd}};

BN.star=(b,id)=>b.bd&&BN.get(b.bd)&&BN.ids(BN.get(b.bd)).includes(id)?"★ ":"";

// كروت الباقات (fn = اسم دالة الاختيار في الصفحة) + ملخص الحساب لما تكون باقة مختارة
BN.html=function(b,fn,fm){
  if(!BN.L.length)return"";
  const sel="border-color:var(--gold,#c9a24a);box-shadow:0 0 0 2px var(--gold,#c9a24a) inset;";
  return`<h2>الباقات <span class="m">(أوفر من الخدمات لوحدها)</span></h2>`+BN.L.map(x=>`<button class="row" style="cursor:pointer;width:100%;text-align:right;${b.bd==x.id?sel:""}" onclick="${fn}(${x.id})"><div><b>${esc(x.name)}</b><div class="m">${(x.services||[]).map(s=>esc(s.name)).join(" + ")}</div>${x.description?`<div class="m">${esc(x.description)}</div>`:""}</div><div style="text-align:left"><s class="m">${fm(x.full)}</s><br><b>${fm(x.price)}</b><br><span class="tag">وفّر ${fm(x.saving)}</span></div></button>`).join("")};

BN.summary=function(b,SV,fm){const c=BN.calc(b,SV);if(!c.bd)return"";
  return`<div class="box" style="margin:10px 0;border-color:var(--gold,#c9a24a)"><b>🎁 ${esc(c.bd.name)}</b>
<div style="display:flex;justify-content:space-between;padding-top:6px"><span>الخدمات دي كلها لوحدها</span><span>${fm(c.bd.full)}</span></div>
<div style="display:flex;justify-content:space-between"><span>خصم الباقة</span><b style="color:var(--ok,#2ea66b)">− ${fm(c.saving)}</b></div>
<div style="display:flex;justify-content:space-between;border-top:1px solid var(--line,#2a2f3a);margin-top:6px;padding-top:6px"><b>الإجمالي بعد الباقة</b><b>${fm(c.total)}</b></div></div>`};

// بعد ما التذكرة تتحجز: نربط الباقة بيها (السيرفر بيتأكد إن الخدمات مطابقة). phone للزائر من غير حساب.
BN.attach=async function(client,b,ticketId,phone){if(!b.bd||!ticketId)return true;
  try{const{error}=await client.rpc("set_ticket_bundle",{p_id:ticketId,p_bundle:b.bd,p_phone:phone||null});return!error}catch(e){return false}};
