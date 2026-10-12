/* features/customers/customers.js — إدارة العملاء */

// ================= العملاء =================

V.cust=async()=>{dfClr("cu");const{data}=await sb.rpc("customers_overview");C.CU=data||[];C.cq="";
put(`<h1>إدارة العملاء</h1>${can("use_pos")?`<button class="btn s" onclick="addCustForm()">+ إضافة عميل</button><div id="ac"></div>`:""}<input placeholder="ابحث بالاسم أو الموبايل" oninput="C.cq=this.value;$('cl').innerHTML=custRows()"><div id="cl">${custRows()}</div>`)};

function addCustForm(){const e=$("ac");if(e.innerHTML)return e.innerHTML="";e.innerHTML=`<div class="box" style="margin:10px 0"><input id="ac_n" placeholder="اسم العميل"><input id="ac_p" type="tel" inputmode="numeric" placeholder="رقم الموبايل (01xxxxxxxxx)"><div class="chips"><button class="btn" onclick="saveCust()">حفظ العميل</button><button class="btn g" onclick="$('ac').innerHTML=''">إلغاء</button></div></div>`;$("ac_n").focus()}

async function saveCust(){const n=$("ac_n").value.trim(),ph=$("ac_p").value.replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/\D/g,"");
if(n.length<2)return toast("اكتب اسم العميل");if(!/^01\d{9}$/.test(ph))return toast("الموبايل لازم 11 رقم ويبدأ بـ 01");
const{error}=await sb.rpc("add_customer",{p_name:n,p_phone:ph});error?toast(error.message):(toast("تمت إضافة "+n+" ✓"),V.cust())}

const custRows=()=>{const q=(C.cq||"").trim(),L=C.CU.filter(x=>!q||x.name.includes(q)||(x.phone||"").includes(q));return `<div class="m" style="margin-bottom:8px">${L.length} عميل</div>`+L.map(x=>`<div class="row" role="button" style="cursor:pointer" onclick="openCust(${x.id})"><div><b>${esc(x.name)}</b><div class="m">${esc(x.phone||"")} · ${x.visits} زيارة · دفع ${fm(x.spent)}</div></div><div style="display:flex;gap:6px;align-items:center"><span class="tag" style="background:var(--brass);color:#fff">${x.points} نقطة</span>${waBtn(x.phone,0,waAppMsg(x.name))}</div></div>`).join("")};

async function openCust(id){const x=C.CU.find(y=>y.id==id);const[{data},{data:ap}]=await Promise.all([dfQ(sb.from("invoices").select("id,no,subtotal,discount,total,created_at,payment_method,invoice_items(name,qty,unit_price)").eq("customer_id",id),"created_at","cu",true).order("created_at",{ascending:false}).limit(dfOn("cu")?300:15),dfQ(sb.from("appointments").select("day,status,profiles(full_name),appointment_services(services(name))").eq("customer_id",id),"day","cu").order("day",{ascending:false}).limit(dfOn("cu")?300:10)]);
const A=ap||[],staff=[...new Set(A.map(a=>a.profiles?.full_name).filter(Boolean))],fv=n=>n?new Date(n).toLocaleDateString("ar-EG"):"—";
put(`<button class="btn g s" style="margin-top:12px" onclick="V.cust()">‹ رجوع</button><h1>${esc(x.name)}</h1><div class="m" dir="ltr" style="text-align:right">${esc(x.phone||"")}</div>
<div class="cc-grid" style="margin-top:10px"><div class="box cc-stat" role="button" style="cursor:pointer" onclick="dsCust(${x.id})"><div class="cc-l">زيارات</div><div class="cc-n">${x.visits}</div></div><div class="box cc-stat" role="button" style="cursor:pointer" onclick="dsCust(${x.id})"><div class="cc-l">إجمالي الدفع</div><div class="cc-n">${fm(x.spent)}</div></div><div class="box cc-stat" role="button" style="cursor:pointer" onclick="dsLoyC(${x.id})"><div class="cc-l">نقاط</div><div class="cc-n">${x.points}</div></div><div class="box cc-stat" role="button" style="cursor:pointer" onclick="dsCust(${x.id})"><div class="cc-l">آخر زيارة</div><div class="cc-n" style="font-size:1rem">${fv(x.last_visit)}</div></div></div>
<div class="chips" style="margin-top:10px">${waBtn(x.phone,1,waAppMsg(x.name))}${can("use_pos")?`<button class="btn" onclick="custSell(${id})">بيع</button>`:""}${can("manage_appts")?`<button class="btn g" onclick="custBook(${id})">حجز</button>`:""}${isAdm(me)?`<button class="btn s g" onclick="adjP(${id})">تعديل النقاط</button><button class="btn s g" style="color:var(--red)" onclick="delC(${id})">حذف</button>`:""}</div>
${can("view_customers")?`<div class="box" style="margin-top:10px"><div class="m">كود دخول العميل (للتطبيق من جهاز جديد)</div><div class="code-big" id="ccode" dir="ltr">••••••</div><div class="chips"><button class="btn s g" onclick="custCode(${id},false)">إظهار الكود</button><button class="btn s g" onclick="custCode(${id},true)">كود جديد</button></div></div>`:""}
${staff.length?`<h2>اتخدم عند</h2><div class="m">${staff.map(esc).join(" · ")}</div>`:""}
${dfBar("cu","openCust("+id+")")}<h2>${dfOn("cu")?"الفواتير":"آخر الفواتير"}</h2>`+((data||[]).length?data.map(i=>`<div class="row" role="button" style="cursor:pointer;width:100%;text-align:right;gap:8px" onclick="dsInvOne(${i.id})"><div><b>#${i.no}</b> · ${fv(i.created_at)}<div class="m">${i.invoice_items.map(z=>esc(z.name)+(z.qty>1?" ×"+z.qty:"")).join(" + ")}</div></div><div style="display:flex;gap:6px;align-items:center"><b>${fm(i.total)}</b>${waBtn(x.phone,0,waInvText(i,x.name))}</div></div>`).join(""):`<p class="m">مفيش فواتير.</p>`)+`<h2>الحجوزات</h2>`+(A.length?A.map(a=>`<div class="row"><div><b>${fv(a.day)}</b><div class="m">${(a.appointment_services||[]).map(z=>esc(z.services?.name||"")).filter(Boolean).join(" + ")||"—"}${a.profiles?.full_name?" · "+esc(a.profiles.full_name):""}</div></div><span class="tag">${esc(ST[a.status]||a.status)}</span></div>`).join(""):`<p class="m">مفيش حجوزات.</p>`))}

async function custSell(id){const x=C.CU.find(y=>y.id==id),{data:L}=await sb.from("open_invoices").select("chair,customer_id");const ex=(L||[]).find(r=>r.customer_id==id);let n=ex?ex.chair:0;
if(!n){const u=new Set((L||[]).map(r=>r.chair));for(let i=1;i<=chN();i++)if(!u.has(i)){n=i;break}if(!n){toast("كل الكراسي مشغولة. اقفل فاتورة الأول");return go("pos")}
const ins=await sb.from("open_invoices").insert({chair:n,customer_id:id});if(ins.error){toast(ins.error.code=="23505"?"الكرسي ده اتاخد، جرّب تاني":ins.error.message);return go("pos")}}
C.chOpenAfter=n;go("pos")}

function custBook(id){const x=C.CU.find(y=>y.id==id);go("appts");let n=0;const w=setInterval(async()=>{if($("adm")||++n>40){clearInterval(w);if(!$("adm"))return;await admForm();let m=0;const w2=setInterval(()=>{if($("ad_n")||++m>40){clearInterval(w2);if($("ad_n")){$("ad_n").value=x.name;$("ad_p").value=x.phone||""}}},100)}},100)}

async function adjP(id){const n=+prompt("عدد النقاط (موجب للإضافة، سالب للخصم)");if(!n)return;const note=prompt("السبب","تعديل إداري")||"";const{error}=await sb.rpc("adjust_points",{p_customer:id,p_pts:n,p_note:note});error?toast(error.message):(toast("تم ✓"),V.cust())}

async function delC(id){if(!confirm("حذف العميل وكل حجوزاته وتقييماته؟ مش هيترجّع."))return;const{error}=await sb.rpc("delete_customer",{p_id:id});error?toast(error.message):(toast("تم الحذف"),V.cust())}

const dsCuRow=c=>{(C.dsN=C.dsN||{})[c.id]=c.name;return `<button class="row" style="cursor:pointer;width:100%;text-align:right" onclick="dsCust(${c.id})"><div><b>${esc(c.name)}</b><div class="m">${dsPh()&&c.phone?`<span dir="ltr">${esc(c.phone)}</span> · `:""}${c.sub||""}</div></div>${c.end?`<div style="text-align:left">${c.end}</div>`:""}</button>`};

function dsCust(id){const n=(C.dsN||{})[id]||((C.CU||[]).find(y=>y.id==id)||{}).name||"العميل";dsInv({t:"فواتير "+n,customer:id})}

function dsLoyC(id){const n=(C.dsN||{})[id]||((C.CU||[]).find(y=>y.id==id)||{}).name||"العميل";
  dsQ("نقاط "+n,sb.from("loyalty_ledger").select("points,reason,note,created_at").eq("customer_id",id).order("created_at",{ascending:false}).limit(200),L=>L.map(x=>dsRow(`<b>${esc(LYR[x.reason]||x.reason)}</b>`,dsT(x.created_at)+(x.note?" · "+esc(x.note):""),`<b style="color:${x.points>0?"var(--ok)":"var(--red)"}">${x.points>0?"+":""}${x.points}</b>`)).join(""))}

// كود دخول العميل: الكاشير/المالك يشوفه أو يطلّع واحد جديد (الجديد بيخرّج العميل من أجهزته القديمة)
async function custCode(id,renew){const x=C.CU.find(y=>y.id==id);if(!x)return;
if(renew&&!confirm("تطلّع كود جديد للعميل ده؟ هيتخرّج من كل أجهزته وهيدخل بالكود الجديد."))return;
const{data,error}=await sb.rpc(renew?"customer_code_reset":"customer_code_get",{p_phone:x.phone});
if(error||!data)return toast(error?error.message:"العميل ده لسه ما سجّلش في التطبيق");
const e=$("ccode");if(e)e.textContent=data;
if(renew)toast("تم — الكود الجديد: "+data);
const w=$("ccw");if(w)w.remove();
e.insertAdjacentHTML("afterend",`<span id="ccw">${waBtn(x.phone,0,"كودك للدخول على تطبيق "+C.cfg.salon_name+": "+data)}</span>`)}
