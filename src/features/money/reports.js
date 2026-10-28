/* features/money/reports.js — التقارير */

const RSEC=[["sum","الملخص"],["daily","يوم بيوم"],["sales","المبيعات"],["staff","الموظفين"],["cust","العملاء"],["queue","الدور والتقييم"],["stock","المخزون"],["exp","المصروفات"]];

function rangeR(k){const a=new Date();a.setHours(0,0,0,0);const b=new Date(a);b.setDate(b.getDate()+1);const t=new Date();
if(k=="yesterday"){a.setDate(a.getDate()-1);b.setDate(b.getDate()-1)}else if(k=="week")a.setDate(a.getDate()-6);else if(k=="month")a.setDate(1);
else if(k=="lastmonth"){a.setFullYear(t.getFullYear(),t.getMonth()-1,1);b.setFullYear(t.getFullYear(),t.getMonth(),1)}
else if(k=="custom"&&C.rf&&C.rt){const x=new Date(C.rf+"T00:00"),y=new Date(C.rt+"T00:00");y.setDate(y.getDate()+1);return[x,y]}
return[a,b]}

V.rep=async()=>{C.rk=C.rk||"month";C.rs=C.rs||(isAdm(me)?"full":"sum");const{data:xc}=await sb.from("expense_categories").select("name").eq("active",true).order("id");C.xcats=(xc||[]).map(x=>x.name);repLoad()};

async function repLoad(){C.rl=null;const[a,b]=rangeR(C.rk);const[{data,error},{data:ex}]=await Promise.all([sb.rpc("report_data",{p_from:a.toISOString(),p_to:b.toISOString()}),sb.from("expenses").select("*").gte("spent_on",ymd(a)).lt("spent_on",ymd(b)).order("spent_on",{ascending:false})]);
if(error)return put(`<h1>التقارير</h1><p class="m">${esc(error.message)}</p>`);C.rd=data;C.rx=ex||[];C.rr=[a,b];drawRep()}

function drawRep(){const d=C.rd,T=d.totals,[a,b]=C.rr,e=new Date(b);e.setDate(e.getDate()-1);
const RK=[["today","اليوم"],["yesterday","أمس"],["week","7 أيام"],["month","الشهر"],["lastmonth","الشهر اللي فات"],["custom","مخصص"]];
let h=`<h1>التقارير</h1><div class="chips">${RK.map(x=>`<button class="chip ${C.rk==x[0]?"sel":""}" onclick="C.rk='${x[0]}';repLoad()">${x[1]}</button>`).join("")}</div>${C.rk=="custom"?`<div class="chips" style="align-items:center"><input type="date" id="rf" value="${C.rf||ymd(a)}" style="width:auto;margin:0"><span class="m">إلى</span><input type="date" id="rt" value="${C.rt||ymd(e)}" style="width:auto;margin:0"><button class="btn s" onclick="C.rf=$('rf').value;C.rt=$('rt').value;repLoad()">عرض</button></div>`:""}<div class="m" style="margin-bottom:6px">${ymd(a)} ← ${ymd(e)}</div><div class="chips">${(isAdm(me)?[["full","التقرير الشامل"]]:[]).concat(RSEC).map(x=>`<button class="chip ${C.rs==x[0]?"sel":""}" onclick="C.rs='${x[0]}';drawRep()">${x[1]}</button>`).join("")}</div>`;
const s=C.rs;if(s=="full")h+=`<div id="rpf"><p class="m">بنحمّل...</p></div>`;
if(s=="sum")h+=`<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">${kc("المبيعات",fm(T.revenue),"","rp('inv')")}${kc("صافي الربح",fm(T.profit),T.profit>=0?"var(--ok)":"var(--red)","rp('profit')")}${kc("عدد الفواتير",num(T.invoices),"","rp('inv')")}${kc("متوسط الفاتورة",fm(T.avg),"","rp('inv')")}${kc("الخصومات",fm(T.discounts),"","rp('disc')")}${kc("المصروفات",fm(T.expenses),"","rp('exp')")}</div>
<h2>تفاصيل كل الفواتير (الأحدث فوق)</h2><div id="rpl"><p class="m">بنحمّل...</p></div>
<h2>إزاي طلع الربح؟</h2><div class="box">${[["المبيعات",T.revenue,1],["تكلفة المنتجات المباعة",-T.cogs],["عمولات الحلاقين (بعد خصم المساعدين)",-T.commissions],["رواتب المساعدين",-(T.salaries||0)],["المكافآت",-T.bonuses],["الخصومات على الموظفين",T.deductions],["المصروفات",-T.expenses],["صافي الربح",T.profit,1]].map(r=>`<div class="tot" style="display:flex;justify-content:space-between;padding:4px 0;${r[2]?"font-weight:800":""}${PA[r[0]]?";cursor:pointer":""}"${PA[r[0]]?` role="button" onclick="${PA[r[0]]}"`:""}><span>${r[0]}${PA[r[0]]?" ›":""}</span><span>${fm(r[1])}</span></div>`).join("")}</div><div class="m" style="margin-top:6px;cursor:pointer;text-decoration:underline dotted" role="button" onclick="rp('advance')">سحب الموظفين في الفترة: ${fm(T.advances)} (بتتخصم من مستحقاتهم ومش مصروف)</div>${T.assistant_cuts?`<div class="m" style="cursor:pointer;text-decoration:underline dotted" role="button" onclick="rpSal()">حصة المحل من خدمات المساعدين في الفترة: ${fm(T.assistant_cuts)} (متحسوبة جوه المبيعات ومخصومة من عمولات الحلاقين)</div>`:""}
<h2>المبيعات يوم بيوم (اضغط على اليوم)</h2>${bars(d.by_day,x=>x.d,x=>x.t,(x,i)=>"rpDay("+i+")")}`;
if(s=="daily")h+=`<div id="rpd"><p class="m">بنحمّل...</p></div>`;
if(s=="sales")h+=`<h2>طرق الدفع</h2>${tbl(["الطريقة","الفواتير","الإجمالي"],d.by_pay.map(x=>[`<a href="#" style="color:var(--gold2)" onclick="rp('${esc(x.m)}');return false">${{cash:"كاش",card:"كارت",wallet:"محفظة"}[x.m]||esc(x.m)}</a>`,x.n,fm(x.t)]))}<h2>الخدمات</h2>${tbl(["الخدمة","العدد","الإيراد"],d.services.map((x,i)=>[ra(`rpItem('sv',${i})`,esc(x.n)),x.q,fm(x.t)]))}<h2>المنتجات</h2>${tbl(["المنتج","العدد","الإيراد","الربح"],d.products.map((x,i)=>[ra(`rpItem('pr',${i})`,esc(x.n)),x.q,fm(x.t),fm(x.p)]))}<h2>ساعات الذروة</h2>${bars(d.by_hour,x=>x.h+":00",x=>x.t,(x,i)=>"rpHour("+i+")")}`;
if(s=="staff")h+=`<h2>أداء الحلاقين</h2>${tbl(["الحلاق","الزباين","المبيعات","العمولة","التقييم"],d.barbers.map((x,i)=>[ra(`rpBar(${i})`,esc(x.n)),x.cuts,fm(x.sales),fm(x.comm),x.rating?"★ "+x.rating:"—"]))}${(d.assistants||[]).length?`<h2>المساعدين</h2>${tbl(["المساعد","خدمات","قيمتها","حصة المحل","راتب الفترة"],d.assistants.map((x,i)=>[ra(`rpAsst(${i})`,esc(x.n)),x.svc,fm(x.val),fm(x.cut),fm(x.sal)]))}`:""}<h2>الحضور</h2>${tbl(["الموظف","أيام","ساعات","تأخير (د)"],d.attendance.map((x,i)=>[ra(`rpAtt(${i})`,esc(x.n)),x.days,x.hrs,x.late]))}<h2>حركات الموظفين</h2><div style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px">${kc("مكافآت",fm(T.bonuses),"var(--ok)","rp('bonus')")}${kc("سحب",fm(T.advances),"var(--red)","rp('advance')")}${kc("خصومات",fm(T.deductions),"var(--red)","rp('deduction')")}</div>`;
if(s=="cust")h+=`<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px">${kc("كل العملاء",num(d.customers.total),"","rp('cu_all')")}${kc("جدد",num(d.customers.new),"","rp('cu_new')")}${kc("نشطين",num(d.customers.active),"","rp('cu_act')")}</div><h2>أعلى العملاء إنفاقًا</h2>${tbl(["العميل","الموبايل","الزيارات","الإنفاق"],d.customers.top.map((x,i)=>[ra(`rpCu(${i})`,esc(x.n)),esc(x.ph||""),x.v,fm(x.t)]))}<h2>الولاء</h2><div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">${kc("نقاط ممنوحة",num(d.loyalty.issued),"","rp('ly_in')")}${kc("نقاط مستبدلة",num(d.loyalty.redeemed),"","rp('ly_out')")}${kc("كوبونات مفعّلة",num(d.loyalty.active),"","rp('cp_a')")}${kc("كوبونات اتستخدمت",num(d.loyalty.used),"","rp('cp_u')")}</div>`;
if(s=="queue"){const tot=d.tickets.reduce((a,x)=>a+x.n,0),can2=(d.tickets.find(x=>x.s=="cancelled")||{n:0}).n;h+=`<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">${kc("إجمالي الحجوزات",num(tot),"","rp('ap_all')")}${kc("نسبة الإلغاء",(tot?Math.round(can2/tot*100):0)+"%","","rp('ap_can')")}</div><h2>حالات الحجز</h2>${tbl(["الحالة","العدد"],d.tickets.map((x,i)=>[ra(`rpTk(${i})`,ST[x.s]||x.s),x.n]))}<h2>الفترات</h2>${tbl(["الفترة","الحجوزات"],d.periods.map((x,i)=>[ra(`rpPer(${i})`,PLB[x.p]||x.p),x.n]))}<h2>التقييمات (${d.ratings.n})</h2><div style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px">${kc("الحلاق",d.ratings.barber?"★ "+d.ratings.barber:"—","","rp('rev')")}${kc("الخدمة",d.ratings.service?"★ "+d.ratings.service:"—","","rp('rev')")}${kc("المكان",d.ratings.place?"★ "+d.ratings.place:"—","","rp('rev')")}</div>`}
if(s=="stock")h+=`<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">${kc("قيمة المخزون (تكلفة)",fm(d.stock.cost_value),"","rp('stock')")}${kc("قيمة المخزون (بيع)",fm(d.stock.retail_value),"","rp('stock')")}</div><h2>نواقص المخزون</h2>${tbl(["المنتج","الكمية","الحد الأدنى"],d.stock.low.map((x,i)=>[ra(`rpLow(${i})`,esc(x.n)),x.q,x.min]))}`;
if(s=="exp")h+=`<h2>إضافة مصروف</h2><div class="box"><select id="xc">${(C.xcats&&C.xcats.length?C.xcats:["إيجار","كهرباء ومياه","صيانة","تسويق","أخرى"]).map(c=>`<option>${c}</option>`).join("")}</select><select id="xp">${paySrc("drawer")}</select><input id="xa" type="number" inputmode="decimal" placeholder="المبلغ"><input id="xn" placeholder="ملاحظة (اختياري)"><input id="xd" type="date" value="${bizToday()}">${isAdm(me)?`<button class="btn" onclick="addExp()">حفظ المصروف</button>`:""}</div><h2>حسب البند</h2>${tbl(["البند","الإجمالي"],d.expenses.map((x,i)=>[ra(`rpExpCat(${i})`,esc(x.c)),fm(x.t)]))}<h2>المصروفات</h2>`+(C.rx.length?C.rx.map(x=>`<div class="row"><div><b>${esc(x.category)}</b> · ${fm(x.amount)}<div class="m">${x.spent_on} ${esc(x.note||"")}${x.purchase_id?" · من فاتورة شراء":""}${x.paid_from=="other"?" · من برا الدرج":""}</div></div>${me.role=="owner"&&!x.purchase_id?`<button class="btn s" onclick="editDate('expense',${x.id},'${x.spent_on}')">تعديل التاريخ</button> <button class="btn s g" onclick="delExp(${x.id})">حذف</button>`:""}</div>`).join(""):`<p class="m">مفيش مصروفات.</p>`);
h+=`<div class="chips" style="margin-top:16px"><button class="btn g s" onclick="exportXlsx()">⬇ تصدير Excel</button>${me.role=="owner"?`<button class="btn s" onclick="exportTemplate()">📊 ملف الإكسيل الجاهز</button>`:""}<button class="btn g s" onclick="exportCsv()">⬇ الفواتير (CSV)</button><button class="btn g s" onclick="print()">🖨 طباعة</button></div>`;put(h);if(C.rs=="full")fullLoad();if(C.rs=="sum")rplLoad(0);if(C.rs=="daily")rpdLoad()}

async function addExp(){const a=+$("xa").value;if(!(a>0))return toast("اكتب المبلغ");const{error}=await sb.from("expenses").insert({category:$("xc").value,amount:a,note:$("xn").value,spent_on:$("xd").value,paid_from:$("xp")?$("xp").value:"drawer"});error?toast(error.message):(toast("تم ✓"),repLoad())}

function delExp(id){return ownerDel("expenses",id,()=>repLoad(),"حذف المصروف؟")}

async function exportCsv(){const[a,b]=C.rr;const{data}=await sb.from("invoices").select("no,created_at,total,discount,payment_method,customers(name,phone),profiles:barber_id(full_name),invoice_items(name,qty)").gte("created_at",a.toISOString()).lt("created_at",b.toISOString()).order("created_at",{ascending:false});
const q=v=>'"'+String(v??"").replace(/"/g,'""')+'"';const rows=[["رقم","التاريخ","العميل","الموبايل","الحلاق","البنود","الخصم","الإجمالي","الدفع"],...(data||[]).map(i=>[i.no,new Date(i.created_at).toLocaleString("ar-EG"),i.customers?.name||"عابر",i.customers?.phone||"",i.profiles?.full_name||"",i.invoice_items.map(z=>z.name+" x"+z.qty).join(" + "),i.discount,i.total,i.payment_method])];
const blob=new Blob(["\ufeff"+rows.map(r=>r.map(q).join(",")).join("\n")],{type:"text/csv;charset=utf-8"}),u=URL.createObjectURL(blob),l=document.createElement("a");l.href=u;l.download="invoices-"+ymd(a)+".csv";l.click();URL.revokeObjectURL(u)}

// ---- التقارير ----

const rpR=()=>({from:C.rr[0].toISOString(),to:C.rr[1].toISOString()});

async function rp(k){const R=rpR(),T=(C.rd||{}).totals||{};
  if(k=="inv")return dsInv({t:"فواتير الفترة",...R});
  if(k=="disc")return dsInv({t:"الفواتير اللي عليها خصم",...R,disc:true});
  if(PAYL[k])return dsInv({t:"فواتير "+PAYL[k],...R,pay:k});
  if(k=="profit"){const L=[["المبيعات",T.revenue,1],["تكلفة المنتجات المباعة",-T.cogs],["عمولات الحلاقين (بعد خصم المساعدين)",-T.commissions],["رواتب المساعدين",-(T.salaries||0)],["المكافآت",-T.bonuses],["الخصومات على الموظفين",T.deductions],["المصروفات",-T.expenses],["صافي الربح",T.profit,1]];
    return dsOpen("إزاي طلع صافي الربح",`<div class="box">${L.map(r=>dsKv(r[0],fm(r[1]||0),r[2])).join("")}</div>`)}
  if(k=="exp"){const X=C.rx||[];return dsOpen("مصروفات الفترة",X.length?`<div class="m" style="margin-bottom:8px">${X.length} بند · <b>${fm(sumOf(X,x=>x.amount))}</b></div>`+X.map(x=>dsRow(`<b>${esc(x.category)}</b>`,`${x.spent_on}${x.note?" · "+esc(x.note):""}`,`<b>${fm(x.amount)}</b>`)).join(""):dsEmpty("مفيش مصروفات في الفترة دي."))}
  if(k=="bonus"||k=="advance"||k=="deduction")return dsQ({bonus:"المكافآت",advance:"السحب (السلف)",deduction:"الخصومات"}[k]+" في الفترة",sb.from("staff_transactions").select("amount,note,created_at,profiles(full_name)").eq("kind",k).gte("created_at",R.from).lt("created_at",R.to).order("created_at",{ascending:false}),L=>`<div class="m" style="margin-bottom:8px">${L.length} حركة · <b>${fm(sumOf(L,x=>x.amount))}</b></div>`+L.map(x=>dsRow(`<b>${esc(x.profiles?.full_name||"—")}</b>`,dsT(x.created_at)+(x.note?" · "+esc(x.note):""),`<b>${fm(x.amount)}</b>`)).join(""));
  if(k=="cu_all"||k=="cu_new"){let q=sb.from("customers").select("id,name,phone,visits,points,created_at").order("created_at",{ascending:false}).limit(300);if(k=="cu_new")q=q.gte("created_at",R.from).lt("created_at",R.to);
    return dsQ(k=="cu_new"?"العملاء الجدد":"كل العملاء",q,L=>L.map(c=>dsCuRow({...c,sub:c.visits+" زيارة · "+dsT(c.created_at),end:`<span class="tag">${c.points} نقطة</span>`})).join(""))}
  if(k=="cu_act")return dsQ("العملاء النشطين في الفترة",sb.from("invoices").select("customer_id,total,customers(name,phone)").gte("created_at",R.from).lt("created_at",R.to).not("customer_id","is",null).limit(2000),L=>{const g={};L.forEach(x=>{const o=g[x.customer_id]=g[x.customer_id]||{id:x.customer_id,name:x.customers?.name||"—",phone:x.customers?.phone,n:0,t:0};o.n++;o.t+=+x.total});
    return Object.values(g).sort((a,b)=>b.t-a.t).map(c=>dsCuRow({...c,sub:c.n+" فاتورة",end:`<b>${fm(c.t)}</b>`})).join("")});
  if(k=="ly_in"||k=="ly_out"){let q=sb.from("loyalty_ledger").select("points,reason,note,created_at,customers(name)").gte("created_at",R.from).lt("created_at",R.to).order("created_at",{ascending:false}).limit(300);q=k=="ly_in"?q.gt("points",0):q.eq("reason","redeem");
    return dsQ(k=="ly_in"?"النقاط الممنوحة":"النقاط المستبدلة",q,L=>L.map(x=>dsRow(`<b>${esc(x.customers?.name||"—")}</b>`,dsT(x.created_at)+" · "+esc(lyT(x)||LYR[x.reason]||x.reason)+(x.note&&!lyT(x)?" · "+esc(x.note):""),`<b style="color:${x.points>0?"var(--ok)":"var(--red)"}">${x.points>0?"+":""}${x.points}</b>`)).join(""))}
  if(k=="cp_a"||k=="cp_u"){let q=sb.from("loyalty_redemptions").select("code,status,created_at,used_at,loyalty_rewards(name),customers(name)").order("created_at",{ascending:false}).limit(200);q=k=="cp_a"?q.eq("status","active"):q.eq("status","used").gte("used_at",R.from).lt("used_at",R.to);
    return dsQ(k=="cp_a"?"الكوبونات المفعّلة":"الكوبونات اللي اتستخدمت",q,L=>L.map(x=>dsRow(`<b>${esc(x.loyalty_rewards?.name||"—")}</b> · ${esc(x.customers?.name||"—")}`,`كود ${esc(x.code)} · ${dsT(x.used_at||x.created_at)}`,`<span class="tag">${x.status=="used"?"اتستخدم":"مفعّل"}</span>`)).join(""))}
  if(k=="ap_all"||k=="ap_can"){let q=sb.from("appointments").select("ticket_no,status,day,period,customers(name),profiles(full_name),appointment_services(services(name))").gte("created_at",R.from).lt("created_at",R.to).order("created_at",{ascending:false}).limit(300);if(k=="ap_can")q=q.eq("status","cancelled");
    return dsQ(k=="ap_can"?"الحجوزات الملغية":"حجوزات الفترة",q,L=>L.map(x=>dsRow(`<b>#${x.ticket_no??"-"} · ${esc(x.customers?.name||"—")}</b>`,`${x.day||""}${x.period?" · "+(PLB[x.period]||""):""} · ${(x.appointment_services||[]).map(s=>esc(s.services?.name||"")).filter(Boolean).join(" + ")||"—"}${x.profiles?.full_name?" · الحلاق: "+esc(x.profiles.full_name):""}`,`<span class="tag">${ST[x.status]||x.status}</span>`)).join(""))}
  if(k=="rev")return dsQ("تقييمات الفترة",sb.from("reviews").select("rating,service_rating,place_rating,tags,note,created_at,customers(name),profiles:barber_id(full_name)").gte("created_at",R.from).lt("created_at",R.to).order("created_at",{ascending:false}).limit(200),L=>L.map(x=>`<div class="row" style="display:block"><b style="color:var(--brass)">${"★".repeat(x.rating)}</b> <b>${esc(x.customers?.name||"—")}</b><div class="m">الحلاق: ${esc(x.profiles?.full_name||"—")} · ${dsT(x.created_at)}${x.service_rating?" · الخدمة ★"+x.service_rating:""}${x.place_rating?" · المكان ★"+x.place_rating:""}${(x.tags||[]).length?" · "+x.tags.map(esc).join("، "):""}</div>${x.note?`<div>${esc(x.note)}</div>`:""}</div>`).join(""));
  if(k=="stock")return dsQ("المخزون",sb.from("products").select("name,stock,min_stock,cost,price,active").order("name"),L=>L.map(p=>dsRow(`<b>${esc(p.name)}</b>${p.active?"":" (موقوف)"}`,`تكلفة ${fm(p.cost)} · بيع ${fm(p.price)} · قيمته ${fm(p.cost*p.stock)}`,`<span class="tag" style="${p.stock<=p.min_stock?"background:var(--red);color:#fff":""}">${p.stock} قطعة</span>`)).join(""))}

const ra=(js,t)=>`<a href="#" style="color:var(--gold2);text-decoration:underline dotted" onclick="${js};return false">${t}</a>`;

const PA={"المبيعات":"rp('inv')","تكلفة المنتجات المباعة":"rpCogs()","عمولات الحلاقين (بعد خصم المساعدين)":"rpComm()","رواتب المساعدين":"rpSal()","المكافآت":"rp('bonus')","الخصومات على الموظفين":"rp('deduction')","المصروفات":"rp('exp')","صافي الربح":"rp('profit')"};

const rpPhone=c=>dsPh()&&c&&c.phone?`<span dir="ltr">${esc(c.phone)}</span>`:"";

async function rplLoad(more){const box=$("rpl");if(!box||!C.rr)return;const[a,b]=C.rr,key=a.getTime()+"-"+b.getTime();
if(!C.rl||C.rl.k!=key)C.rl={k:key,rows:[],total:0,done:false};const L=C.rl;if(!more&&L.rows.length)return rplDraw();if(L.busy)return;L.busy=1;
const{data,error,count}=await sb.from("invoices").select("id,no,total,discount,payment_method,created_at,customers(name,phone),barber:barber_id(full_name),invoice_items(name,qty)",{count:"exact"}).gte("created_at",a.toISOString()).lt("created_at",b.toISOString()).order("created_at",{ascending:false}).range(L.rows.length,L.rows.length+99);
L.busy=0;if(error){const bx=$("rpl");if(bx)bx.innerHTML=`<p class="m">${esc(error.message)}</p>`;return}
L.rows.push(...(data||[]));L.total=count??L.rows.length;L.done=!(data||[]).length||L.rows.length>=L.total;rplDraw()}

function rplDraw(){const box=$("rpl"),L=C.rl;if(!box||!L)return;
if(!L.rows.length){box.innerHTML=`<p class="m">مفيش فواتير في الفترة دي.</p>`;return}
const ph=dsPh(),one=(C.rr[1]-C.rr[0])<=864e5+36e5,tm=d=>one?dsHm(d):dsT(d);
const th=t=>`<th style="text-align:right;padding:6px 8px;border-bottom:1px solid var(--line);color:var(--mute);white-space:nowrap">${t}</th>`,td=(c,st)=>`<td style="padding:9px 8px;border-bottom:1px dashed var(--line);white-space:nowrap;${st||""}">${c}</td>`;
box.innerHTML=`<div class="m" style="margin-bottom:6px">${num(L.total)} فاتورة · الإجمالي <b>${fm(((C.rd||{}).totals||{}).revenue)}</b>${L.done?"":" · معروض "+num(L.rows.length)} · اضغط على أي فاتورة لتفاصيلها</div><div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse;font-size:13px"><tr>${th("#")}${th("الوقت")}${th("العميل")}${ph?th("التليفون"):""}${th("الحلاق")}${th("المبلغ")}</tr>`+
L.rows.map(i=>`<tr onclick="dsInvOne(${i.id})" style="cursor:pointer">${td(i.no)}${td(tm(i.created_at))}${td(esc(i.customers?.name||"عميل عابر"))}${ph?td(i.customers?.phone?`<span dir="ltr">${esc(i.customers.phone)}</span>`:"—"):""}${td(esc(i.barber?.full_name||"—"))}${td(`<b>${fm(i.total)}</b>`)}</tr>`).join("")+`</table></div>`+(L.done?"":`<button class="btn g" style="width:100%;margin-top:8px" onclick="rplLoad(1)">عرض المزيد (باقي ${num(L.total-L.rows.length)})</button>`)}

async function rpId(name,roles){const{data}=await sb.from("profiles").select("id,role").eq("full_name",name).limit(5);const L=data||[];return(L.find(x=>!roles||roles.includes(x.role))||L[0]||{}).id}

async function rpBar(i){const x=C.rd.barbers[i],id=await rpId(x.n,["barber"]);if(!id)return toast("مش لاقي الحلاق");dsInv({t:"فواتير "+x.n,...rpR(),barber:id})}

async function rpAsst(i){const x=C.rd.assistants[i],R=rpR(),id=await rpId(x.n,["assistant"]);if(!id)return toast("مش لاقي المساعد");
dsQ("خدمات "+x.n+" في الفترة",sb.rpc("assist_log",{p_staff:id,p_from:R.from,p_to:R.to}),L=>`<div class="m" style="margin-bottom:8px">${L.length} خدمة</div>`+L.map(z=>dsRow(`<b>#${z.inv_no}</b> · ${esc(z.service_name)}`,`${dsT(z.created)} · مع الحلاق ${esc(z.barber_name||"—")}`,`<b>${fm(z.price)}</b>`)).join(""))}

async function rpAtt(i){const x=C.rd.attendance[i],R=rpR();
dsQ("حضور "+x.n+" في الفترة",sb.from("attendance").select("check_in,check_out,late_min,profiles!inner(full_name)").eq("profiles.full_name",x.n).gte("check_in",R.from).lt("check_in",R.to).order("check_in",{ascending:false}).limit(200),L=>L.map(r=>dsRow(`<b>${new Date(r.check_in).toLocaleDateString("ar-EG",{weekday:"long",day:"numeric",month:"numeric"})}</b>`,`حضر ${dsHm(r.check_in)}${r.check_out?" · انصرف "+dsHm(r.check_out):" · لسه شغال"}`,+r.late_min>0?`<b style="color:var(--red)">تأخير ${r.late_min} د</b>`:`<span class="tag">في الميعاد</span>`)).join(""))}

async function rpItem(kind,i){const x=(kind=="sv"?C.rd.services:C.rd.products)[i],R=rpR();
dsQ((kind=="sv"?"الخدمة: ":"المنتج: ")+x.n,sb.from("invoice_items").select("qty,unit_price,invoices!inner(id,no,created_at,customers(name,phone),barber:barber_id(full_name))").eq("name",x.n).eq("item_type",kind=="sv"?"service":"product").gte("invoices.created_at",R.from).lt("invoices.created_at",R.to).limit(500),
L=>{L=[...L].sort((a,b)=>new Date(b.invoices.created_at)-new Date(a.invoices.created_at));return `<div class="m" style="margin-bottom:8px">${num(sumOf(L,z=>z.qty))} مرة · <b>${fm(sumOf(L,z=>z.qty*z.unit_price))}</b></div>`+L.map(z=>{const v=z.invoices;return `<button class="row" style="cursor:pointer;width:100%;text-align:right" onclick="dsInvOne(${v.id})"><div><b>#${v.no}</b> · ${esc(v.customers?.name||"عميل عابر")}${rpPhone(v.customers)?`<div class="m">${rpPhone(v.customers)}</div>`:""}<div class="m">${dsT(v.created_at)} · الحلاق: ${esc(v.barber?.full_name||"—")}</div></div><div style="text-align:left"><b>${fm(z.qty*z.unit_price)}</b>${z.qty>1?`<div class="m">${z.qty} × ${fm(z.unit_price)}</div>`:""}</div></button>`}).join("")})}

function rpDay(i){const d=C.rd.by_day[i].d,m=/^(\d{4}-\d{2}-\d{2})/.exec(String(d));let day=m?m[1]:null;if(!day){const t=new Date(d);if(!isNaN(t))day=ymd(t)}if(!day)return;
const a=new Date(day+"T00:00"),b=new Date(a);b.setDate(b.getDate()+1);dsInv({t:"فواتير يوم "+day,from:a.toISOString(),to:b.toISOString()})}

function rpHour(i){const h=+C.rd.by_hour[i].h;dsInv({t:"فواتير الساعة "+h+":00",...rpR(),hour:h})}

function rpAp(title,fl){const R=rpR();let q=sb.from("appointments").select("ticket_no,status,day,period,customers(name,phone),profiles(full_name),appointment_services(services(name))").gte("created_at",R.from).lt("created_at",R.to).order("created_at",{ascending:false}).limit(300);q=fl(q);
dsQ(title,q,L=>L.map(x=>dsRow(`<b>#${x.ticket_no??"-"} · ${esc(x.customers?.name||"—")}</b>${rpPhone(x.customers)?" · "+rpPhone(x.customers):""}`,`${x.day||""}${x.period?" · "+(PLB[x.period]||""):""} · ${(x.appointment_services||[]).map(s=>esc(s.services?.name||"")).filter(Boolean).join(" + ")||"—"}${x.profiles?.full_name?" · الحلاق: "+esc(x.profiles.full_name):""}`,`<span class="tag">${ST[x.status]||x.status}</span>`)).join(""))}

function rpTk(i){const s=C.rd.tickets[i].s;rpAp("حجوزات — "+(ST[s]||s),q=>q.eq("status",s))}

function rpPer(i){const p=C.rd.periods[i].p;rpAp("حجوزات فترة "+(PLB[p]||p),q=>q.eq("period",p))}

function rpExpCat(i){const c=C.rd.expenses[i].c,X=(C.rx||[]).filter(x=>x.category==c);
dsOpen("مصروفات "+c,X.length?`<div class="m" style="margin-bottom:8px">${X.length} بند · <b>${fm(sumOf(X,x=>x.amount))}</b></div>`+X.map(x=>dsRow(`<b>${esc(x.category)}</b>`,`${x.spent_on}${x.note?" · "+esc(x.note):""}${x.paid_from=="other"?" · من برا الدرج":""}`,`<b>${fm(x.amount)}</b>`)).join(""):dsEmpty("مفيش مصروفات."))}

async function rpCu(i){const x=C.rd.customers.top[i],q=x.ph?sb.from("customers").select("id").eq("phone",x.ph):sb.from("customers").select("id").eq("name",x.n),{data}=await q.limit(1),id=(data||[])[0]?.id;if(!id)return toast("مش لاقي العميل");(C.dsN=C.dsN||{})[id]=x.n;dsCust(id)}

async function rpLow(i){const x=C.rd.stock.low[i],{data:p}=await sb.from("products").select("id,name,stock,min_stock,cost,price").eq("name",x.n).limit(1),pr=(p||[])[0];if(!pr)return toast("مش لاقي المنتج");
dsQ("حركة "+pr.name,sb.from("stock_movements").select("qty,reason,created_at").eq("product_id",pr.id).order("id",{ascending:false}).limit(100),L=>`<div class="box">${dsKv("الكمية الحالية",pr.stock)}${dsKv("الحد الأدنى",pr.min_stock)}${dsKv("التكلفة",fm(pr.cost))}${dsKv("سعر البيع",fm(pr.price))}</div>`+L.map(m=>dsRow(`<b>${esc({sale:"بيع",void:"إلغاء فاتورة",restock:"توريد",purchase:"شراء",adjust:"تعديل"}[m.reason]||m.reason)}</b>`,dsT(m.created_at),`<b style="color:${m.qty>0?"var(--ok)":"var(--red)"}">${m.qty>0?"+":""}${m.qty}</b>`)).join(""))}

function rpCogs(){const P=C.rd.products||[];dsOpen("تكلفة المنتجات المباعة",P.length?P.map(x=>dsRow(`<b>${esc(x.n)}</b>`,`${x.q} قطعة · إيراد ${fm(x.t)}`,`<b>${fm(x.t-x.p)}</b>`)).join(""):dsEmpty("مفيش منتجات اتباعت في الفترة."),{list:1})}

function rpComm(){const B=C.rd.barbers||[];dsOpen("عمولات الحلاقين",B.length?B.map((x,i)=>`<button class="row" style="cursor:pointer;width:100%;text-align:right" onclick="rpBar(${i})"><div><b>${esc(x.n)}</b><div class="m">${x.cuts} زبون · مبيعات ${fm(x.sales)}</div></div><b>${fm(x.comm)}</b></button>`).join(""):dsEmpty(),{list:1})}

function rpSal(){const A=C.rd.assistants||[];dsOpen("رواتب المساعدين",A.length?A.map((x,i)=>`<button class="row" style="cursor:pointer;width:100%;text-align:right" onclick="rpAsst(${i})"><div><b>${esc(x.n)}</b><div class="m">${x.svc} خدمة · حصة المحل ${fm(x.cut)}</div></div><b>${fm(x.sal)}</b></button>`).join(""):dsEmpty("مفيش مساعدين."),{list:1})}


// ---- تقرير يوم بيوم: كل يوم في جدول لوحده + إجمالي الشغل والمصاريف والسحوبات في الآخر ----
async function rpdLoad(){const box=$("rpd");if(!box||!C.rr)return;const[a,b]=C.rr;let inv=[];
  for(let from=0;from<5000;from+=1000){const{data,error}=await sb.from("invoices").select("id,no,total,discount,payment_method,created_at,customers(name),barber:barber_id(full_name),invoice_items(name,qty)").gte("created_at",a.toISOString()).lt("created_at",b.toISOString()).order("created_at").range(from,from+999);
    if(error){box.innerHTML=`<p class="m">${esc(error.message)}</p>`;return}inv.push(...(data||[]));if((data||[]).length<1000)break}
  const{data:wd}=await sb.from("staff_transactions").select("amount,note,created_at,profiles(full_name)").eq("kind","advance").gte("created_at",a.toISOString()).lt("created_at",b.toISOString()).order("created_at");
  if(!$("rpd"))return;
  const bk=await bizKeyer();if(!$("rpd"))return;
  const D={},get=k=>D[k]||(D[k]={i:[],x:[],w:[]});
  inv.forEach(i=>get(bk(i.created_at)).i.push(i));(C.rx||[]).forEach(x=>get(x.spent_on).x.push(x));(wd||[]).forEach(w=>get(bk(w.created_at)).w.push(w));
  const ks=Object.keys(D).sort();if(!ks.length){box.innerHTML=`<p class="m">مفيش حركة في الفترة دي.</p>`;return}
  const sm=(L,f)=>L.reduce((t,x)=>t+(+f(x)||0),0),th=t=>`<th style="text-align:right;padding:6px 8px;border-bottom:1px solid var(--line);color:var(--mute);white-space:nowrap">${t}</th>`,td=(c,st)=>`<td style="padding:7px 8px;border-bottom:1px dashed var(--line);${st||""}">${c}</td>`,
  wk=["الأحد","الاثنين","الثلاثاء","الأربعاء","الخميس","الجمعة","السبت"];let G={s:0,x:0,w:0,n:0};
  const tb=(hd,rows)=>`<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse;font-size:13px"><tr>${hd.map(th).join("")}</tr>${rows.join("")}</table></div>`;
  box.innerHTML=ks.map(k=>{const d=D[k],s1=sm(d.i,x=>x.total),x1=sm(d.x,x=>x.amount),w1=sm(d.w,x=>x.amount);G.s+=s1;G.x+=x1;G.w+=w1;G.n+=d.i.length;
    const dn=new Date(k+"T12:00:00");
    return `<div class="box" style="margin-bottom:14px;break-inside:avoid"><h2 style="margin-top:0">${wk[dn.getDay()]} ${k}</h2>`+
    (d.i.length?tb(["#","الوقت","العميل","الحلاق","الخدمات","المبلغ"],d.i.map(i=>`<tr onclick="dsInvOne(${i.id})" style="cursor:pointer">${td(i.no)}${td(dsHm(i.created_at))}${td(esc(i.customers?.name||"عميل عابر"))}${td(esc(i.barber?.full_name||"—"))}${td((i.invoice_items||[]).map(z=>esc(z.name)+(z.qty>1?" ×"+z.qty:"")).join(" + "))}${td(`<b>${fm(i.total)}</b>`)}</tr>`)):`<p class="m">مفيش فواتير في اليوم ده.</p>`)+
    (d.x.length?`<div class="m" style="margin:8px 0 2px"><b>المصاريف</b></div>`+tb(["البند","ملاحظة","المبلغ"],[...d.x.map(x=>`<tr>${td(esc(x.category))}${td(esc(x.note||"—"))}${td(fm(x.amount))}</tr>`),`<tr>${td("<b>مجموع المصاريف</b>")}${td("")}${td("<b>"+fm(x1)+"</b>")}</tr>`]):"")+
    `<div class="m" style="margin:8px 0 2px"><b>سحوبات الموظفين</b></div>`+(d.w.length?tb(["الموظف","ملاحظة","المبلغ"],[...d.w.map(w=>`<tr>${td(esc(w.profiles?.full_name||"—"))}${td(esc(w.note||"—"))}${td(fm(w.amount))}</tr>`),`<tr>${td("<b>مجموع سحوبات اليوم</b>")}${td("")}${td("<b>"+fm(w1)+"</b>")}</tr>`]):`<p class="m" style="margin:2px 0">مفيش سحوبات في اليوم ده — مجموع سحوبات اليوم: ${fm(0)}</p>`)+
    `<div style="margin-top:8px;padding-top:8px;border-top:2px solid var(--line)">${[["إجمالي الشغل ("+d.i.length+" فاتورة)",s1],["إجمالي المصاريف",x1],["إجمالي السحوبات",w1]].map(r=>`<div style="display:flex;justify-content:space-between;padding:2px 0;font-weight:700"><span>${r[0]}</span><span>${fm(r[1])}</span></div>`).join("")}</div></div>`}).join("")+
  `<div class="box" style="border:2px solid var(--gold2)"><h2 style="margin-top:0">الإجمالي الكلي للفترة</h2>${[["إجمالي الشغل ("+num(G.n)+" فاتورة)",G.s,"var(--ok)"],["إجمالي المصاريف",G.x,"var(--red)"],["إجمالي السحوبات",G.w,"var(--red)"]].map(r=>`<div style="display:flex;justify-content:space-between;padding:4px 0;font-weight:800;font-size:15px"><span>${r[0]}</span><span style="color:${r[2]}">${fm(r[1])}</span></div>`).join("")}</div>`}


// ===== التقرير الشامل: شغل المحل · المصاريف (بنود) · صافي الربح · الدرج، وكل بند بيفتح تفاصيله =====
const FKIND={salary:"راتب",commission:"عمولة",wage:"أجر يوم",adj:"تسوية",deposit:"إيداع / مكافأة",withdraw:"سحب",deduction:"خصم",payout:"صرف راتب",settle:"تسوية حساب"};
// الدرج دلوقتي = رصيد آخر قفل + كل اللي دخل وطلع بعده لحد النهارده (مش النهارده بس)
async function fullDrawer(){const{data:cl}=await sb.from("cash_closings").select("day").order("day",{ascending:false}).limit(1),last=cl&&cl[0]?cl[0].day:null,to=ymd(new Date());let from;
  if(last){const d=new Date(last+"T00:00");d.setDate(d.getDate()+1);from=ymd(d)}else{const d=new Date();d.setDate(d.getDate()-365);from=ymd(d)}
  if(from>to)from=to;const{data}=await sb.rpc("drawer_range",{p_from:from,p_to:to});return data?{f:data,from,to,last}:null}
async function fullLoad(){const[a,b]=C.rr;
  const[{data:f,error},dr]=await Promise.all([sb.rpc("full_report",{p_from:a.toISOString(),p_to:b.toISOString()}),fullDrawer()]);
  const e=$("rpf");if(!e)return;if(error)return e.innerHTML=`<p class="m">${/Could not find the function/i.test(error.message||"")?"التقرير الشامل لسه ما اتفعّلش (شغّل patch_full_report.sql في Supabase).":esc(error.message)}</p>`;
  C.fr=f;C.fdr=dr;fullDraw()}
const fullCost=()=>(+C.fr.cogs||0)+(+C.fr.expenses||0)+(+C.fr.staff_cost||0);
function fullDraw(){const e=$("rpf"),f=C.fr;if(!e||!f)return;const cost=fullCost(),dr=C.fdr&&C.fdr.f.expected_cash!=null?+C.fdr.f.expected_cash:null;
  e.innerHTML=`<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px">${kc("شغل المحل",fm(f.revenue),"","fullWork()")}${kc("المصاريف (الكل)",fm(cost),"var(--red)","fullExp()")}${kc("صافي الربح",fm(f.profit),f.profit>=0?"var(--ok)":"var(--red)","fullProfit()")}${kc("الدرج دلوقتي (المتوقع)",dr==null?"—":fm(dr),"","fullDrawerOpen()")}</div>
<div class="m" style="margin-top:8px">${num(f.invoices)} فاتورة${(f.by_pay||[]).length?" · "+f.by_pay.map(x=>({cash:"كاش",card:"كارت",wallet:"محفظة"}[x.m]||x.m)+" "+fm(x.t)).join(" · "):""}</div>
<div class="m" style="margin-top:4px">اضغط على أي كارت تشوف تفاصيله.</div>`}
const fRow=(l,v,a,c)=>`<div class="row"${a?` role="button" style="cursor:pointer" onclick="${a}"`:""}><div><b>${l}</b></div><b${c?` style="color:${c}"`:""}>${v}${a?" ›":""}</b></div>`;
function fullWork(){const f=C.fr,L=(f.staff||[]).filter(x=>+x.sales>0),tot=L.reduce((a,x)=>a+(+x.sales),0),rest=(+f.revenue)-tot;
  dsOpen("شغل المحل · "+fm(f.revenue),`<div class="m" style="margin-bottom:6px">كل صنايعي اشتغل بكام (اضغط عليه تشوف حسابه كله)</div>`+(L.length?L.map(x=>fRow(esc(x.name)+` <span class="m">· ${num(x.cuts)} فاتورة</span>`,fm(x.sales),`fullStaff('${x.id}','w')`)).join(""):`<p class="m">مفيش مبيعات متسجلة على حلاقين في الفترة دي.</p>`)+(rest>0.5?fRow("مبيعات من غير حلاق (منتجات أو غيره)",fm(rest)):""),{list:1})}
function fullExp(){const f=C.fr,B=[];
  if(+f.commissions)B.push(["عمولات الصنايعية",f.commissions,"fullBand('commission')"]);
  if(+f.salaries)B.push(["رواتب (حلاقين، مدير، مساعدين، كاشير)",f.salaries,"fullBand('salary')"]);
  if(+f.bonuses)B.push(["مكافآت وأجر يوم",f.bonuses,"fullBand('bonus')"]);
  if(+f.deductions)B.push(["خصومات على الموظفين (بتقلّل المصاريف)",-f.deductions,"fullBand('deduction')"]);
  if(+f.cogs)B.push(["تكلفة المنتجات المباعة",f.cogs,null]);
  (f.expense_cats||[]).forEach((x,i)=>B.push([esc(x.c)+` <span class="m">· ${num(x.n)}</span>`,x.t,`fullCat(${i})`]));
  dsOpen("المصاريف · "+fm(fullCost()),`<div class="m" style="margin-bottom:6px">كل بند اضغط عليه تشوف تفاصيله</div>`+(B.length?B.map(x=>fRow(x[0],fm(x[1]),x[2])).join(""):`<p class="m">مفيش مصاريف في الفترة دي.</p>`)+`<div class="tot" style="display:flex;justify-content:space-between;border-top:1px solid var(--line);margin-top:8px;padding-top:8px;font-weight:800"><span>الإجمالي</span><span>${fm(fullCost())}</span></div>`,{list:1})}
function fullBand(k){const f=C.fr,T={commission:"عمولات الصنايعية",salary:"الرواتب",bonus:"المكافآت وأجر اليوم",deduction:"الخصومات"}[k],L=(f.staff||[]).filter(x=>+x[k]).sort((a,b)=>Math.abs(b[k])-Math.abs(a[k]));
  dsOpen(T,L.length?L.map(x=>fRow(esc(x.name)+` <span class="m">· ${RL[x.role]||""}</span>`,fm(k=="deduction"?-x[k]:x[k]),`fullStaff('${x.id}','e')`)).join(""):`<p class="m">مفيش.</p>`,{back:1})}
async function fullCat(i){const f=C.fr,x=(f.expense_cats||[])[i],[a,b]=C.rr;if(!x)return;
  const{data,error}=await sb.from("expenses").select("spent_on,note,amount,paid_from").eq("category",x.c).gte("spent_on",ymd(a)).lt("spent_on",ymd(b)).order("spent_on",{ascending:false}).limit(300);
  if(error)return toast(error.message);
  dsOpen(x.c+" · "+fm(x.t),(data||[]).map(r=>fRow(`${esc(r.note||x.c)}<div class="m">${r.spent_on}${r.paid_from?" · "+({drawer:"من الدرج",owner:"من المالك",bank:"بنك"}[r.paid_from]||esc(r.paid_from)):""}</div>`,fm(r.amount))).join("")||`<p class="m">مفيش تفاصيل.</p>`,{back:1})}
function fullProfit(){const f=C.fr,R=[["شغل المحل",f.revenue,1],["تكلفة المنتجات المباعة",-f.cogs],["عمولات الصنايعية",-f.commissions],["الرواتب",-f.salaries],["المكافآت وأجر اليوم",-f.bonuses],["الخصومات على الموظفين",f.deductions],["المصروفات",-f.expenses],["صافي الربح",f.profit,1]];
  dsOpen("إزاي طلع صافي الربح؟",R.map(r=>`<div style="display:flex;justify-content:space-between;padding:6px 0;${r[2]?"font-weight:800;border-top:1px solid var(--line)":""}"><span>${r[0]}</span><span>${fm(r[1])}</span></div>`).join("")+`<div class="m" style="margin-top:8px">سحب الموظفين (سلف) مش مصروف، بتتخصم من مستحقاتهم.</div>`,{list:1})}
// حساب صنايعي: اشتغل بكام · ليه كام · سحب كام · اتصرف له · باقيله كام + كشف الحركات
async function fullStaff(id,from){const f=C.fr,x=(f.staff||[]).find(y=>y.id==id),[a,b]=C.rr;if(!x)return;
  const{data:st,error}=await sb.rpc("staff_statement",{p_staff:id,p_from:a.toISOString(),p_to:b.toISOString()});if(error)return toast(error.message);
  const E=(st.entries||[]).slice().reverse().slice(0,150),bal=+x.balance;
  dsOpen(x.name+" · "+(RL[x.role]||""),`<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">${x.role=="assistant"?"":kc("اشتغل بكام",fm(x.sales),"")}${kc("ليه كام (مستحقاته)",fm(x.cost),"")}${kc("سحب كام",fm(x.advance),"")}${kc("اتصرف له",fm(x.paid),"")}${kc(bal>=0?"باقيله":"عليه",fm(Math.abs(bal)),bal>0?"var(--red)":"var(--ok)")}</div>
<div class="m" style="margin:8px 0">مستحقاته = عمولة ${fm(x.commission)} + راتب ${fm(x.salary)} + مكافآت ${fm(x.bonus)} − خصومات ${fm(x.deduction)}. «باقيله» رصيد حسابه من أول يوم لحد دلوقتي.</div>
<h2>حركات الفترة</h2>`+(E.length?E.map(r=>fRow(`${esc(r.label)}<div class="m">${FKIND[r.kind]||""} · ${new Date(r.at).toLocaleDateString("ar-EG")}</div>`,(+r.credit>0?"+ "+fm(r.credit):"− "+fm(r.debit)),null,+r.credit>0?"var(--ok)":"var(--red)")).join(""):`<p class="m">مفيش حركات.</p>`),{back:1})}

// تفاصيل الدرج: اللي دخل (مبيعات كاش + إيداع) واللي طلع (مصروفات + سحوبات + رواتب + مشتريات)، وكل بند بيفتح حركاته
function fullDrawerOpen(){const D=C.fdr;if(!D)return toast("بيانات الدرج مش متاحة");const f=D.f,n=k=>+f[k]||0;
  const IN=[["مبيعات كاش",n("cash_sales"),"fullDrw('sales')"],["إيداع في الدرج",n("moves_in"),"fullDrw('in')"]],
  OUT=[["مصروفات من الدرج",n("exp_cash"),"fullDrw('exp')"],["سحب موظفين (سلف)",n("adv_cash"),"fullDrw('adv')"],["سحب من الدرج",n("moves_out"),"fullDrw('out')"],["رواتب اتصرفت من الدرج",n("sal_cash"),"fullDrw('sal')"],["مشتريات مخزون",n("pur_cash"),null],["دفعات موردين",n("sup_cash"),null]],
  tin=IN.reduce((a,x)=>a+x[1],0),tout=OUT.reduce((a,x)=>a+x[1],0),line=x=>x[1]?fRow(x[0],fm(x[1]),x[2]):"";
  dsOpen("الدرج دلوقتي · "+fm(f.expected_cash),`<div class="m" style="margin-bottom:6px">من ${D.last?"آخر قفل ("+D.last+")":"أول الفترة"} لحد النهارده. اضغط على أي بند تشوف حركاته.</div>
${fRow("رصيد آخر قفل (اللي اتعدّ فعلًا)",fm(f.opening))}
<h2>دخل الدرج · ${fm(tin)}</h2>${IN.map(line).join("")||`<p class="m">مفيش.</p>`}
<h2>طلع من الدرج · ${fm(tout)}</h2>${OUT.map(line).join("")||`<p class="m">مفيش.</p>`}
<div class="tot" style="display:flex;justify-content:space-between;border-top:1px solid var(--line);margin-top:10px;padding-top:8px;font-weight:800"><span>الموجود المتوقع في الدرج</span><span>${fm(f.expected_cash)}</span></div>
<div class="m" style="margin-top:6px">${fm(f.opening)} + ${fm(tin)} − ${fm(tout)}. المتوقع حسابيًا، والفعلي بتعرفه من عدّ الدرج في «قفل اليوم».</div>`,{list:1})}
async function fullDrw(k){const D=C.fdr,f0=D.from,t0=D.to,ts=new Date(f0+"T00:00").toISOString(),te=(d=>(d.setDate(d.getDate()+1),d.toISOString()))(new Date(t0+"T00:00")),nm=id=>((C.fr.staff||[]).find(x=>x.id==id)||{}).name||"موظف",day=d=>new Date(d).toLocaleDateString("ar-EG");let q,T,R;
  if(k=="sales"){q=sb.from("invoices").select("no,total,created_at").eq("payment_method","cash").gte("created_at",ts).lt("created_at",te).order("created_at",{ascending:false}).limit(300);T="مبيعات كاش";R=r=>fRow(`فاتورة #${r.no}<div class="m">${day(r.created_at)}</div>`,fm(r.total))}
  else if(k=="in"||k=="out"){q=sb.from("cash_moves").select("day,amount,note").eq("kind",k=="in"?"deposit":"withdraw").gte("day",f0).lte("day",t0).order("day",{ascending:false}).limit(300);T=k=="in"?"إيداع في الدرج":"سحب من الدرج";R=r=>fRow(`${esc(r.note||T)}<div class="m">${r.day}</div>`,fm(r.amount))}
  else if(k=="exp"){q=sb.from("expenses").select("spent_on,category,note,amount").eq("paid_from","drawer").is("purchase_id",null).gte("spent_on",f0).lte("spent_on",t0).order("spent_on",{ascending:false}).limit(300);T="مصروفات من الدرج";R=r=>fRow(`${esc(r.category)}${r.note?" — "+esc(r.note):""}<div class="m">${r.spent_on}</div>`,fm(r.amount))}
  else if(k=="adv"){q=sb.from("staff_transactions").select("staff_id,amount,note,created_at").eq("kind","advance").gte("created_at",ts).lt("created_at",te).order("created_at",{ascending:false}).limit(300);T="سحب موظفين";R=r=>fRow(`${esc(nm(r.staff_id))}${r.note?" — "+esc(r.note):""}<div class="m">${day(r.created_at)}</div>`,fm(r.amount))}
  else{q=sb.from("salary_payments").select("staff_id,amount,note,paid_on").eq("paid_from","drawer").gte("paid_on",f0).lte("paid_on",t0).order("paid_on",{ascending:false}).limit(300);T="رواتب من الدرج";R=r=>fRow(`${esc(nm(r.staff_id))}${r.note?" — "+esc(r.note):""}<div class="m">${r.paid_on}</div>`,fm(r.amount))}
  const{data,error}=await q;if(error)return toast(error.message);const L=data||[];
  dsOpen(T+" · "+fm(L.reduce((a,r)=>a+(+r.amount||+r.total||0),0)),L.map(R).join("")||`<p class="m">مفيش حركات.</p>`,{back:1})}
