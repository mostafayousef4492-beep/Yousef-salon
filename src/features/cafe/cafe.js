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
.cf-deb{display:grid;gap:8px;margin:10px 0}.cf-owe{color:var(--red);font-weight:800}.cf-ok{color:var(--ok);font-weight:800}.cf-led{margin-top:8px;padding-top:8px;border-top:1px dashed var(--line)}.cf-act{display:grid;grid-template-columns:1fr auto;gap:8px;margin-top:8px}.cf-two{display:grid;grid-template-columns:1fr 1fr;gap:8px}.cf-item{border:1px dashed var(--line);border-radius:12px;padding:8px;margin:8px 0}.cf-prod{margin-bottom:10px}
`;document.head.appendChild(st)}catch(e){}})();
const cfm=n=>(+n||0).toLocaleString("ar-EG",{maximumFractionDigits:2})+" "+C.cfg.currency;
const CF_PAY=[["cash","كاش"],["card","كارت"],["wallet","محفظة"],["credit","آجل"]];
const CF_WK=[["owner","سحب للمالك"],["bank","إيداع بنك / محفظة"],["advance","سلفة من مرتبي"],["other","سبب آخر (اكتبه)"]];
const cfDig=v=>String(v||"").replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/[^\d+]/g,"");
const CF_CATS=["كهرباء","صيانة","مستلزمات","أخرى"];
// الكوفي: كاش ومحفظة وآجل بس (الكارت مش بيتعرض للبيع). الكارت لسه بيظهر في التقارير لو فيه مبيعات قديمة بيه.
const cfPays=()=>CF_PAY.filter(x=>x[0]!="card"&&(x[0]!="wallet"||C.cfg.pay_wallet_enabled!==false));
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
  const[m,r,dbt]=await Promise.all([cfRpc("cafe_menu"),cfRpc("cafe_recent_sales",{p_limit:15}),sb.rpc("cafe_debtors")]);
  if(m.error)return put(cfHead("بيع سريع")+`<p class="m">${esc(m.error.message)}<br>لو ده أول مرة، لازم patch_coffee_corner.sql يتشغّل في Supabase.</p>`);
  S.menu=m.data||[];S.recent=r.data||[];S.debtors=(dbt&&dbt.data)||[];
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
  ${S.pay=="credit"?cfDebtorPick(S):""}<input id="cf_note" placeholder="ملاحظة (اختياري)" value="${esc(S.note||"")}" oninput="C.cf.note=this.value">
  <button class="btn cf-go" ${tot?"":"disabled"} onclick="cfSell()">تسجيل البيع ${tot?"— "+cfm(tot):""}</button>${lines.length?`<button class="btn g" style="width:100%;margin-top:8px" onclick="C.cf.cart={};cfDraw()">مسح الطلب</button>`:""}</section>
  <h3 class="sec">آخر العمليات</h3>${S.recent.length?S.recent.map(x=>`<div class="box cf-rec ${x.status=="void"?"void":""}"><div><b>${cfm(x.total)}</b> <span class="tag">${x.kind=="salon"?"عميل صالون"+(x.invoice_no?" #"+esc(x.invoice_no):""):"شارع"}</span> <span class="tag">${esc((CF_PAY.find(p=>p[0]==x.method)||[0,x.method])[1])}${x.method=="credit"&&x.debtor?" — "+esc(x.debtor):""}</span>${x.status=="void"?` <span class="tag" style="color:var(--red)">ملغي</span>`:""}<div class="m">${cfTm(x.at)} · ${x.items.map(i=>esc(i.name)+" ×"+num(i.qty)).join("، ")}${x.note?" · "+esc(x.note):""}</div></div>${x.can_void?`<button class="btn s g" onclick="cfVoid(${x.id})">إلغاء</button>`:""}</div>`).join(""):`<p class="m">مفيش عمليات لسه.</p>`}`)}

function cfAdd(id,d){const S=C.cf,p=S.menu.find(x=>x.id==id);if(!p)return;let q=(S.cart[id]||0)+d;if(q<=0)delete S.cart[id];else{if(p.track&&q>p.stock){toast("المخزون مش كفاية");q=p.stock}if(q>99)q=99;S.cart[id]=q}cfDraw()}
function cfDebtorPick(S){const D=S.debtors||[];return `<div class="cf-deb"><select id="cf_deb" onchange="C.cf.deb=this.value;cfDraw()"><option value="">اختار العميل...</option>${D.map(d=>`<option value="${d.id}" ${S.deb==d.id?"selected":""}>${esc(d.name)}${+d.balance>0?" — عليه "+cfm(d.balance):""}</option>`).join("")}<option value="new" ${S.deb=="new"?"selected":""}>+ عميل جديد</option></select>${S.deb=="new"?`<input id="cf_dn" placeholder="اسم العميل" value="${esc(S.dn||"")}" oninput="C.cf.dn=this.value"><input id="cf_dp" type="tel" inputmode="numeric" placeholder="موبايل (اختياري)" value="${esc(S.dp||"")}" oninput="C.cf.dp=this.value">`:""}<div class="m">الآجل مش بيدخل الدرج لحد ما العميل يسدّد.</div></div>`}
async function cfSell(){const S=C.cf;if(S.busy)return;const items=Object.keys(S.cart).map(id=>({id:+id,qty:S.cart[id]}));if(!items.length)return;
  const args={p_items:items,p_method:S.pay,p_invoice:null,p_note:(S.note||"").trim()||null};S.busy=1;
  if(S.pay=="credit"){let deb=+S.deb||0;
    if(!S.deb){S.busy=0;return toast("اختار العميل اللي هيتسجّل عليه الآجل")}
    if(S.deb=="new"){const nm=(S.dn||"").trim();if(!nm){S.busy=0;return toast("اكتب اسم العميل")}
      const r=await sb.rpc("cafe_debtor_save",{p_name:nm,p_phone:cfDig(S.dp)||null});if(r.error){S.busy=0;return toast(r.error.message)}deb=r.data}
    args.p_debtor=deb}
  const{data,error}=await sb.rpc("cafe_sell",args);S.busy=0;
  if(error)return toast(error.message);
  const tot=S.menu.reduce((a,x)=>a+(S.cart[x.id]?x.price*S.cart[x.id]:0),0);S.cart={};S.note="";S.deb="";S.dn="";S.dp="";okFlash(S.pay=="credit"?"اتسجّل آجل":"تم البيع",cfm(tot));V.cafe()}
async function cfVoid(id,back){const why=prompt("سبب الإلغاء؟ (اختياري)");if(why===null)return;const{error}=await sb.rpc("cafe_void_sale",{p_id:id,p_reason:why||null});if(error)return toast(error.message);toast("اتلغت ✓");(back||V.cafe)()}

// ============================ لوحة الكوفي ============================
V.cafe_dash=async()=>{if(!cfAdm())return cfDeny();await bizLoad();const d=bizToday();
  put(cfHead("لوحة الكوفي","يوم "+d)+`<p class="m">بنحمّل...</p>`);
  const{data:r,error}=await cfRpc("cafe_report",{p_from:d,p_to:d});if(error)return;
  put(cfHead("لوحة الكوفي","يوم العمل "+d)+cfCards(r)+`<div class="chips"><button class="chip sel" onclick="go('cafe')">بيع سريع</button><button class="chip" onclick="go('cafe_buy')">تسجيل مشتريات</button><button class="chip" onclick="go('cafe_exp')">تسجيل مصروف</button><button class="chip" onclick="go('cafe_rep')">التقارير</button></div>`+cfLow(r)+cfDebtors(r)+cfTop(r))}

function cfCards(r){const k=(t,v,c)=>`<div class="cf-kpi"><span class="m">${t}</span><b ${c?`style="color:${c}"`:""}>${v}</b></div>`;
  return `<div class="cf-kpis">${k("المبيعات",cfm(r.sales))}${k("عملاء الصالون",cfm(r.salon_sales))}${k("الشارع",cfm(r.street_sales))}${k("عدد الطلبات",num(r.orders))}${k("تكلفة المباع",cfm(r.cogs))}${k("المصروفات",cfm(r.expenses))}${k("المشتريات (للمعلومية)",cfm(r.purchases))}${k("صافي الربح",cfm(r.net_profit),r.net_profit<0?"var(--red)":"var(--ok)")}${k("مبيعات آجل",cfm(r.credit_sales))}${k("تحصيل ديون",cfm(r.debt_collected))}${k("سحب من الدرج",cfm(r.withdrawals))}${k("ديون مستحقة (لحد دلوقتي)",cfm(r.outstanding_debt),(+r.outstanding_debt>0)?"var(--red)":"")}</div><p class="m">صافي الربح = المبيعات − تكلفة المباع − المصروفات. المشتريات مش بتتخصم تاني عشان تكلفتها اتحسبت وقت البيع. الآجل بيتحسب مبيعات وقت البيع، والتحصيل مش إيراد تاني. السحب مش مصروف (بيتخصم من الدرج بس).</p>`}
const cfLow=r=>(r.low_stock||[]).length?`<h3 class="sec">⚠ مخزون قليل</h3>${r.low_stock.map(x=>`<div class="box cf-rec"><b>${esc(x.name)}</b><span class="tag" style="color:var(--red)">باقي ${num(x.stock)} (الحد ${num(x.min)})</span></div>`).join("")}`:"";
const cfDebtors=r=>(r.top_debtors||[]).length?`<h3 class="sec">ديون مستحقة</h3>`+tbl(["العميل","المتبقي"],r.top_debtors.map(x=>[esc(x.name),`<b class="cf-owe">${cfm(x.balance)}</b>`])):"";
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
V.cafe_exp=async()=>{if(!cfAdm())return cfExpStaff();await bizLoad();const A=C.cfa=C.cfa||{};A.from=A.from||ymd(new Date(Date.now()-29*864e5));A.to=A.to||ymd(new Date());
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
  <h3 class="sec">طرق الدفع</h3>${tbl(["الطريقة","المبلغ"],CF_PAY.filter(p=>p[0]!="card"||+r.by_method[p[0]]).map(p=>[p[1],cfm(r.by_method[p[0]])]))}
  <h3 class="sec">يوم بيوم</h3>${tbl(["اليوم","المبيعات","الطلبات","التكلفة","المصروفات","المشتريات"],(r.by_day||[]).map(d=>[esc(d.day),cfm(d.sales),num(d.orders),cfm(d.cogs),cfm(d.expenses),cfm(d.purchases)]))}
  ${cfTop(r)}${(r.withdrawals_by_kind||[]).length?`<h3 class="sec">السحب حسب النوع</h3>`+tbl(["النوع","المبلغ"],r.withdrawals_by_kind.map(x=>[esc((CF_WK.find(w=>w[0]==x.kind)||[0,x.kind])[1]),cfm(x.amount)])):""}${cfDebtors(r)}${(r.expenses_by_category||[]).length?`<h3 class="sec">المصروفات حسب التصنيف</h3>`+tbl(["التصنيف","المبلغ"],r.expenses_by_category.map(x=>[esc(x.category),cfm(x.amount)])):""}${cfLow(r)}`)};
function cfrMode(m){const R=C.cfr,t=bizToday(),dd=n=>ymd(new Date(new Date(t+"T12:00:00").getTime()-n*864e5));R.mode=m;if(m=="day"){R.from=R.to=t}else if(m=="week"){R.from=dd(6);R.to=t}else if(m=="month"){R.from=t.slice(0,8)+"01";R.to=t}V.cafe_rep()}
function cfrCustom(){const R=C.cfr,f=$("cfr_f").value,t=$("cfr_t").value;if(!f||!t||t<f)return toast("الفترة غير صحيحة");R.from=f;R.to=t;R.mode="custom";V.cafe_rep()}

// ============================ شاشات موظف الكوفي (موبايل): مصروف، سحب، آجل، حركة اليوم ============================
// الصلاحيات الحقيقية في القاعدة (can_use_cafe). الموظف بيشوف ويسجّل اللي هو سجّله في يوم العمل الحالي بس.
const cfUndoBtn=(fn,id,back)=>`<button class="btn s g" onclick="cfUndo('${fn}',${id},'${back}')">تراجع</button>`;
async function cfUndo(fn,id,back){if(!confirm("متأكد؟"))return;const map={cafe_delete_expense:"p_id",cafe_void_withdrawal:"p_id",cafe_void_collection:"p_id"};const{error}=await sb.rpc(fn,{[map[fn]]:id});if(error)return toast(error.message);toast("اتراجع ✓");V[back]()}
async function cfDay(){const{data,error}=await cfRpc("cafe_staff_day");if(error)return null;C.cfs=data;return data}
const cfSum=a=>a.reduce((t,x)=>t+(+x.amount||0),0);

// ---- مصروف الموظف ----
async function cfExpStaff(){put(cfHead("مصروف","يوم العمل")+`<p class="m">بنحمّل...</p>`);const d=await cfDay();if(!d)return;
  const S=C.cfx=C.cfx||{cat:CF_CATS[0]};
  put(cfHead("مصروف جديد","يوم العمل "+esc(d.day)+" — بيتخصم من الدرج")+`<section class="box"><div class="chips">${CF_CATS.map(c=>`<button class="chip ${S.cat==c?"sel":""}" onclick="C.cfx.cat='${c}';cfExpStaff()">${c}</button>`).join("")}</div>
  <input id="cfx_a" type="number" inputmode="decimal" min="0" step="any" placeholder="المبلغ"><input id="cfx_n" placeholder="ملاحظة (إيه اللي اتشرى؟)">
  <button class="btn cf-go" onclick="cfExpStaffSave()">حفظ المصروف</button></section>
  <h3 class="sec">مصروفات النهارده — ${cfm(cfSum(d.expenses))}</h3>${d.expenses.map(e=>`<div class="box cf-rec"><div><b>${cfm(e.amount)}</b> <span class="tag">${esc(e.category)}</span><div class="m">${cfTm(e.at)}${e.note?" · "+esc(e.note):""}</div></div>${e.can_void?cfUndoBtn("cafe_delete_expense",e.id,"cafe_exp"):""}</div>`).join("")||`<p class="m">مفيش مصروفات لسه.</p>`}`)}
async function cfExpStaffSave(){const a=parseFloat($("cfx_a").value);if(!(a>0))return toast("اكتب المبلغ");const S=C.cfx;if(S.busy)return;
  if(!confirm("تسجّل مصروف "+cfm(a)+" ("+S.cat+") من الدرج؟"))return;S.busy=1;
  const{error}=await sb.rpc("cafe_add_expense",{p_date:null,p_category:S.cat,p_amount:a,p_note:$("cfx_n").value.trim()||null,p_paid_from:"drawer"});S.busy=0;
  if(error)return toast(error.message);okFlash("اتسجّل المصروف",cfm(a));cfExpStaff()}

// ---- سحب من الدرج ----
V.cafe_mv=async()=>{if(!canCafe())return cfDeny();put(cfHead("سحب من الدرج")+`<p class="m">بنحمّل...</p>`);const d=await cfDay();if(!d)return;
  const S=C.cfw=C.cfw||{kind:"owner"},ks=CF_WK.filter(k=>k[0]!="advance"||(me&&me.role!="owner"));if(!ks.some(k=>k[0]==S.kind))S.kind=ks[0][0];
  put(cfHead("سحب من الدرج","يوم العمل "+esc(d.day))+`<section class="box"><div class="chips">${ks.map(k=>`<button class="chip ${S.kind==k[0]?"sel":""}" onclick="C.cfw.kind='${k[0]}';V.cafe_mv()">${k[1]}</button>`).join("")}</div>
  <input id="cfw_a" type="number" inputmode="decimal" min="0" step="any" placeholder="المبلغ"><input id="cfw_n" placeholder="${S.kind=="other"?"السبب (مطلوب)":"ملاحظة (اختياري)"}">
  <button class="btn cf-go" onclick="cfWithdraw()">تسجيل السحب</button><p class="m">السلفة بتتخصم من مرتبك. باقي الأنواع بتنزل من كاش الدرج وتظهر للمالك في الخزنة.</p></section>
  <h3 class="sec">سحب النهارده — ${cfm(cfSum(d.withdrawals))}</h3>${d.withdrawals.map(w=>`<div class="box cf-rec"><div><b>${cfm(w.amount)}</b> <span class="tag">${esc((CF_WK.find(k=>k[0]==w.kind)||[0,w.kind])[1])}</span><div class="m">${cfTm(w.at)}${w.note?" · "+esc(w.note):""}</div></div>${w.can_void?cfUndoBtn("cafe_void_withdrawal",w.id,"cafe_mv"):""}</div>`).join("")||`<p class="m">مفيش سحب لسه.</p>`}`)};
async function cfWithdraw(){const S=C.cfw,a=parseFloat($("cfw_a").value),n=$("cfw_n").value.trim();if(!(a>0))return toast("اكتب المبلغ");if(S.kind=="other"&&!n)return toast("اكتب السبب");if(S.busy)return;
  if(!confirm("تسحب "+cfm(a)+" ("+(CF_WK.find(k=>k[0]==S.kind)||[0,""])[1]+") من الدرج؟"))return;S.busy=1;
  const{error}=await sb.rpc("cafe_add_withdrawal",{p_kind:S.kind,p_amount:a,p_note:n||null});S.busy=0;
  if(error)return toast(error.message);okFlash("اتسجّل السحب",cfm(a));V.cafe_mv()}

// ---- الآجل ----
V.cafe_debt=async()=>{if(!canCafe())return cfDeny();put(cfHead("الآجل")+`<p class="m">بنحمّل...</p>`);const{data,error}=await cfRpc("cafe_debtors");if(error)return;
  const D=C.cfd=C.cfd||{led:{},open:null};D.list=data||[];cfDebtDraw()};
function cfDebtDraw(){const D=C.cfd,owe=D.list.filter(x=>+x.balance>0),rest=D.list.filter(x=>!(+x.balance>0)),tot=owe.reduce((t,x)=>t+(+x.balance),0);
  const card=x=>{const open=D.open==x.id,L=D.led[x.id];return `<div class="box"><div class="cf-rec" style="margin:0"><div><b>${esc(x.name)}</b>${x.phone?` <span class="m">${esc(x.phone)}</span>`:""}<div class="m">${x.last_at?"آخر حركة "+cfTm(x.last_at):"لسه مفيش حركة"}</div></div><b class="${+x.balance>0?"cf-owe":"cf-ok"}">${+x.balance>0?cfm(x.balance):"مسدّد ✓"}</b></div>
  ${+x.balance>0?`<div class="cf-act"><input id="cfd_a_${x.id}" type="number" inputmode="decimal" min="0" step="any" placeholder="المبلغ المحصّل (كاش)"><button class="btn s" onclick="cfCollect(${x.id})">تحصيل</button></div><button class="btn s g" style="margin-top:6px" onclick="cfFill(${x.id},${+x.balance})">تحصيل الكل (${cfm(x.balance)})</button>`:""}
  <button class="btn s g" style="margin-top:6px;width:100%" onclick="cfLed(${x.id})">${open?"إخفاء كشف الحساب":"كشف الحساب"}</button>
  ${open&&L?`<div class="cf-led">${L.entries.map(e=>`<div class="cf-rec ${e.status=="void"?"void":""}"><div><b>${cfm(e.amount)}</b> <span class="tag">${e.type=="sale"?"آجل":"تحصيل"}</span>${e.status=="void"?` <span class="tag" style="color:var(--red)">ملغي</span>`:""}<div class="m">${cfTm(e.at)}${e.items?" · "+e.items.map(i=>esc(i.name)+" ×"+num(i.qty)).join("، "):""}${e.note?" · "+esc(e.note):""}</div></div>${e.can_void?`<button class="btn s g" onclick="${e.type=="sale"?`cfVoid(${e.id},cfDebtReload)`:`cfUndo('cafe_void_collection',${e.id},'cafe_debt')`}">إلغاء</button>`:""}</div>`).join("")||`<p class="m">مفيش حركات.</p>`}</div>`:""}</div>`};
  put(cfHead("الآجل","الإجمالي المستحق: "+cfm(tot))+`<details class="box"><summary><b>+ عميل جديد</b></summary><input id="cfd_n" placeholder="اسم العميل"><input id="cfd_p" type="tel" inputmode="numeric" placeholder="موبايل (اختياري)"><button class="btn s" onclick="cfDebtAdd()">إضافة</button></details>
  <h3 class="sec">عليهم فلوس (${num(owe.length)})</h3>${owe.map(card).join("")||`<p class="m">مفيش ديون.</p>`}
  ${rest.length?`<details><summary class="sec" style="cursor:pointer">عملاء مسدّدين (${num(rest.length)})</summary>${rest.map(card).join("")}</details>`:""}
  <p class="m">البيع الآجل بيتسجّل من "بيع سريع" باختيار "آجل". التحصيل كاش بس وبيدخل الدرج.</p>`)}
const cfDebtReload=()=>{const id=C.cfd&&C.cfd.open;V.cafe_debt().then(()=>{if(id)cfLed(id,true)})};
function cfFill(id,b){const e=$("cfd_a_"+id);if(e)e.value=b}
async function cfDebtAdd(){const n=$("cfd_n").value.trim();if(!n)return toast("اكتب اسم العميل");const{error}=await sb.rpc("cafe_debtor_save",{p_name:n,p_phone:cfDig($("cfd_p").value)||null});if(error)return toast(error.message);toast("اتضاف ✓");V.cafe_debt()}
async function cfLed(id,keep){const D=C.cfd;if(D.open==id&&!keep){D.open=null;return cfDebtDraw()}const{data,error}=await cfRpc("cafe_debtor_ledger",{p_id:id});if(error)return;D.led[id]=data;D.open=id;cfDebtDraw()}
async function cfCollect(id){const a=parseFloat($("cfd_a_"+id).value);if(!(a>0))return toast("اكتب المبلغ");const D=C.cfd;if(D.busy)return;const x=D.list.find(v=>v.id==id)||{};
  if(!confirm("تحصّل "+cfm(a)+" كاش من "+(x.name||"العميل")+"؟"))return;D.busy=1;
  const{data,error}=await sb.rpc("cafe_collect_debt",{p_debtor:id,p_amount:a,p_note:null});D.busy=0;
  if(error)return toast(error.message);okFlash("تم التحصيل","باقي "+cfm(data&&data.balance));D.open=null;V.cafe_debt()}

// ---- حركة اليوم ----
V.cafe_day=async()=>{if(!canCafe())return cfDeny();put(cfHead("حركة اليوم")+`<p class="m">بنحمّل...</p>`);const d=await cfDay();if(!d)return;const s=d.sales||{},k=(t,v,c)=>`<div class="cf-kpi"><span class="m">${t}</span><b ${c?`style="color:${c}"`:""}>${v}</b></div>`;
  put(cfHead("حركة اليوم","يوم العمل "+esc(d.day)+(d.scope=="all"?" — كل الموظفين":" — اللي سجلته أنت"))+`<div class="cf-kpis">${k("عدد الطلبات",num(s.orders))}${k("بيع كاش",cfm(s.cash))}${+(s.card||0)?k("بيع كارت",cfm(s.card)):""}${k("بيع محفظة",cfm(s.wallet))}${k("بيع آجل",cfm(s.credit),+s.credit>0?"var(--red)":"")}${k("تحصيل آجل",cfm(cfSum(d.collections)))}${k("مصروفات",cfm(cfSum(d.expenses)))}${k("سحب",cfm(cfSum(d.withdrawals)))}</div>
  <h3 class="sec">تحصيل آجل</h3>${d.collections.map(p=>`<div class="box cf-rec"><div><b>${cfm(p.amount)}</b> <span class="tag">${esc(p.debtor)}</span><div class="m">${cfTm(p.at)}</div></div>${p.can_void?cfUndoBtn("cafe_void_collection",p.id,"cafe_day"):""}</div>`).join("")||`<p class="m">مفيش.</p>`}
  <h3 class="sec">مصروفات</h3>${d.expenses.map(e=>`<div class="box cf-rec"><div><b>${cfm(e.amount)}</b> <span class="tag">${esc(e.category)}</span><div class="m">${cfTm(e.at)}${e.note?" · "+esc(e.note):""}</div></div>${e.can_void?cfUndoBtn("cafe_delete_expense",e.id,"cafe_day"):""}</div>`).join("")||`<p class="m">مفيش.</p>`}
  <h3 class="sec">سحب</h3>${d.withdrawals.map(w=>`<div class="box cf-rec"><div><b>${cfm(w.amount)}</b> <span class="tag">${esc((CF_WK.find(k=>k[0]==w.kind)||[0,w.kind])[1])}</span><div class="m">${cfTm(w.at)}${w.note?" · "+esc(w.note):""}</div></div>${w.can_void?cfUndoBtn("cafe_void_withdrawal",w.id,"cafe_day"):""}</div>`).join("")||`<p class="m">مفيش.</p>`}`)};

// ============================ شاشة موظف الكوفي الرئيسية: ترحيب + حضور/انصراف + مبيعاتي وسحوباتي ============================
if(typeof IC!=="undefined"&&!IC.cafe_me)IC.cafe_me=IC.me;
V.cafe_me=async()=>{if(!canCafe())return cfDeny();C.reload=()=>V.cafe_me();await bizLoad();
  const[dr,op]=await Promise.all([cfRpc("cafe_staff_day"),can("use_attendance")?sb.from("attendance").select("id,check_in").eq("staff_id",me.id).is("check_out",null).order("check_in",{ascending:false}).limit(1):{data:[]}]);
  const d=dr.data;if(!d)return put(cfHead("شاشتي")+`<p class="m">مقدرناش نحمّل بيانات اليوم.</p>`);
  const hr=new Date().getHours(),gr=hr>=5&&hr<12?"صباح الخير":"مساء الخير",first=String(me.full_name||"").trim().split(/\s+/)[0]||"",
  hm=t=>new Date(t).toLocaleTimeString("ar-EG",{hour:"2-digit",minute:"2-digit",hourCycle:"h23"}),
  s=d.sales||{},ws=d.withdrawals||[],es=d.expenses||[],cl=d.collections||[],open=(op.data||[])[0];
  const row=(l,v)=>`<div style="display:flex;justify-content:space-between;padding:4px 0"><span>${l}</span><b>${v}</b></div>`;
  put(cfHead(gr+" يا "+esc(first),"أهلاً بيك في الكوفي كورنر ☕ — يوم العمل "+esc(d.day))
   +(can("use_attendance")?`<div class="box" style="margin:10px 0;text-align:center">${open?`<div class="m" style="margin-bottom:6px">حاضر من ${hm(open.check_in)}</div><button class="btn" style="width:100%" onclick="att('check_out')">تسجيل انصراف</button>`:`<button class="btn" style="width:100%;background:var(--ok)" onclick="att('check_in')">تسجيل حضور</button>`}</div>`:"")
   +`<button class="btn" style="width:100%;margin:6px 0" onclick="go('cafe')">☕ بيع سريع</button>`
   +`<h3 class="sec">مبيعاتي النهارده</h3><div class="box">${row("عدد الطلبات",num(s.orders||0))}${row("كاش",cfm(s.cash))}${+s.card?row("كارت (قديم)",cfm(s.card)):""}${row("محفظة",cfm(s.wallet))}${row("آجل",cfm(s.credit))}${row("الإجمالي",cfm((+s.cash||0)+(+s.card||0)+(+s.wallet||0)+(+s.credit||0)))}</div>`
   +`<h3 class="sec">سحوباتي النهارده</h3><div class="box">${ws.length?ws.map(w=>row(esc((CF_WK.find(k=>k[0]==w.kind)||[0,w.kind])[1])+" · "+hm(w.at),cfm(w.amount))).join("")+row("الإجمالي",cfm(cfSum(ws))):`<div class="m">مفيش سحوبات النهارده.</div>`}</div>`
   +`<h3 class="sec">مصروفاتي النهارده</h3><div class="box">${es.length?es.map(w=>row(esc(w.category||"مصروف")+" · "+hm(w.at),cfm(w.amount))).join("")+row("الإجمالي",cfm(cfSum(es))):`<div class="m">مفيش مصروفات النهارده.</div>`}</div>`
   +(cl.length?`<h3 class="sec">تحصيل آجل النهارده</h3><div class="box">${row("الإجمالي",cfm(cfSum(cl)))}</div>`:""))};
