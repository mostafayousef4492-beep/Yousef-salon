/* features/money/kpi.js — مؤشرات الخزنة */

// ---------- كروت KPI في تاب الخزنة (للمالك): دخل / سحب / مصاريف / عمولات / بضاعة / الدرج — وكل كارت بيفتح تفاصيله ----------

const KR=[["today","اليوم"],["yesterday","أمس"],["week","7 أيام"],["month","الشهر"],["lastmonth","الشهر اللي فات"]];

const sumOf=(a,f)=>(a||[]).reduce((s,x)=>s+(+f(x)||0),0);

async function loadKpi(){const k=C.kr||"today",[a,b]=rangeR(k),e=new Date(b);e.setDate(e.getDate()-1);const f=ymd(a),t=ymd(e),A=a.toISOString(),B=b.toISOString();
  const[{data:dr,error},{data:st},{data:adv},{data:mv},{data:ex},{data:gp},{data:rd}]=await Promise.all([
    sb.rpc("drawer_range",{p_from:f,p_to:t}),
    sb.from("profiles").select("id,full_name,role").in("role",["barber","assistant","cashier"]).order("full_name"),
    sb.from("staff_transactions").select("staff_id,amount,note,created_at,profiles(full_name)").eq("kind","advance").gte("created_at",A).lt("created_at",B).order("created_at",{ascending:false}),
    sb.from("cash_moves").select("*").eq("kind","withdraw").gte("day",f).lte("day",t).order("day",{ascending:false}),
    sb.from("expenses").select("*").gte("spent_on",f).lte("spent_on",t).order("spent_on",{ascending:false}),
    sb.from("purchases").select("*,suppliers(name),purchase_items(name,qty)").eq("kind","stock").gte("bought_on",f).lte("bought_on",t).order("bought_on",{ascending:false}),
    sb.rpc("report_data",{p_from:A,p_to:B})]);
  if(error)return{error};
  const sums=await Promise.all((st||[]).filter(s=>s.role=="barber").map(s=>sb.rpc("staff_summary",{p_staff:s.id,p_from:A,p_to:B})));
  const bars=(st||[]).filter(s=>s.role=="barber").map((s,i)=>{const m=sums[i].data?.[0]||{};return{id:s.id,n:s.full_name,sales:+m.sales||0,cuts:+m.cuts||0,comm:+m.commission||0,adv:+m.advances||0,assist:+m.assistant_cuts||0}});
  return{k,f,t,A,B,dr,adv:adv||[],mv:mv||[],ex:ex||[],gp:gp||[],bars,cogs:+rd?.totals?.cogs||0}}

async function showKpi(){const box=$("kpi");if(!box)return;C.kp=await loadKpi();if(!$("kpi"))return;
  if(C.kp.error)return $("kpi").innerHTML=`<p class="m">${esc(C.kp.error.message)} — شغّل patch10.sql في Supabase الأول.</p>`;drawKpi()}

function kpiCards(P){const d=P.dr,wd=sumOf(P.adv,x=>x.amount)+sumOf(P.mv,x=>x.amount),exp=sumOf(P.ex,x=>x.amount),com=sumOf(P.bars,x=>x.comm),gd=sumOf(P.gp,x=>x.total);
  return[["inc","إجمالي الدخل",+d.revenue,"var(--ok)",d.invoices+" فاتورة"],["wd","إجمالي السحب",wd,"var(--red)",P.adv.length+P.mv.length+" عملية"],["exp","إجمالي المصاريف",exp,"var(--red)",P.ex.length+" بند"],["com","عمولات الصنايعية",com,"inherit",P.bars.length+" صنايعي"],["gd","البضاعة (مشتريات)",gd,"inherit",P.gp.length+" فاتورة"],["drw","اللي في الدرج (متوقع)",+d.expected_cash,+d.expected_cash>=0?"var(--gold2)":"var(--red)","كاش بس"]]}

function drawKpi(){const P=C.kp;if(!P||!$("kpi"))return;const d=P.dr,cards=kpiCards(P),sel=C.kd;
  const row=(l,v,b,a)=>`<div ${a?`role="button" onclick="${a}"`:""} style="${a?"cursor:pointer;color:var(--gold2);":""}display:flex;justify-content:space-between;padding:4px 0;${b?"font-weight:800;border-top:1px solid var(--line);margin-top:4px":""}"><span>${l}</span><span>${v}</span></div>`;
  let det="";
  if(sel=="inc"){const bs=P.bars.slice().sort((x,y)=>y.sales-x.sales);
    det=`<h2>الدخل حسب طريقة الدفع</h2><div class="box">${row("كاش",fm(d.cash_sales),0,"dsBar(null,'cash')")}${row("كارت",fm(d.card_sales),0,"dsBar(null,'card')")}${row("محفظة",fm(d.wallet_sales),0,"dsBar(null,'wallet')")}${row("الإجمالي ("+d.invoices+" فاتورة) — اضغط للفواتير",fm(d.revenue),1,"dsAll()")}</div><h2>مين اشتغل بكام</h2>${tbl(["الصنايعي","الزباين","الشغل (مبيعات)"],bs.map(x=>[`<a href="#" style="color:var(--gold2)" onclick="dsBar('${x.id}');return false">${esc(x.n)}</a>`,x.cuts,fm(x.sales)]).concat(bs.length?[[`<b>الإجمالي</b>`,sumOf(bs,x=>x.cuts),`<b>${fm(sumOf(bs,x=>x.sales))}</b>`]]:[]))}`}
  if(sel=="wd"){const by={};P.adv.forEach(x=>{const n=x.profiles?.full_name||"—";(by[n]=by[n]||{n,c:0,t:0});by[n].c++;by[n].t+=+x.amount});
    det=`<h2>سحب الموظفين (سلف) — مين سحب كام</h2>${tbl(["الاسم","مرات","إجمالي السحب"],Object.values(by).sort((x,y)=>y.t-x.t).map(x=>[esc(x.n),x.c,fm(x.t)]).concat(P.adv.length?[[`<b>الإجمالي</b>`,P.adv.length,`<b>${fm(sumOf(P.adv,x=>x.amount))}</b>`]]:[]))}<h2>تفاصيل السلف</h2>${P.adv.map(x=>`<div class="row"><div><b>${esc(x.profiles?.full_name||"—")}</b> · ${fm(x.amount)}<div class="m">${new Date(x.created_at).toLocaleString("ar-EG")}${x.note?" · "+esc(x.note):""}</div></div></div>`).join("")||`<p class="m">مفيش سلف في الفترة دي.</p>`}<h2>سحب من الدرج (مالك / إيداع بنك)</h2>${P.mv.map(x=>`<div class="row"><div><b>${fm(x.amount)}</b><div class="m">${x.day}${x.note?" · "+esc(x.note):""}</div></div></div>`).join("")||`<p class="m">مفيش سحب من الدرج في الفترة دي.</p>`}`}
  if(sel=="exp"){const by={};P.ex.forEach(x=>by[x.category]=(by[x.category]||0)+ +x.amount);
    det=`<h2>المصاريف حسب البند</h2>${tbl(["البند","الإجمالي"],Object.entries(by).sort((x,y)=>y[1]-x[1]).map(([c,t])=>[esc(c),fm(t)]).concat(P.ex.length?[[`<b>الإجمالي</b>`,`<b>${fm(sumOf(P.ex,x=>x.amount))}</b>`]]:[]))}<h2>التفاصيل</h2>${P.ex.map(x=>`<div class="row"><div><b>${esc(x.category)}</b> · ${fm(x.amount)}<div class="m">${x.spent_on}${x.note?" · "+esc(x.note):""}${x.purchase_id?" · من فاتورة شراء":""}${x.paid_from=="other"?" · من برا الدرج":""}</div></div></div>`).join("")||`<p class="m">مفيش مصاريف في الفترة دي.</p>`}`}
  if(sel=="com"){const bs=P.bars.slice().sort((x,y)=>y.comm-x.comm);
    det=`<h2>الشغل − السحب = الباقي لكل صنايعي</h2>${tbl(["الصنايعي","الشغل","العمولة","السحب","الباقي"],bs.map(x=>[`<a href="#" style="color:var(--gold2)" onclick="dsBar('${x.id}');return false">${esc(x.n)}</a>`,fm(x.sales),fm(x.comm),fm(x.adv),`<b style="color:${x.comm-x.adv>=0?"var(--ok)":"var(--red)"}">${fm(x.comm-x.adv)}</b>`]).concat(bs.length?[[`<b>الإجمالي</b>`,`<b>${fm(sumOf(bs,x=>x.sales))}</b>`,`<b>${fm(sumOf(bs,x=>x.comm))}</b>`,`<b>${fm(sumOf(bs,x=>x.adv))}</b>`,`<b>${fm(sumOf(bs,x=>x.comm-x.adv))}</b>`]]:[]))}<div class="m" style="margin-top:6px">الباقي = العمولة − السحب. العمولة محسوبة بعد خصم نسبة المساعدين${sumOf(bs,x=>x.assist)?" ("+fm(sumOf(bs,x=>x.assist))+" في الفترة دي)":""}. المكافآت والخصومات والرواتب الثابتة في تاب المالية ← الرواتب.</div>`}
  if(sel=="gd"){const tot=sumOf(P.gp,x=>x.total),pd=sumOf(P.gp,x=>x.paid);
    det=`<h2>مشتريات البضاعة</h2><div class="box">${row("إجمالي المشتريات",fm(tot))}${row("اتدفع",fm(pd))}${row("متبقي للموردين",fm(tot-pd),1)}${row("تكلفة البضاعة اللي اتباعت في الفترة",fm(P.cogs))}</div><h2>الفواتير</h2>${P.gp.map(p=>`<div class="row"><div><b>${esc(p.suppliers?.name||"بدون مورد")}</b> · ${fm(p.total)}<div class="m">${p.bought_on} · ${(p.purchase_items||[]).map(i=>esc(i.name)+" ×"+(+i.qty)).join("، ")}${+p.paid<+p.total?` · <span style="color:var(--red)">متبقي ${fm(p.total-p.paid)}</span>`:""}</div></div></div>`).join("")||`<p class="m">مفيش مشتريات بضاعة في الفترة دي.</p>`}<div class="m">مشتريات المستلزمات بتظهر في كارت المصاريف.</div>`}
  if(sel=="drw"){const L=[["رصيد أول الفترة (آخر قفل قبلها)",+d.opening],["مبيعات كاش",+d.cash_sales],["مصاريف من الدرج",-d.exp_cash],["مشتريات كاش",-d.pur_cash],["تسديد موردين",-d.sup_cash],["رواتب مصروفة",-d.sal_cash],["سحب موظفين (سلف)",-d.adv_cash],["سحب من الدرج",-d.moves_out],["إضافة للدرج",+d.moves_in]].filter(r=>+r[1]||r[0].startsWith("رصيد"));
    det=`<h2>إزاي طلع اللي في الدرج؟</h2><div class="box">${L.map(r=>row(r[0],fm(r[1]))).join("")}${row("المتوقع في الدرج",fm(d.expected_cash),1)}</div><div class="m" style="margin-top:6px">الكارت والمحفظة (${fm(+d.card_sales+ +d.wallet_sales)}) مش داخلين في الدرج. الحساب بيبدأ من الكاش اللي اتعدّ في آخر قفل قبل الفترة، ولو مفيش قفل بيبدأ من صفر.</div>`}
  $("kpi").innerHTML=`<div class="chips">${KR.map(x=>`<button class="chip ${P.k==x[0]?"sel":""}" onclick="C.kr='${x[0]}';C.kd=null;V.cash()">${x[1]}</button>`).join("")}</div><div class="m" style="margin:2px 0 8px">${P.f==P.t?P.f:P.f+" ← "+P.t}</div><div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">${cards.map(c=>`<button class="box" style="text-align:center;cursor:pointer;margin:0;width:100%;${sel==c[0]?"border-color:var(--gold2);box-shadow:0 0 0 1px var(--gold2) inset":""}" onclick="C.kd=C.kd=='${c[0]}'?null:'${c[0]}';drawKpi()"><div class="m">${c[1]}</div><div style="font-weight:800;font-size:19px;color:${c[3]}">${fm(c[2])}</div><div class="m" style="font-size:11px">${c[4]} · ${sel==c[0]?"اضغط للإغلاق":"اضغط للتفاصيل"}</div></button>`).join("")}</div>${det}`}
