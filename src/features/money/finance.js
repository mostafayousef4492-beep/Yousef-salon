/* features/money/finance.js — المصروفات والموردين والرواتب */

// ---------- المالية (للمالك) ----------

V.fin=async()=>{C.fs=C.fs||"pur";const FS=[["pur","الموردين والمشتريات"],["pay","الرواتب"],["mon","أرباح شهرية"],["cat","تصنيفات المصروفات"]];
  put(`<h1>المالية</h1><div class="chips">${FS.map(x=>`<button class="chip ${C.fs==x[0]?"sel":""}" onclick="C.fs='${x[0]}';V.fin()">${x[1]}</button>`).join("")}</div><div id="fb">${SK}</div>`);
  try{await({pur:finPur,pay:finPay,mon:finMon,cat:finCat})[C.fs]()}catch(e){const b=$("fb");if(b)b.innerHTML=`<p class="m">حصلت مشكلة في تحميل القسم: ${esc(e.message||e)}</p><button class="btn g" onclick="V.fin()">إعادة المحاولة</button>`}};

async function finPur(){const box=$("fb");const[{data:sp,error},{data:pu},{data:allp},{data:py},{data:pr}]=await Promise.all([sb.from("suppliers").select("*").order("name"),dfQ(sb.from("purchases").select("*,suppliers(name),purchase_items(name,qty)"),"bought_on","pur").order("bought_on",{ascending:false}).order("id",{ascending:false}).limit(dfOn("pur")?500:40),sb.from("purchases").select("supplier_id,total,paid"),sb.from("supplier_payments").select("id,supplier_id,amount,paid_on,note,suppliers(name)").order("paid_on",{ascending:false}).order("id",{ascending:false}),sb.from("products").select("id,name,cost").eq("active",true).order("name")]);
  if(error)return errBox(box,error);
  const bal={};(allp||[]).forEach(p=>{if(p.supplier_id)bal[p.supplier_id]=(bal[p.supplier_id]||0)+(+p.total)-(+p.paid)});(py||[]).forEach(p=>{bal[p.supplier_id]=(bal[p.supplier_id]||0)-(+p.amount)});
  C.fp={sp:sp||[],pr:pr||[]};const pyV=(py||[]).filter(p=>dfIn("pur",p.paid_on));
  box.innerHTML=`<h2>الموردين</h2>${(sp||[]).map(s=>{const b=bal[s.id]||0;return `<div class="row"><div><b>${esc(s.name)}</b><div class="m">${esc(s.phone||"")}${b>0?` · <span style="color:var(--red)">مستحق له ${fm(b)}</span>`:b<0?` · له رصيد عندنا ${fm(-b)}`:""}</div></div><button class="btn s g" onclick="supPayForm(${s.id})">تسديد</button></div><div id="sp${s.id}"></div>`}).join("")||`<p class="m">مفيش موردين لسه.</p>`}<div class="box" style="margin-top:8px"><input id="sn_n" placeholder="اسم مورد جديد"><input id="sn_p" type="tel" placeholder="موبايل (اختياري)"><button class="btn s" onclick="addSup()">+ إضافة مورد</button></div><div class="m" style="margin-top:10px">فلتر بالتاريخ (التسديدات والمشتريات)</div>${dfBar("pur","V.fin()")}
${pyV.length?`<h2>${dfOn("pur")?"التسديدات":"آخر التسديدات"}</h2>`+(dfOn("pur")?`<div class="m">${pyV.length} عملية · <b>${fm(sumOf(pyV,x=>x.amount))}</b></div>`:"")+pyV.slice(0,dfOn("pur")?500:15).map(p=>`<div class="row"><div><b>${fm(p.amount)}</b> · ${esc(p.suppliers?.name||"")}<div class="m">${p.paid_on}${p.note?" · "+esc(p.note):""}</div></div><button class="btn s g" onclick="ownerDel('supplier_payments','${p.id}',()=>V.fin(),'تحذف التسديد ده؟')">حذف</button></div>`).join(""):(dfOn("pur")?`<p class="m">مفيش تسديدات في الفترة دي.</p>`:"")}<h2>فاتورة شراء</h2><button class="btn" onclick="purForm()">+ فاتورة شراء جديدة</button><div id="pf"></div>
<h2>${dfOn("pur")?"المشتريات":"آخر المشتريات"}</h2>${dfOn("pur")?`<div class="m">${(pu||[]).length} فاتورة · <b>${fm(sumOf(pu||[],x=>x.total))}</b></div>`:""}${(pu||[]).map(p=>`<div class="row"><div><b>${esc(p.suppliers?.name||"بدون مورد")}</b> · ${fm(p.total)}<div class="m">${p.bought_on} · ${p.kind=="stock"?"بضاعة مخزون":"مستلزمات"} · ${(p.purchase_items||[]).map(i=>esc(i.name)+" ×"+(+i.qty)).join("، ")}${+p.paid<+p.total?` · <span style="color:var(--red)">متبقي ${fm(p.total-p.paid)}</span>`:""}</div></div><button class="btn s g" onclick="voidPur(${p.id})">إلغاء</button></div>`).join("")||`<p class="m">مفيش مشتريات.</p>`}`}

async function addSup(){const n=$("sn_n").value.trim();if(n.length<2)return toast("اكتب اسم المورد");const{error}=await sb.from("suppliers").insert({name:n,phone:$("sn_p").value.trim()||null});error?toast(error.code=="23505"?"المورد ده موجود":error.message):(toast("تم ✓"),V.fin())}

function supPayForm(id){const e=$("sp"+id);if(e.innerHTML)return e.innerHTML="";e.innerHTML=`<div class="box" style="margin-bottom:10px"><input id="spa${id}" type="number" inputmode="decimal" placeholder="المبلغ"><select id="sps${id}">${paySrc("drawer")}</select><input id="spn${id}" placeholder="ملاحظة (اختياري)"><button class="btn s" onclick="saveSupPay(${id})">حفظ التسديد</button></div>`}

async function saveSupPay(id){const a=parseFloat($("spa"+id).value);if(!(a>0))return toast("اكتب المبلغ");const{error}=await sb.from("supplier_payments").insert({supplier_id:id,amount:a,paid_from:$("sps"+id).value,note:$("spn"+id).value||null,paid_on:bizToday()});error?toast(error.message):(toast("تم التسديد ✓"),V.fin())}

function purForm(){C.pf={sup:"",kind:"stock",date:bizToday(),items:[{product_id:"",name:"",qty:1,unit_cost:""}],paid:"",paid_from:"drawer",upd:false,note:""};drawPur()}

function pfTot(){return C.pf.items.reduce((a,i)=>a+(+i.qty||0)*(+i.unit_cost||0),0)}

function pfSet(i,k,v,quiet){const it=C.pf.items[i];it[k]=v;if(k=="product_id"){const p=C.fp.pr.find(x=>x.id==v);if(p&&!it.unit_cost)it.unit_cost=p.cost}if(quiet){const t=$("pf_t");if(t)t.textContent=fm(pfTot())}else drawPur()}

function drawPur(){const f=C.pf,P=C.fp;
  $("pf").innerHTML=`<div class="box" style="margin-top:8px"><label class="m">المورد</label><select onchange="C.pf.sup=this.value"><option value="">بدون مورد</option>${P.sp.filter(s=>s.active).map(s=>`<option value="${s.id}" ${f.sup==s.id?"selected":""}>${esc(s.name)}</option>`).join("")}</select>
<label class="m">نوع الشراء</label><select onchange="C.pf.kind=this.value;C.pf.items=[{product_id:'',name:'',qty:1,unit_cost:''}];drawPur()"><option value="stock" ${f.kind=="stock"?"selected":""}>بضاعة للمخزون (بتزوّد الكمية)</option><option value="supplies" ${f.kind=="supplies"?"selected":""}>مستلزمات (بتتحسب مصروف)</option></select>
<input type="date" value="${f.date}" onchange="C.pf.date=this.value">
${f.items.map((it,i)=>`<div style="border-top:1px dashed var(--line);padding-top:8px;margin-top:8px">${f.kind=="stock"?`<select onchange="pfSet(${i},'product_id',this.value)"><option value="">اختار المنتج</option>${P.pr.map(p=>`<option value="${p.id}" ${it.product_id==p.id?"selected":""}>${esc(p.name)}</option>`).join("")}</select>`:`<input placeholder="اسم البند" value="${esc(it.name)}" oninput="pfSet(${i},'name',this.value,1)">`}<div class="chips" style="margin:0"><input type="number" inputmode="decimal" placeholder="الكمية" value="${it.qty}" style="width:90px" oninput="pfSet(${i},'qty',this.value,1)"><input type="number" inputmode="decimal" placeholder="سعر الوحدة" value="${it.unit_cost}" style="width:120px" oninput="pfSet(${i},'unit_cost',this.value,1)">${f.items.length>1?`<button class="btn s g" onclick="C.pf.items.splice(${i},1);drawPur()">حذف</button>`:""}</div></div>`).join("")}
<button class="btn s g" style="margin:8px 0" onclick="C.pf.items.push({product_id:'',name:'',qty:1,unit_cost:''});drawPur()">+ بند</button>
<div style="display:flex;justify-content:space-between;font-weight:800;margin-bottom:8px"><span>الإجمالي</span><span id="pf_t">${fm(pfTot())}</span></div>
<input type="number" inputmode="decimal" placeholder="المدفوع دلوقتي (اكتب 0 لو آجل)" value="${f.paid}" oninput="C.pf.paid=this.value"><select onchange="C.pf.paid_from=this.value">${paySrc(f.paid_from)}</select>
${f.kind=="stock"?`<label class="row" style="cursor:pointer"><span>حدّث تكلفة المنتج بسعر الشراء ده</span><input type="checkbox" ${f.upd?"checked":""} onchange="C.pf.upd=this.checked" style="width:22px;height:22px;margin:0"></label>`:""}
<input placeholder="ملاحظة (اختياري)" value="${esc(f.note)}" oninput="C.pf.note=this.value"><div class="chips"><button class="btn" onclick="savePur()">حفظ الفاتورة</button><button class="btn g" onclick="$('pf').innerHTML=''">إلغاء</button></div></div>`}

async function savePur(){const f=C.pf;if(f.paid==="")return toast("اكتب المدفوع (اكتب 0 لو آجل)");
  const items=f.items.map(i=>({product_id:f.kind=="stock"?(i.product_id||null):null,name:i.name,qty:+i.qty,unit_cost:+i.unit_cost}));
  const{error}=await sb.rpc("record_purchase",{p_supplier:f.sup?+f.sup:null,p_date:f.date,p_kind:f.kind,p_items:items,p_paid:+f.paid,p_paid_from:f.paid_from,p_note:f.note||null,p_update_cost:!!f.upd});
  error?toast(error.message):(toast("تم تسجيل الفاتورة ✓"),V.fin())}

async function voidPur(id){if(!confirm("تلغي فاتورة الشراء دي؟ هترجّع المخزون وتمسح المصروف المرتبط بيها."))return;const{error}=await sb.rpc("void_purchase",{p_id:id});error?toast(error.message):(toast("تم الإلغاء"),V.fin())}

async function finPay(){const box=$("fb");const now=ymd(new Date());C.pm=C.pm||now.slice(0,7)+"-01";const[a,b]=monthR(C.pm);
  const{data:st,error}=await sb.from("profiles").select("id,full_name,role").neq("role","owner").neq("role","customer").order("full_name");if(!error)await addSalary(st);if(error)return errBox(box,error);
  const[sums,{data:pays,error:e2}]=await Promise.all([Promise.all((st||[]).map(s=>sb.rpc("staff_summary",{p_staff:s.id,p_from:a.toISOString(),p_to:b.toISOString()}))),sb.from("salary_payments").select("*,profiles(full_name)").eq("period",C.pm).order("id",{ascending:false})]);
  if(e2)return errBox(box,e2);
  const paid={};(pays||[]).forEach(p=>paid[p.staff_id]=(paid[p.staff_id]||0)+(+p.amount));
  const rows=(st||[]).map((s,i)=>{const net=sums[i].data?.[0]?.net,due=net==null?0:+net,pd=paid[s.id]||0,rem=Math.max(0,due-pd);return{s,due,pd,rem}});
  const T=rows.reduce((o,r)=>({due:o.due+r.due,pd:o.pd+r.pd,rem:o.rem+r.rem}),{due:0,pd:0,rem:0});C.fp={rows,pays:pays||[],m:C.pm};
  box.innerHTML=`<div class="chips" style="align-items:center"><input type="month" value="${C.pm.slice(0,7)}" style="width:auto;margin:0" onchange="C.pm=(this.value||'${now.slice(0,7)}')+'-01';V.fin()"></div><div class="m" style="margin:6px 0">المستحق = الراتب الثابت + العمولة + المكافآت − السحب − الخصومات (عن ${mAr(C.pm)})</div>
<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px">${kc("المستحق",fm(T.due),"","fpDue()")}${kc("اتصرف",fm(T.pd),"var(--ok)","fpPaid()")}${kc("المتبقي",fm(T.rem),T.rem>0?"var(--red)":"inherit","fpRem()")}</div>
<h2>الموظفين</h2>${tbl(["الموظف","المستحق","اتصرف","المتبقي",""],rows.map(r=>[`${esc(r.s.full_name)}<div class="m">${RL[r.s.role]||r.s.role}</div>`,fm(r.due),fm(r.pd),`<b style="color:${r.rem>0?"var(--red)":"var(--ok)"}">${fm(r.rem)}</b>`,`<button class="btn s" onclick="payForm('${r.s.id}',${r.rem})">صرف</button>`]))}<div id="pyf"></div>
<h2>سجل الصرف</h2>${(pays||[]).map(p=>`<div class="row"><div><b>${esc(p.profiles?.full_name||"—")}</b> · ${fm(p.amount)}<div class="m">${p.paid_on} · ${p.paid_from=="drawer"?"من الدرج":"من برا الدرج"}${p.note?" · "+esc(p.note):""}</div></div><button class="btn s g" onclick="delPay(${p.id})">حذف</button></div>`).join("")||`<p class="m">مفيش صرف الشهر ده.</p>`}`}

function payForm(id,rem){C.py=id;$("pyf").innerHTML=`<div class="box" style="margin-top:10px"><div class="m">صرف راتب</div><input id="py_a" type="number" inputmode="decimal" value="${rem||""}" placeholder="المبلغ"><select id="py_s">${paySrc("drawer")}</select><input id="py_n" placeholder="ملاحظة (اختياري)"><div class="chips"><button class="btn" onclick="savePay()">حفظ الصرف</button><button class="btn g" onclick="$('pyf').innerHTML=''">إلغاء</button></div></div>`;$("py_a").focus()}

async function savePay(){const a=parseFloat($("py_a").value);if(!(a>0))return toast("اكتب المبلغ");const{error}=await sb.from("salary_payments").insert({staff_id:C.py,period:C.pm,amount:a,paid_from:$("py_s").value,note:$("py_n").value||null,paid_on:bizToday()});error?toast(error.message):(toast("تم صرف الراتب ✓"),V.fin())}

function delPay(id){return ownerDel("salary_payments",id,()=>V.fin(),"تحذف سجل الصرف ده؟")}

async function finMon(){const box=$("fb");const{data,error}=await sb.rpc("monthly_profit",{p_months:12});if(error)return errBox(box,error);const L=data||[];C.mon=L;
  box.innerHTML=`<h2>صافي الربح كل شهر</h2>${bars(L.slice().reverse(),x=>mAr(x.month),x=>Math.max(0,+x.profit))}<h2>التفاصيل</h2>${tbl(["الشهر","المبيعات","تكلفة","عمولات ورواتب","مصروفات","الصافي"],L.map(x=>[mAr(x.month),fm(x.revenue),fm(x.cogs),fm(+x.commissions+ +x.salaries+ +x.bonuses- +x.deductions),fm(x.expenses),`<b style="color:${+x.profit>=0?"var(--ok)":"var(--red)"}">${fm(x.profit)}</b>`]))}<div class="chips" style="margin-top:12px"><button class="btn g s" onclick="exportMonthly()">⬇ تصدير Excel</button></div>`}

async function finCat(){const box=$("fb");const{data,error}=await sb.from("expense_categories").select("*").order("id");if(error)return errBox(box,error);
  box.innerHTML=`<div class="m" style="margin-bottom:8px">التصنيفات دي بتظهر عند تسجيل مصروف. الرواتب مش تصنيف: بتتسجل من تاب "الرواتب" عشان ما تتحسبش مرتين.</div>${(data||[]).map(c=>`<div class="row"><b>${esc(c.name)}${c.active?"":" · موقوف"}</b><button class="btn s g" onclick="togCat(${c.id},${!c.active})">${c.active?"إيقاف":"تفعيل"}</button></div>`).join("")}<div class="box"><input id="cat_n" placeholder="تصنيف جديد"><button class="btn s" onclick="addCat()">+ إضافة</button></div>`}

async function addCat(){const n=$("cat_n").value.trim();if(!n)return toast("اكتب اسم التصنيف");const{error}=await sb.from("expense_categories").insert({name:n});error?toast(error.code=="23505"?"التصنيف ده موجود":error.message):V.fin()}

async function togCat(id,v){await sb.from("expense_categories").update({active:v}).eq("id",id);V.fin()}
