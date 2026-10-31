/* features/floor/pos.js — الكراسي والكاشير */

// ===== كاشير =====

function drawPos(){const P=C.P,svS=P.s.reduce((a,i)=>a+P.sv.find(x=>x.id==i).price,0),urF=P.ur?svS*(P.ur-1):0,sub=svS+urF+P.p.reduce((a,i)=>a+P.pr.find(x=>x.id==i.id).price*i.q,0),bdS=(()=>{const b=P.bn;if(!b||!(b.service_ids||[]).length||!b.service_ids.every(i=>P.s.includes(i)))return 0;return Math.max(b.service_ids.reduce((a,i)=>a+(P.sv.find(x=>x.id==i)||{price:0}).price,0)-b.price,0)})(),d=bdS>0?Math.min(sub,bdS):Math.min(sub,sub*P.disc/100+(+P.dfx||0)),cb=P.cust?`<div class="cust-pick"><div><b>${esc(P.cust.name)}</b><div class="m">${esc(P.cust.phone||"")} · ${P.cust.visits} زيارة · ${P.cust.points} نقطة</div></div><button class="btn s g" onclick="chCust(null)">تغيير</button></div>`:P.walk?`<div class="cust-pick"><div><b>عميل عابر</b><div class="m">من غير رقم موبايل</div></div><button class="btn s g" onclick="chCust(null)">تغيير</button></div>`:`<div class="cust-find"><input id="cp" type="tel" inputmode="numeric" autocomplete="off" placeholder="رقم موبايل العميل (01xxxxxxxxx)" oninput="chPh()"><div id="cpr"></div><button class="btn s g" onclick="chCust('walk')">عميل عابر (من غير رقم)</button><button class="btn s g" onclick="chNm()">عميل بالاسم بس (يتسجل ويتربط بعدين)</button><div id="cnm"></div></div>`;chSave();
const cfT=(P.cf||[]).reduce((a,i)=>a+((P.cm.find(x=>x.id==i.id)||{price:0}).price*i.q),0);P.cft=cfT;const lines=P.s.map(id=>{const v=P.sv.find(x=>x.id==id);return `<div class="pos-line"><span>${esc(v.name)}</span><b>${fm(v.price)}</b></div>`}).concat(P.p.map(c=>{const v=P.pr.find(x=>x.id==c.id);return `<div class="pos-line"><span>${esc(v.name)} ×${c.q}</span><b>${fm(v.price*c.q)}</b></div>`})).join("")+(urF>0?`<div class="pos-line"><span>⚡ رسوم مستعجل (×${P.ur})</span><b>${fm(urF)}</b></div>`:"");
const payBtns=[["cash","كاش"],["card","كارت"],["wallet","محفظة"]].filter(x=>(x[0]!="card"||C.cfg.pay_card_enabled!==false)&&(x[0]!="wallet"||C.cfg.pay_wallet_enabled!==false)).map(x=>`<button class="chip ${P.pay==x[0]?"sel":""}" onclick="C.P.pay='${x[0]}';drawPos()">${x[1]}</button>`).join("");
put(`<div class="ch-bar"><button class="btn s g" onclick="chBack()">‹ الكراسي</button></div><div class="pos-head"><h1>كرسي ${P.chair}</h1><span class="m">الفاتورة بتتحفظ تلقائي</span></div>
<div class="pos-grid">
<section class="box pos-cust"><h3 class="sec">العميل</h3>${cb}${P.vs?.length?`<select onchange="C.P.rid=this.value;chSave()"><option value="">بدون كوبون ولاء</option>${P.vs.map(v=>`<option value="${v.id}" ${P.rid==v.id?"selected":""}>${esc(v.loyalty_rewards.name)} (${v.code})</option>`).join("")}</select>`:""}<h3 class="sec">الحلاق</h3><select onchange="C.P.bid=this.value;chSave()"><option value="">اختار الحلاق</option>${P.br.map(c=>`<option value="${c.id}" ${P.bid==c.id?"selected":""}>${esc(c.full_name)}</option>`).join("")}</select>
${P.as.length&&P.s.length?`<h3 class="sec">المساعد (اختياري)</h3>${P.s.map(id=>{const v=P.sv.find(x=>x.id==id);return `<div class="m" style="margin-top:6px">${esc(v.name)}</div><select onchange="P_a(${id},this.value)"><option value="">بدون مساعد</option>${P.as.map(a=>`<option value="${a.id}" ${P.sa[id]==a.id?"selected":""}>${esc(a.full_name)} (${+a.commission_pct}%)</option>`).join("")}</select>`}).join("")}`:""}</section>
<section class="box pos-items"><h3 class="sec">الخدمات</h3><div class="pos-tiles">${SG.render(P.sv,P.s,(x,s,sh)=>`<button class="chip ${s?"sel":""}" onclick="P_s(${x.id})"><b>${esc(sh?SG.label(x):x.name)}</b><span class="m">${fm(x.price)}</span></button>`)}</div><h3 class="sec">المنتجات</h3><div class="chips pos-tiles">${P.pr.map(x=>{const c=P.p.find(y=>y.id==x.id);return `<button class="chip ${c?"sel":""}" ${x.stock<=0?"disabled":""} onclick="P_p(${x.id})"><b>${esc(x.name)}${c?" ×"+c.q:""}</b><span class="m">${fm(x.price)}</span></button>`}).join("")}</div>${P.cm&&P.cm.length?`<h3 class="sec">☕ كوفي كورنر <span class="m">(حسابه منفصل، مش داخل في العمولة ولا الخصم)</span></h3><div class="chips pos-tiles">${P.cm.map(x=>{const c=(P.cf||[]).find(y=>y.id==x.id);return `<button class="chip ${c?"sel":""}" ${x.track&&x.stock<=0?"disabled":""} onclick="P_cf(${x.id},1)"><b>${esc(x.name)}${c?" ×"+c.q:""}</b><span class="m">${fm(x.price)}</span></button>`}).join("")}</div>`:""}</section>
<section class="box pos-bill"><h3 class="sec">الفاتورة</h3><div class="pos-lines">${lines||(cfT?"":`<p class="m">اختار خدمة أو منتج عشان يتضاف هنا.</p>`)}</div>${cfT?`<div class="pos-lines" style="border-top:1px dashed var(--line);margin-top:6px;padding-top:6px"><div class="m">☕ كوفي كورنر (منفصل)</div>${P.cf.map(c=>{const v=P.cm.find(x=>x.id==c.id)||{name:"?",price:0};return `<div class="pos-line"><span>${esc(v.name)} ×${c.q} <button class="chip" style="min-height:28px;padding:0 10px" onclick="P_cf(${c.id},-1)">−</button></span><b>${fm(v.price*c.q)}</b></div>`}).join("")}</div>`:""}
<div class="chips">${discOpts().map(x=>`<button class="chip ${P.disc==x&&!P.dfx?"sel":""}" onclick="pickDisc(${x})">خصم ${x}%${x>discLim()?" 🔒":""}</button>`).join("")}${fixOpts().map(x=>`<button class="chip ${P.dfx==x?"sel":""}" onclick="pickFix(${x})">خصم ${x} ج${fxPct(x,sub)>discLim()?" 🔒":""}</button>`).join("")}</div>
<div class="chips">${payBtns}</div>
<div class="tot"><span class="m">المجموع</span><span>${fm(sub)}</span></div>${d>0?`<div class="tot"><span class="m">${bdS>0?"🎁 خصم باقة "+esc(P.bn.name):"الخصم"}</span><span>- ${fm(d)}</span></div>`:""}${posBn(P)}<div class="tot f"><span>المطلوب</span><span class="pos-total">${fm(sub-d)}</span></div>${cfT?`<div class="tot"><span class="m">☕ كوفي كورنر</span><span>${fm(cfT)}</span></div><div class="tot f"><span>الإجمالي المطلوب من العميل</span><span class="pos-total">${fm(sub-d+cfT)}</span></div>`:""}${(P.req=sub-d,"")}<div class="chips" style="align-items:center;margin-top:6px"><input id="pd_v" type="number" inputmode="decimal" min="0" placeholder="المدفوع الفعلي (لو دفع أكتر)" value="${P.paid||""}" oninput="posPaid(this.value)" style="flex:1;margin:0"><span class="m" id="pd_x">${P.paid>P.req?"زيادة "+fm(P.paid-P.req):""}</span></div><button class="btn" style="width:100%;margin-top:10px" ${sub?"":"disabled"} onclick="checkout()">دفع وإغلاق الفاتورة</button><button class="btn g" style="width:100%;margin-top:8px" onclick="chCancel()">إلغاء الفاتورة وتفضية الكرسي</button></section>
</div>`)}

function P_s(id){const P=C.P;if(P.s.includes(id))delete P.sa[id];P.s=SG.tog(P.s,id,P.sv);drawPos()}

function P_a(id,v){if(v)C.P.sa[id]=v;else delete C.P.sa[id];chSave()}

function P_cf(id,d){const P=C.P,m=P.cm.find(x=>x.id==id);if(!m)return;P.cf=P.cf||[];let c=P.cf.find(x=>x.id==id);if(!c){if(d<0)return;c={id,q:0};P.cf.push(c)}c.q+=d;if(m.track&&c.q>m.stock){c.q=m.stock;toast("المخزون مش كفاية")}if(c.q<=0)P.cf=P.cf.filter(x=>x.id!=id);drawPos()}
function P_p(id){const P=C.P,c=P.p.find(x=>x.id==id),pr=P.pr.find(x=>x.id==id);if(c){c.q<pr.stock?c.q++:toast("الكمية خلصت")}else P.p.push({id,q:1});drawPos()}

// ===== كاشير: كل كرسي = فاتورة مفتوحة (محفوظة على السيرفر، كل الأجهزة تشوفها) =====

const chN=()=>Math.min(12,Math.max(1,+C.cfg.chairs||4));

const chTot=(r,sv,pr)=>{const sub=(r.services||[]).reduce((a,id)=>a+(+(sv.find(x=>x.id==id)||{}).price||0),0)+(r.products||[]).reduce((a,i)=>a+(+(pr.find(x=>x.id==i.id)||{}).price||0)*i.q,0);return Math.max(0,sub-sub*(+r.discount_pct||0)/100-(+r.discount_fixed||0))};

async function chLoadRefs(){const[{data:sv},{data:pr}]=await Promise.all([sb.from("services").select("*").eq("active",true),sb.from("products").select("*").eq("active",true)]);let cm=[];try{const r=await sb.rpc("cafe_menu");if(!r.error)cm=r.data||[]}catch(e){}return{sv:sv||[],pr:pr||[],cm}}

V.pos=async()=>{if(C.chOpenAfter){const n=C.chOpenAfter;C.chOpenAfter=null;return chOpen(n)}
C.chEdit=0;C.cxOpen=0;if(C.P&&!C.P.chair)C.P=null;
const[{data:L,error},R]=await Promise.all([sb.from("open_invoices").select("*,customers(name),profiles(full_name)").order("chair"),chLoadRefs()]);
if(error)return put(`<h1>الكاشير</h1><p class="m">مقدرتش أحمّل الكراسي: ${esc(error.message)}<br>لو ده أول مرة، شغّل patch_open_invoices.sql في Supabase.</p>`);
C.OI=L||[];const N=chN(),by=Object.fromEntries(C.OI.map(r=>[r.chair,r]));let h=`<h1>الكاشير</h1>${waLastCard()}${can("cash_ops")?`<button class="btn s g" style="margin:6px 0" onclick="cxToggle()">+ مصروف / سحب / سلفة</button><div id="cx"></div>`:""}<div class="m">${C.OI.length} من ${N} كراسي شغالة</div><div class="ch-grid">`;
for(let i=1;i<=N;i++){const r=by[i];
if(!r){h+=`<button class="box ch ch-free" onclick="chOpen(${i})"><div class="ch-no">كرسي ${i}</div><div class="m">متاح</div><div class="ch-plus">+ فاتورة جديدة</div></button>`;continue}
const nms=(r.services||[]).map(id=>(R.sv.find(x=>x.id==id)||{}).name).filter(Boolean),pn=(r.products||[]).length,pay=r.status=="paying";
h+=`<button class="box ch ch-busy" onclick="chOpen(${i})"><div class="ch-top"><span class="ch-no">كرسي ${i}</span><span class="tag ${pay?"st-checked_in":"st-in_service"}">${pay?"بتتدفع":"شغالة"}</span></div><b>${esc(r.profiles?.full_name||"من غير حلاق")}</b><div class="m">${esc(r.customers?.name||"عميل عابر")}</div><div class="m ch-sv">${nms.map(esc).join(" + ")||"لسه من غير خدمات"}${pn?" · "+pn+" منتج":""}</div><div class="ch-t">${fm(chTot(r,R.sv,R.pr))}</div></button>`}
put(h+`</div>`+(C.OI.length?"":`<p class="m">كل الكراسي متاحة. افتح فاتورة جديدة لما يبدأ عميل.</p>`));
clearInterval(C.poll);C.poll=setInterval(()=>{if(tab=="pos"&&!C.chEdit&&!C.cxOpen){$("app").classList.add("still");V.pos()}},12000)};

async function chOpen(n){let{data:r}=await sb.from("open_invoices").select("*").eq("chair",n).maybeSingle();
if(!r){const ins=await sb.from("open_invoices").insert({chair:n}).select("*").single();if(ins.error){toast(ins.error.code=="23505"?"الكرسي ده اتفتح من جهاز تاني":ins.error.message);return go("pos")}r=ins.data}
if(r.status=="paying"){if(!confirm("الفاتورة دي معلّقة وبتتدفع (يمكن من جهاز تاني). تفتحها تاني؟"))return go("pos");await sb.from("open_invoices").update({status:"open"}).eq("chair",n)}
const[R,{data:br},{data:asx},cr]=await Promise.all([chLoadRefs(),sb.from("profiles").select("id,full_name").eq("role","barber"),sb.from("profiles").select("id,full_name,commission_pct").eq("role","assistant"),r.customer_id?sb.from("customers").select("id,name,phone,points,visits").eq("id",r.customer_id).maybeSingle():Promise.resolve({data:null})]);
C.P={chair:n,sv:R.sv,pr:R.pr,cm:R.cm||[],cf:(Array.isArray(r.cafe)?r.cafe:[]).filter(i=>(R.cm||[]).some(x=>x.id==i.id)),cu:[],br:br||[],as:asx||[],sa:r.assistants||{},s:(r.services||[]).filter(id=>R.sv.some(x=>x.id==id)),p:(r.products||[]).filter(i=>R.pr.some(x=>x.id==i.id)),cid:r.customer_id?String(r.customer_id):"",cust:cr.data||null,bid:r.barber_id||"",appt:r.appointment_id||null,disc:+r.discount_pct||0,dfx:+r.discount_fixed||0,pay:r.payment_method||"cash",rid:r.redemption_id?String(r.redemption_id):"",vs:[]};
if(C.P.appt){try{const{data:ap}=await sb.from("appointments").select("is_urgent,urgent_state").eq("id",C.P.appt).maybeSingle();if(ap&&ap.is_urgent&&ap.urgent_state=="approved")C.P.ur=Math.max(+C.cfg.urgent_multiplier||2,1)}catch(e){}
  await posBnLoad()}
C.chEdit=1;clearInterval(C.poll);C.P.cid?loadV():drawPos()}

let chT=0;

function chSave(){clearTimeout(chT);chT=setTimeout(chSaveNow,500)}

async function chSaveNow(){clearTimeout(chT);const P=C.P;if(!P||!P.chair||P.paying)return;const{error}=await sb.from("open_invoices").update({barber_id:P.bid||null,customer_id:P.cid?+P.cid:null,appointment_id:P.appt||null,services:P.s,products:P.p,cafe:P.cf||[],assistants:P.sa||{},discount_pct:P.disc||0,discount_fixed:+P.dfx||0,payment_method:P.pay,redemption_id:P.rid?+P.rid:null,updated_at:new Date().toISOString()}).eq("chair",P.chair).eq("status","open");if(error)toast("مقدرتش أحفظ الفاتورة: "+error.message)}

async function chBack(){await chSaveNow();go("pos")}

async function chCancel(){const P=C.P;if(!confirm("تلغي الفاتورة المفتوحة دي وتفضّي الكرسي؟"))return;P.paying=1;clearTimeout(chT);const{error}=await sb.from("open_invoices").delete().eq("chair",P.chair);if(error){P.paying=0;return toast(error.message)}C.P=null;toast("اتفضّى كرسي "+P.chair);go("pos")}

// تحديد العميل برقم الموبايل: لو موجود نستخدمه، ولو جديد نطلب الاسم بس

const chDig=v=>String(v||"").replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/\D/g,"");

function chCust(c){const P=C.P;if(c=="walk"){P.cid="";P.cust=null;P.walk=1}else if(c){P.cid=String(c.id);P.cust=c;P.walk=0}else{P.cid="";P.cust=null;P.walk=0}P.rid="";loadV()}

async function chPh(){const el=$("cp");if(!el)return;const ph=chDig(el.value),o=$("cpr");if(!o)return;
if(ph.length<11){o.innerHTML=ph.length?`<div class="m">${ph.length}/11</div>`:"";return}
if(!/^01\d{9}$/.test(ph)){o.innerHTML=`<div class="m" style="color:var(--red)">الرقم لازم يبدأ بـ 01 ويبقى 11 رقم</div>`;return}
o.innerHTML=`<div class="m">بندوّر...</div>`;
const{data,error}=await sb.from("customers").select("id,name,phone,points,visits").in("phone",[ph,"+2"+ph,"2"+ph]).order("id").limit(5);
if(error){o.innerHTML=`<div class="m" style="color:var(--red)">${esc(error.message)}</div>`;return}
if(data&&data.length){if(data.length>1)toast("تنبيه: الرقم ده متسجل لأكتر من عميل. استخدمت الأقدم.");return chCust(data[0])}
o.innerHTML=`<div class="box" style="margin-top:8px"><div class="m">عميل جديد · ${ph}</div><input id="cn" placeholder="اسم العميل"><button class="btn s" onclick="chNew('${ph}')">إضافة وإكمال</button></div>`}

async function chNew(ph){const n=($("cn")?.value||"").trim();if(n.length<2)return toast("اكتب اسم العميل");
const{error}=await sb.rpc("add_customer",{p_name:n,p_phone:ph});if(error)return toast(error.message);
const{data}=await sb.from("customers").select("id,name,phone,points,visits").eq("phone",ph).order("id").limit(1);
if(!data||!data[0])return toast("اتضاف العميل بس مقدرتش أجيبه، دوّر عليه تاني");okFlash("تمت إضافة العميل",n);chCust(data[0])}

function posPaid(v){const P=C.P;if(!P)return;P.paid=v===""?0:+v;const x=$("pd_x");if(x)x.textContent=P.paid>P.req+(P.cft||0)?"زيادة "+fm(P.paid-P.req-(P.cft||0)):(P.paid&&P.paid<P.req+(P.cft||0)?"أقل من المطلوب ("+fm(P.req+(P.cft||0))+")":"")}

async function checkout(){const P=C.P;if(P.paying)return;if(P.paid&&P.paid<P.req+(P.cft||0)-0.004)return toast("المدفوع أقل من المطلوب ("+fm(P.req+(P.cft||0))+")");if(Object.keys(P.sa||{}).length&&!P.bid)return toast("اختار الحلاق الأول قبل ما تحدد مساعد");
const ch=P.chair;await chSaveNow();P.paying=1;
const{data:lk,error:le}=await sb.from("open_invoices").update({status:"paying"}).eq("chair",ch).eq("status","open").select("chair");
if(le||!lk||!lk.length){P.paying=0;return toast("الفاتورة دي بتتدفع من جهاز تاني أو اتقفلت")}
posBnOn();const items=[...P.s.map(id=>({type:"service",id,qty:1,assistant:(P.sa||{})[id]||null})),...P.p.map(x=>({type:"product",id:x.id,qty:x.q}))];
const ckA={p_customer:P.cid?+P.cid:null,p_barber:P.bid||null,p_items:items,p_discount_pct:P.bnOn?0:(P.disc||0),p_discount_fixed:P.bnOn?0:(P.dfx||0),p_method:P.pay,p_appointment:P.appt,p_redemption:P.rid?+P.rid:null,p_request:P.rqid||null},cfc=(P.cf||[]).map(x=>({id:x.id,qty:x.q}));
const{data,error}=cfc.length?await sb.rpc("pos_checkout_cafe",{...ckA,p_cafe:cfc}):await sb.rpc("pos_checkout",ckA);
if(error){P.paying=0;await sb.from("open_invoices").update({status:"open"}).eq("chair",ch);return toast(error.message)}
let pm="";if(P.paid&&P.paid>P.req+(P.cft||0)+0.004){const r2=await sb.rpc("invoice_set_paid",{p_invoice:data,p_paid:P.paid-(P.cft||0)});pm=r2.error?" (تنبيه: المبلغ الفعلي ماتسجلش: "+r2.error.message+")":" · مدفوع "+fm(P.paid)}
const wc=P.cust,wcid=P.cid;let de=(await sb.from("open_invoices").delete().eq("chair",ch)).error;if(de)await sb.from("open_invoices").delete().eq("chair",ch);
C.P=null;await waPrep(data,wc,wcid);okFlash("تم الدفع","فاتورة رقم "+(data&&typeof data=="object"?JSON.stringify(data):data)+" · كرسي "+ch+" اتفضّى"+pm);go("pos")}

async function payAppt(id){const a=(C.A||[]).find(x=>x.id==id);if(!a)return;const{data:L}=await sb.from("open_invoices").select("chair,appointment_id");
const ex=(L||[]).find(r=>r.appointment_id==id);let n=ex?ex.chair:0;
if(!n){const used=new Set((L||[]).map(r=>r.chair));for(let i=1;i<=chN();i++)if(!used.has(i)){n=i;break}
if(!n){toast("كل الكراسي مشغولة. اقفل فاتورة الأول");return go("pos")}
const ins=await sb.from("open_invoices").insert({chair:n,customer_id:a.customer_id,barber_id:a.barber_id||null,appointment_id:id,services:(a.appointment_services||[]).map(x=>x.service_id)});
if(ins.error){toast(ins.error.code=="23505"?"الكرسي ده اتاخد، جرّب تاني":ins.error.message);return go("pos")}}
C.chOpenAfter=n;go("pos")}

// تغيير حالة تذكرة: بدء الخدمة للكاشير بس (start_service)، والإلغاء بيمرّ على حارس الحالات في قاعدة البيانات
async function setS(id,s){const r=s=="in_service"?await sb.rpc("start_service",{p_id:id}):await sb.from("appointments").update({status:s}).eq("id",id);if(r.error)return toast(netErr(r.error)?"التحديث لم يتأكد — النت واقف":/شغّالة بالفعل/.test(r.error.message||"")?"الحلاق لسه معاه عميل على الكرسي — اضغط «انتهت» أو «دفع» للعميل اللي معاه الأول، وبعدها ابدأ اللي بعده":r.error.message);go(tab=="home"?"home":"appts")}

function cxToggle(){const b=$("cx");if(!b)return;if(C.cxOpen){C.cxOpen=0;b.innerHTML="";return}C.cxOpen=1;b.innerHTML=`<p class="m">بنحمّل...</p>`;cxLoad()}

async function cxLoad(){const box=$("cx");if(!box)return;const{data,error}=await sb.rpc("cashier_board");
if(error){box.innerHTML=`<p class="m">${/Could not find the function/i.test(error.message||"")?"شغّل ملف cashier_ops.sql في Supabase الأول":esc(error.message)}</p>`;return}
C.cx=data;cxDraw()}

function cxDraw(){const box=$("cx"),d=C.cx;if(!box||!d)return;const K={withdraw:"سحب من الدرج",deposit:"إضافة للدرج"},cats=d.cats&&d.cats.length?d.cats:["إيجار","كهرباء ومياه","صيانة","تسويق","أخرى"];
const form=d.closed?`<p class="m">اليوم اتقفل — مينفعش تسجل عمليات جديدة.</p>`:`<div class="box"><select id="cx_k" onchange="cxKind()"><option value="expense">مصروف</option><option value="withdraw">سحب من الدرج (مالك / إيداع بنك)</option><option value="deposit">إضافة للدرج (فكة / ضخ)</option><option value="advance">سلفة / سحب موظف</option></select><div id="cx_e"><select id="cx_c">${cats.map(c=>`<option>${esc(c)}</option>`).join("")}</select><select id="cx_p">${paySrc("drawer")}</select></div><div id="cx_a" style="display:none"><select id="cx_s"><option value="">اختار الموظف</option>${(d.staff||[]).map(x=>`<option value="${x.id}">${esc(x.name)}</option>`).join("")}</select></div><input id="cx_m" type="number" inputmode="decimal" placeholder="المبلغ"><input id="cx_n" placeholder="ملاحظة (اختياري)"><button class="btn" style="width:100%" onclick="cxSave()">حفظ</button></div>`;
const rows=[...(d.expenses||[]).map(x=>[`مصروف · ${esc(x.category)}${x.paid_from=="other"?" (من برا الدرج)":""}`,x.amount,x.note]),...(d.moves||[]).map(x=>[K[x.kind]||x.kind,x.amount,x.note]),...(d.advances||[]).map(x=>[`سلفة · ${esc(x.staff)}`,x.amount,x.note])];
box.innerHTML=`<div class="chips" style="align-items:center;justify-content:space-between"><h2>تسجيل من الخزنة</h2><button class="btn s g" onclick="cxToggle()">إغلاق</button></div>${form}<h2>عمليات النهارده</h2>`+(rows.length?rows.map(r=>`<div class="row"><div><b>${r[0]}</b> · ${fm(r[1])}<div class="m">${esc(r[2]||"")}</div></div></div>`).join(""):`<p class="m">لسه مفيش عمليات النهارده.</p>`)}

function cxKind(){const k=$("cx_k").value;$("cx_e").style.display=k=="expense"?"":"none";$("cx_a").style.display=k=="advance"?"":"none"}

async function cxSave(){if(C.cxBusy)return;const k=$("cx_k").value,a=parseFloat($("cx_m").value),n=$("cx_n").value.trim()||null;if(!(a>0))return toast("اكتب المبلغ");
let fn,args,txt;
if(k=="expense"){fn="cashier_add_expense";args={p_category:$("cx_c").value,p_amount:a,p_note:n,p_paid_from:$("cx_p").value};txt="مصروف "+$("cx_c").value}
else if(k=="advance"){const sel=$("cx_s");if(!sel.value)return toast("اختار الموظف");fn="cashier_add_advance";args={p_staff:sel.value,p_amount:a,p_note:n};txt="سلفة "+sel.options[sel.selectedIndex].text}
else{fn="cashier_add_move";args={p_kind:k,p_amount:a,p_note:n};txt=k=="withdraw"?"سحب من الدرج":"إضافة للدرج"}
if(!confirm("تسجّل "+txt+" بمبلغ "+fm(a)+"؟"))return;
C.cxBusy=1;try{const{error}=await sb.rpc(fn,args);if(error)return toast(/Could not find the function/i.test(error.message||"")?"شغّل ملف cashier_ops.sql في Supabase الأول":error.message);toast("تم التسجيل ✓");cxLoad()}finally{C.cxBusy=0}}

function chNm(){const o=$("cnm");if(!o)return;if(o.innerHTML)return o.innerHTML="";o.innerHTML=`<div class="box" style="margin-top:8px"><input id="cnn" placeholder="اسم العميل" oninput="chNmQ()"><div id="cnr"></div><button class="btn s" onclick="chNmNew()">تسجيل باسم جديد وإكمال</button></div>`;$("cnn").focus()}
async function chNmQ(){const n=($("cnn")?.value||"").trim(),o=$("cnr");if(!o)return;if(n.length<2){o.innerHTML="";return}
const{data}=await sb.from("customers").select("id,name,phone,points,visits").is("phone",null).ilike("name","%"+n.replace(/[%_,()]/g," ")+"%").limit(6);
window._cnm=data||[];o.innerHTML=(data||[]).map((c,i)=>`<button class="btn s g" onclick="chCust(window._cnm[${i}])">${esc(c.name)} · ${c.points} نقطة</button>`).join("")}
async function chNmNew(){const n=($("cnn")?.value||"").trim();if(n.length<2)return toast("اكتب اسم العميل");
const{data:id,error}=await sb.rpc("add_customer",{p_name:n,p_phone:null});if(error)return toast(error.message);
const{data}=await sb.from("customers").select("id,name,phone,points,visits").eq("id",id).maybeSingle();if(!data)return toast("اتسجل بس مقدرتش أجيبه");okFlash("تم تسجيل العميل",n);chCust(data)}


// ---- الباقات في الكاشير: الخصم بيتحسب على السيرفر من تذكرة الحجز؛ هنا للعرض وتطبيق/إلغاء باقة على التذكرة ----
async function posBnLoad(){const P=C.P;if(!P||!P.appt){if(P){P.bn=null;P.bnOn=false}return}
  try{await BN.load(sb);const{data}=await sb.rpc("ticket_bundle",{p_id:P.appt});P.bn=data||null}catch(e){P.bn=null}
  posBnOn()}
function posBnOn(){const P=C.P;P.bnOn=!!(P.bn&&(P.bn.service_ids||[]).length&&P.bn.service_ids.every(i=>P.s.includes(i)))}
function posBn(P){if(!P.appt)return"";
  const cand=(BN.L||[]).filter(b=>(!P.bn||b.id!=P.bn.id)&&BN.ids(b).every(i=>P.s.includes(i)));
  return(P.bn?`<div class="m" style="margin:6px 0">${P.bnOn?"🎁 باقة «"+esc(P.bn.name)+"» مطبّقة (مفيش خصم يدوي معاها)":"باقة «"+esc(P.bn.name)+"» على التذكرة بس خدماتها مش كلها في الفاتورة"} <button class="btn s g" onclick="posBnSet(null)">إلغاء الباقة</button></div>`:"")
   +cand.map(b=>`<button class="btn s g" style="margin:4px 0;width:100%" onclick="posBnSet(${b.id})">🎁 طبّق باقة ${esc(b.name)} · وفّر ${fm(b.saving)}</button>`).join("")}
async function posBnSet(id){const P=C.P;if(!P||!P.appt)return;const{error}=await sb.rpc("set_ticket_bundle",{p_id:P.appt,p_bundle:id});if(error)return toast(error.message);await posBnLoad();drawPos()}
