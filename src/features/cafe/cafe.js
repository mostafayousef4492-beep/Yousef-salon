/* features/cafe/cafe.js — كوفي كورنر: بيع سريع، منتجات، مشتريات ومخزون، مصروفات، تقارير
   كل الكتابة بتمر على دوال قاعدة البيانات (cafe_*) والصلاحيات متحققة هناك مش بس هنا. */

(()=>{try{const st=document.createElement("style");st.textContent=`
.cf-head{display:flex;gap:12px;align-items:center;margin-bottom:8px}.cf-head h1{margin:0}.cf-ic{font-size:30px;width:52px;height:52px;display:grid;place-items:center;border-radius:16px;background:#0b0b0b;border:1px solid var(--gold)}
.cf-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin:10px 0}@media(min-width:700px){.cf-grid{grid-template-columns:repeat(4,minmax(0,1fr))}}
.cf-tile{position:relative;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;min-height:92px;padding:12px;border-radius:16px;border:1px solid var(--line);background:#0b0b0b;color:#fff;font:inherit;cursor:pointer}
.cf-tile b{font-size:16px}.cf-tile span{color:var(--gold2);font-weight:700}.cf-tile small{color:var(--mute);font-size:11px}.cf-tile.sel{border-color:var(--gold);box-shadow:0 0 0 1px var(--gold) inset}.cf-tile:disabled{opacity:.45}.cf-tile:active{transform:scale(.97)}
.cf-badge{position:absolute;top:6px;inset-inline-start:8px;min-width:24px;height:24px;border-radius:999px;background:var(--gold);color:#1A1405;font-style:normal;font-weight:800;display:grid;place-items:center;font-size:13px}
.cf-line{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:8px 0;border-bottom:1px dashed var(--line)}.cf-q{display:inline-flex;align-items:center;gap:8px}.cf-q .chip{min-height:36px;padding:4px 14px}
.cf-go{width:100%;margin-top:10px;min-height:54px;font-size:17px}.cf-rec{display:flex;justify-content:space-between;align-items:center;gap:8px;margin-bottom:8px}.cf-rec.void{opacity:.55}
.cf-kpis{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin:10px 0}@media(min-width:700px){.cf-kpis{grid-template-columns:repeat(4,minmax(0,1fr))}}
.cf-kpi{background:#0b0b0b;border:1px solid var(--line);border-radius:14px;padding:12px;display:flex;flex-direction:column;gap:4px;color:#fff}.cf-kpi b{font-size:19px;color:var(--gold2)}
.cf-two{display:grid;grid-template-columns:1fr 1fr;gap:8px}.cf-item{border:1px dashed var(--line);border-radius:12px;padding:8px;margin:8px 0}.cf-prod{margin-bottom:10px}
`;document.head.appendChild(st)}catch(e){}})();
const cfm=n=>(+n||0).toLocaleString("ar-EG",{maximumFractionDigits:2})+" "+C.cfg.currency;
const CF_PAY=[["cash","كاش"],["card","كارت"],["wallet","محفظة"]];
const CF_CATS=["كهرباء","صيانة","مستلزمات","أخرى"];
const cfPays=()=>CF_PAY.filter(x=>(x[0]!="card"||C.cfg.pay_card_enabled!==false)&&(x[0]!="wallet"||C.cfg.pay_wallet_enabled!==false));
const cfTm=t=>new Date(t).toLocaleString("ar-EG",{hourCycle:"h23",month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit"});
const cfAdm=()=>isAdm(me);
const cfOwner=()=>!!me&&me.role=="owner";
const cfDeny=()=>put(`<h1>كوفي كورنر</h1><p class="m">الشاشة دي للمدير والمالك بس.</p>`);
async function cfRpc(n,a){const{data,error}=await sb.rpc(n,a||{});if(error){toast(error.message);return{error}}return{data}}
function cfHead(t,sub){return `<div class="cf-head"><span class="cf-ic">☕</span><div><h1>${t}</h1><div class="m">${sub||"كوفي كورنر — حساباته منفصلة عن الصالون"}</div></div></div>`}

// ============================ البيع السريع ============================
V.cafe=async()=>{
  const S=C.cf=C.cf||{cart:{},pay:"cash",note:""};
  put(cfHead("بيع سريع")+`<p class="m">بنحمّل...</p>`);
  const[m,r]=await Promise.all([cfRpc("cafe_menu"),cfRpc("cafe_recent_sales",{p_limit:15})]);
  if(m.error)return put(cfHead("بيع سريع")+`<p class="m">${esc(m.error.message)}<br>لو ده أول مرة، لازم patch_coffee_corner.sql يتشغّل في Supabase.</p>`);
  S.menu=m.data||[];S.recent=r.data||[];
  Object.keys(S.cart).forEach(k=>{if(!S.menu.some(x=>x.id==k))delete S.cart[k]});
  cfDraw()};

function cfDraw(){
  const S=C.cf,lines=S.menu.filter(x=>S.cart[x.id]).map(x=>({...x,q:S.cart[x.id]})),tot=lines.reduce((a,x)=>a+x.price*x.q,0),pays=cfPays();
  if(!pays.some(x=>x[0]==S.pay))S.pay="cash";
  put(cfHead("بيع سريع")+`
  <div class="cf-grid">${S.menu.map(x=>{const q=S.cart[x.id]||0,out=x.track&&x.stock<=0;return `<button class="cf-tile ${q?"sel":""}" ${out?"disabled":""} onclick="cfAdd(${x.id},1)"><b>${esc(x.name)}</b><span>${cfm(x.price)}</span>${x.track?`<small>${out?"خلص":"متاح "+num(x.stock)}</small>`:""}${q?`<i class="cf-badge">${num(q)}</i>`:""}</button>`}).join("")||`<p class="m">مفيش منتجات. المدير يضيفها من شاشة المنتجات.</p>`}</div>
  <section class="box cf-cart"><h3 class="sec">الطلب</h3>${lines.map(x=>`<div class="cf-line"><span>${esc(x.name)}</span><span class="cf-q"><button class="chip" onclick="cfAdd(${x.id},-1)" aria-label="نقص">−</button><b>${num(x.q)}</b><button class="chip" onclick="cfAdd(${x.id},1)" aria-label="زوّد">+</button></span><b>${cfm(x.price*x.q)}</b></div>`).join("")||`<p class="m">اضغط على منتج عشان يتضاف.</p>`}
  <div class="tot f"><span>الإجمالي</span><span class="pos-total">${cfm(tot)}</span></div>
  <div class="chips">${pays.map(x=>`<button class="chip ${S.pay==x[0]?"sel":""}" onclick="C.cf.pay='${x[0]}';cfDraw()">${x[1]}</button>`).join("")}</div>
  <input id="cf_note" placeholder="ملاحظة (اختياري)" value="${esc(S.note||"")}" oninput="C.cf.note=this.value">
  <button class="btn cf-go" ${tot?"":"disabled"} onclick="cfSell()">تسجيل البيع ${tot?"— "+cfm(tot):""}</button>${lines.length?`<button class="btn g" style="width:100%;margin-top:8px" onclick="C.cf.cart={};cfDraw()">مسح الطلب</button>`:""}</section>
  <h3 class="sec">آخر العمليات</h3>${S.recent.length?S.recent.map(x=>`<div class="box cf-rec ${x.status=="void"?"void":""}"><div><b>${cfm(x.total)}</b> <span class="tag">${x.kind=="salon"?"عميل صالون"+(x.invoice_no?" #"+esc(x.invoice_no):""):"شارع"}</span> <span class="tag">${esc((CF_PAY.find(p=>p[0]==x.method)||[0,x.method])[1])}</span>${x.status=="void"?` <span class="tag" style="color:var(--red)">ملغي</span>`:""}<div class="m">${cfTm(x.at)} · ${x.items.map(i=>esc(i.name)+" ×"+num(i.qty)).join("، ")}${x.note?" · "+esc(x.note):""}</div></div>${x.can_void?`<button class="btn s g" onclick="cfVoid(${x.id})">إلغاء</button>`:""}</div>`).join(""):`<p class="m">مفيش عمليات لسه.</p>`}`)}

function cfAdd(id,d){const S=C.cf,p=S.menu.find(x=>x.id==id);if(!p)return;let q=(S.cart[id]||0)+d;if(q<=0)delete S.cart[id];else{if(p.track&&q>p.stock){toast("المخزون مش كفاية");q=p.stock}if(q>99)q=99;S.cart[id]=q}cfDraw()}
async function cfSell(){const S=C.cf;if(S.busy)return;const items=Object.keys(S.cart).map(id=>({id:+id,qty:S.cart[id]}));if(!items.length)return;S.busy=1;
  const{data,error}=await sb.rpc("cafe_sell",{p_items:items,p_method:S.pay,p_invoice:null,p_note:(S.note||"").trim()||null});S.busy=0;
  if(error)return toast(error.message);
  const tot=S.menu.reduce((a,x)=>a+(S.cart[x.id]?x.price*S.cart[x.id]:0),0);S.cart={};S.note="";okFlash("تم البيع",cfm(tot));V.cafe()}
async function cfVoid(id){const why=prompt("سبب الإلغاء؟ (اختياري)");if(why===null)return;const{error}=await sb.rpc("cafe_void_sale",{p_id:id,p_reason:why||null});if(error)return toast(error.message);toast("اتلغت ✓");V.cafe()}

// ============================ لوحة الكوفي ============================
V.cafe_dash=async()=>{if(!cfAdm())return cfDeny();await bizLoad();const d=bizToday();
  put(cfHead("لوحة الكوفي","يوم "+d)+`<p class="m">بنحمّل...</p>`);
  const{data:r,error}=await cfRpc("cafe_report",{p_from:d,p_to:d});if(error)return;
  put(cfHead("لوحة الكوفي","يوم العمل "+d)+cfCards(r)+`<div class="chips"><button class="chip sel" onclick="go('cafe')">بيع سريع</button><button class="chip" onclick="go('cafe_buy')">تسجيل مشتريات</button><button class="chip" onclick="go('cafe_exp')">تسجيل مصروف</button><button class="chip" onclick="go('cafe_rep')">التقارير</button></div>`+cfLow(r)+cfTop(r))}

function cfCards(r){const k=(t,v,c)=>`<div class="cf-kpi"><span class="m">${t}</span><b ${c?`style="color:${c}"`:""}>${v}</b></div>`;
  return `<div class="cf-kpis">${k("المبيعات",cfm(r.sales))}${k("عملاء الصالون",cfm(r.salon_sales))}${k("الشارع",cfm(r.street_sales))}${k("عدد الطلبات",num(r.orders))}${k("تكلفة المباع",cfm(r.cogs))}${k("المصروفات",cfm(r.expenses))}${k("المشتريات (للمعلومية)",cfm(r.purchases))}${k("صافي الربح",cfm(r.net_profit),r.net_profit<0?"var(--red)":"var(--ok)")}</div><p class="m">صافي الربح = المبيعات − تكلفة المباع − المصروفات. المشتريات مش بتتخصم تاني عشان تكلفتها اتحسبت وقت البيع.</p>`}
const cfLow=r=>(r.low_stock||[]).length?`<h3 class="sec">⚠ مخزون قليل</h3>${r.low_stock.map(x=>`<div class="box cf-rec"><b>${esc(x.name)}</b><span class="tag" style="color:var(--red)">باقي ${num(x.stock)} (الحد ${num(x.min)})</span></div>`).join("")}`:"";
const cfTop=r=>(r.top||[]).length?`<h3 class="sec">الأكتر مبيعًا</h3>`+tbl(["المنتج","الكمية","الإيراد"],r.top.map(x=>[esc(x.name),num(x.qty),cfm(x.revenue)])):"";

// ============================ المنتجات ============================
V.cafe_prods=async()=>{if(!cfAdm())return cfDeny();
  const d=ymd(new Date()),{data,error}=await cfRpc("cafe_admin_lists",{p_from:d,p_to:d});if(error)return;C.cfa=C.cfa||{};C.cfa.products=data.products||[];cfpDraw()};

function cfpDraw(){const P=C.cfa.products,row=(p)=>{const id=p?p.id:"new",v=(k,d)=>p?p[k]:d;return `<div class="box cf-prod" id="cfp_${id}">
  <input id="cfp_n_${id}" placeholder="اسم المنتج" value="${esc(v("name",""))}">
  <div class="cf-two"><label class="m">سعر البيع<input id="cfp_p_${id}" type="number" inputmode="decimal" min="0" step="0.5" value="${v("price","")}"></label><label class="m">التكلفة<input id="cfp_c_${id}" type="number" inputmode="decimal" min="0" step="0.01" value="${v("cost",0)}"></label></div>
  <div class="cf-two"><label class="m"><input id="cfp_t_${id}" type="checkbox" ${v("track_stock",false)?"checked":""}> تتبّع المخزون</label><label class="m">الحد الأدنى<input id="cfp_m_${id}" type="number" min="0" value="${v("min_stock",0)}"></label></div>
  <label class="m"><input id="cfp_a_${id}" type="checkbox" ${v("active",true)?"checked":""}> ظاهر في البيع</label>
  ${p&&p.track_stock?`<div class="m">المخزون الحالي: <b>${num(p.stock)}</b> <button class="btn s g" onclick="cfpStock(${p.id})">تسوية مخزون</button></div>`:""}
  <button class="btn s" onclick="cfpSave('${id}')">${p?"حفظ":"إضافة المنتج"}</button></div>`};
  put(cfHead("المنتجات والأسعار")+`<p class="m">التكلفة بتتسجّل وقت البيع، فتعديلها مش بيغيّر عمليات قديمة.</p><h3 class="sec">منتج جديد</h3>${row(null)}<h3 class="sec">المنتجات</h3>${P.map(row).join("")||`<p class="m">مفيش منتجات.</p>`}`)}

async function cfpSave(id){const g=k=>$("cfp_"+k+"_"+id),n=g("n").value.trim(),p=parseFloat(g("p").value),c=parseFloat(g("c").value||0);if(!n)return toast("اكتب اسم المنتج");if(!(p>=0))return toast("اكتب السعر");if(!(c>=0))return toast("التكلفة غير صحيحة");
  const{error}=await sb.rpc("cafe_save_product",{p_id:id=="new"?null:+id,p_name:n,p_price:p,p_cost:c,p_track:g("t").checked,p_min:parseInt(g("m").value||0),p_active:g("a").checked,p_sort:id=="new"?(C.cfa.products.length+1):(C.cfa.products.find(x=>x.id==id)||{}).sort||0});
  if(error)return toast(error.message);toast("اتحفظ ✓");V.cafe_prods()}
async function cfpStock(id){const p=C.cfa.products.find(x=>x.id==id),v=prompt("اكتب الزيادة (+) أو النقص (−) في مخزون "+p.name+"\nمثال: 20 أو -3");if(v===null)return;const n=parseInt(v);if(!n)return toast("اكتب رقم صحيح");const why=prompt("السبب (جرد/تالف/...)")||"تسوية";const{error}=await sb.rpc("cafe_adjust_stock",{p_id:id,p_delta:n,p_reason:why});if(error)return toast(error.message);toast("اتعدّل ✓");V.cafe_prods()}

// ============================ المشتريات والمخزون ============================
V.cafe_buy=async()=>{if(!cfAdm())return cfDeny();await bizLoad();const A=C.cfa=C.cfa||{};A.from=A.from||ymd(new Date(Date.now()-29*864e5));A.to=A.to||ymd(new Date());
  const{data,error}=await cfRpc("cafe_admin_lists",{p_from:A.from,p_to:A.to});if(error)return;A.products=data.products||[];A.purchases=data.purchases||[];A.items=A.items||[{}];A.kind=A.kind||"stock";cfbDraw()};

function cfbRead(){const A=C.cfa;if(!$("cfb_k"))return;A.kind=$("cfb_k").value;A.items=A.items.map((_,i)=>({pid:$("cfb_p_"+i)?.value||"",name:$("cfb_n_"+i)?.value||"",qty:$("cfb_q_"+i)?.value||"",cost:$("cfb_c_"+i)?.value||""}))}
function cfbDraw(){const A=C.cfa,tot=A.items.reduce((a,i)=>a+(+i.qty||0)*(+i.cost||0),0),st=A.kind=="stock";
  put(cfHead("المشتريات والمخزون")+`<section class="box"><h3 class="sec">فاتورة شراء جديدة</h3>
  <label class="m">النوع<select id="cfb_k" onchange="cfbRead();cfbDraw()"><option value="stock" ${st?"selected":""}>بضاعة / خامات (بتزوّد المخزون)</option><option value="supplies" ${st?"":"selected"}>مستلزمات (أكواب، سكر، أدوات) — بتتسجل مصروف</option></select></label>
  ${A.items.map((it,i)=>`<div class="cf-item">${st?`<select id="cfb_p_${i}" onchange="cfbRead();cfbDraw()"><option value="">بند آخر (اكتب الاسم)</option>${A.products.map(p=>`<option value="${p.id}" ${it.pid==p.id?"selected":""}>${esc(p.name)}</option>`).join("")}</select>`:""}${st&&it.pid?"":`<input id="cfb_n_${i}" placeholder="اسم البند" value="${esc(it.name||"")}" oninput="">`}<div class="cf-two"><input id="cfb_q_${i}" type="number" inputmode="decimal" min="0" step="any" placeholder="الكمية" value="${esc(it.qty||"")}" oninput="cfbTot()"><input id="cfb_c_${i}" type="number" inputmode="decimal" min="0" step="any" placeholder="سعر الوحدة" value="${esc(it.cost||"")}" oninput="cfbTot()"></div>${A.items.length>1?`<button class="btn s g" onclick="cfbRead();C.cfa.items.splice(${i},1);cfbDraw()">حذف البند</button>`:""}</div>`).join("")}
  <button class="btn s g" onclick="cfbRead();C.cfa.items.push({});cfbDraw()">+ بند</button>
  <input id="cfb_s" placeholder="المورّد (اختياري)" value="${esc(A.sup||"")}" oninput="C.cfa.sup=this.value">
  <label class="m">اتدفع من<select id="cfb_f" onchange="C.cfa.from_=this.value"><option value="drawer" ${A.from_!="other"?"selected":""}>الدرج (بيتخصم من الخزنة)</option><option value="other" ${A.from_=="other"?"selected":""}>من برّه الدرج</option></select></label>
  <input id="cfb_d" type="date" max="${ymd(new Date())}" value="${A.date||bizToday()}" onchange="C.cfa.date=this.value">
  <input id="cfb_nt" placeholder="ملاحظات" value="${esc(A.note||"")}" oninput="C.cfa.note=this.value">
  ${st?`<label class="m"><input id="cfb_uc" type="checkbox" ${A.uc?"checked":""} onchange="C.cfa.uc=this.checked"> حدّث تكلفة المنتج بسعر الشراء ده</label>`:""}
  <div class="tot f"><span>الإجمالي</span><span id="cfb_tot">${cfm(tot)}</span></div><button class="btn" style="width:100%" onclick="cfbSave()">حفظ فاتورة الشراء</button></section>
  <h3 class="sec">آخر المشتريات</h3>${A.purchases.map(p=>`<div class="box cf-rec"><div><b>${cfm(p.total)}</b> <span class="tag">${p.kind=="stock"?"بضاعة":"مستلزمات"}</span> <span class="tag">${p.paid_from=="drawer"?"من الدرج":"برّه الدرج"}</span><div class="m">${esc(p.bought_on)}${p.supplier?" · "+esc(p.supplier):""} · ${p.items.map(i=>esc(i.name)+" ×"+num(i.qty)).join("، ")}${p.note?" · "+esc(p.note):""}</div></div>${cfOwner()?`<button class="btn s g" onclick="cfbVoid(${p.id})">إلغاء</button>`:""}</div>`).join("")||`<p class="m">مفيش مشتريات في الفترة.</p>`}`)}
function cfbTot(){cfbRead();const t=C.cfa.items.reduce((a,i)=>a+(+i.qty||0)*(+i.cost||0),0),e=$("cfb_tot");if(e)e.textContent=cfm(t)}
async function cfbSave(){cfbRead();const A=C.cfa,st=A.kind=="stock",items=[];
  for(const i of A.items){const q=parseFloat(i.qty),c=parseFloat(i.cost);if(!(q>0)||!(c>=0)||i.cost==="")return toast("اكتب كمية وسعر لكل بند");const pid=st&&i.pid?+i.pid:null;if(!pid&&!(i.name||"").trim())return toast("اكتب اسم كل بند");items.push({product_id:pid,name:(i.name||"").trim(),qty:q,unit_cost:c})}
  if(A.busy)return;A.busy=1;const{error}=await sb.rpc("cafe_record_purchase",{p_date:A.date||bizToday(),p_kind:A.kind,p_items:items,p_supplier:(A.sup||"").trim()||null,p_paid_from:A.from_||"drawer",p_note:(A.note||"").trim()||null,p_update_cost:!!(st&&A.uc)});A.busy=0;
  if(error)return toast(error.message);A.items=[{}];A.sup="";A.note="";toast("اتسجلت ✓");V.cafe_buy()}
async function cfbVoid(id){if(!confirm("تلغي فاتورة الشراء دي؟ المخزون هيرجع والمصروف المرتبط هيتشال (بيتسجل في سجل المحذوفات)."))return;const{error}=await sb.rpc("cafe_void_purchase",{p_id:id});if(error)return toast(error.message);toast("اتلغت ✓");V.cafe_buy()}

// ============================ المصروفات ============================
V.cafe_exp=async()=>{if(!cfAdm())return cfDeny();await bizLoad();const A=C.cfa=C.cfa||{};A.from=A.from||ymd(new Date(Date.now()-29*864e5));A.to=A.to||ymd(new Date());
  const{data,error}=await cfRpc("cafe_admin_lists",{p_from:A.from,p_to:A.to});if(error)return;A.expenses=data.expenses||[];
  put(cfHead("مصروفات الكوفي","منفصلة عن مصروفات الصالون")+`<section class="box"><h3 class="sec">مصروف جديد</h3>
  <select id="cfe_c">${CF_CATS.map(c=>`<option>${c}</option>`).join("")}</select>
  <input id="cfe_a" type="number" inputmode="decimal" min="0" step="any" placeholder="المبلغ">
  <input id="cfe_d" type="date" max="${ymd(new Date())}" value="${bizToday()}">
  <label class="m">اتدفع من<select id="cfe_f"><option value="drawer">الدرج (بيتخصم من الخزنة)</option><option value="other">من برّه الدرج</option></select></label>
  <input id="cfe_n" placeholder="ملاحظات"><button class="btn" style="width:100%" onclick="cfeSave()">حفظ المصروف</button></section>
  <h3 class="sec">المصروفات</h3>${A.expenses.map(e=>`<div class="box cf-rec"><div><b>${cfm(e.amount)}</b> <span class="tag">${esc(e.category)}</span> <span class="tag">${e.paid_from=="drawer"?"من الدرج":"برّه الدرج"}</span>${e.purchase_id?` <span class="tag">من مشتريات</span>`:""}<div class="m">${esc(e.spent_on)}${e.note?" · "+esc(e.note):""}</div></div>${cfOwner()&&!e.purchase_id?`<button class="btn s g" onclick="cfeDel(${e.id})">مسح</button>`:""}</div>`).join("")||`<p class="m">مفيش مصروفات في الفترة.</p>`}`)};
async function cfeSave(){const a=parseFloat($("cfe_a").value);if(!(a>0))return toast("اكتب المبلغ");const{error}=await sb.rpc("cafe_add_expense",{p_date:$("cfe_d").value||bizToday(),p_category:$("cfe_c").value,p_amount:a,p_note:$("cfe_n").value.trim()||null,p_paid_from:$("cfe_f").value});if(error)return toast(error.message);toast("اتسجّل ✓");V.cafe_exp()}
async function cfeDel(id){if(!confirm("تمسح المصروف ده؟ (بيتسجل في سجل المحذوفات)"))return;const{error}=await sb.rpc("cafe_delete_expense",{p_id:id});if(error)return toast(error.message);V.cafe_exp()}

// ============================ التقارير ============================
V.cafe_rep=async()=>{if(!cfAdm())return cfDeny();await bizLoad();const R=C.cfr=C.cfr||{};if(!R.from){const t=bizToday();R.from=R.to=t;R.mode="day"}
  put(cfHead("تقارير الكوفي")+`<p class="m">بنحمّل...</p>`);const{data:r,error}=await cfRpc("cafe_report",{p_from:R.from,p_to:R.to});if(error)return;
  put(cfHead("تقارير الكوفي")+`<div class="chips">${[["day","اليوم"],["week","آخر 7 أيام"],["month","الشهر"],["custom","فترة مخصصة"]].map(x=>`<button class="chip ${R.mode==x[0]?"sel":""}" onclick="cfrMode('${x[0]}')">${x[1]}</button>`).join("")}</div>
  <div class="cf-two"><label class="m">من<input type="date" id="cfr_f" value="${R.from}" onchange="cfrCustom()"></label><label class="m">إلى<input type="date" id="cfr_t" value="${R.to}" onchange="cfrCustom()"></label></div>
  ${cfCards(r)}
  <h3 class="sec">طرق الدفع</h3>${tbl(["الطريقة","المبلغ"],CF_PAY.map(p=>[p[1],cfm(r.by_method[p[0]])]))}
  <h3 class="sec">يوم بيوم</h3>${tbl(["اليوم","المبيعات","الطلبات","التكلفة","المصروفات","المشتريات"],(r.by_day||[]).map(d=>[esc(d.day),cfm(d.sales),num(d.orders),cfm(d.cogs),cfm(d.expenses),cfm(d.purchases)]))}
  ${cfTop(r)}${(r.expenses_by_category||[]).length?`<h3 class="sec">المصروفات حسب التصنيف</h3>`+tbl(["التصنيف","المبلغ"],r.expenses_by_category.map(x=>[esc(x.category),cfm(x.amount)])):""}${cfLow(r)}`)};
function cfrMode(m){const R=C.cfr,t=bizToday(),dd=n=>ymd(new Date(new Date(t+"T12:00:00").getTime()-n*864e5));R.mode=m;if(m=="day"){R.from=R.to=t}else if(m=="week"){R.from=dd(6);R.to=t}else if(m=="month"){R.from=t.slice(0,8)+"01";R.to=t}V.cafe_rep()}
function cfrCustom(){const R=C.cfr,f=$("cfr_f").value,t=$("cfr_t").value;if(!f||!t||t<f)return toast("الفترة غير صحيحة");R.from=f;R.to=t;R.mode="custom";V.cafe_rep()}
