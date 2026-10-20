/* features/customers/customers.js — إدارة العملاء */

// ================= العملاء =================

V.cust=async()=>{dfClr("cu");const[{data},cl]=await Promise.all([sb.rpc("customers_overview"),can("use_pos")?sb.rpc("pending_claims"):Promise.resolve({data:null})]);C.CU=data||[];C.cq="";
const CL=cl.data||[];
put(`<h1>العملاء</h1>${CL.length?`<h2>طلبات ربط حساب (${CL.length})</h2>`+CL.map(r=>`<div class="row"><div><b>${esc(r.customer_name)}</b><div class="m" dir="ltr">${esc(r.phone||"")}</div></div><button class="btn s" onclick="claimOk(${r.id})">موافقة على الربط</button></div>`).join(""):""}${can("use_pos")?`<button class="btn s" onclick="addCustForm()">+ إضافة عميل</button><div id="ac"></div>`:""}${isAdm(me)?`<button class="btn s g" onclick="fbList()">💬 آراء العملاء</button>`:""}<input placeholder="ابحث بالاسم أو الموبايل" oninput="C.cq=this.value;$('cl').innerHTML=custRows()"><div id="cl">${custRows()}</div>`)};

function addCustForm(){const e=$("ac");if(e.innerHTML)return e.innerHTML="";e.innerHTML=`<div class="box" style="margin:10px 0"><input id="ac_n" placeholder="اسم العميل"><input id="ac_p" type="tel" inputmode="numeric" placeholder="رقم الموبايل (اختياري — تقدر تربطه بعدين)"><input id="ac_r" placeholder="جاي عن طريق مين؟ (رقم أو كود — اختياري)"><div class="chips"><button class="btn" onclick="saveCust()">حفظ العميل</button><button class="btn g" onclick="$('ac').innerHTML=''">إلغاء</button></div></div>`;$("ac_n").focus()}

async function saveCust(){const n=$("ac_n").value.trim(),ph=$("ac_p").value.replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/\D/g,"");
if(n.length<2)return toast("اكتب اسم العميل");if(ph&&!/^01\d{9}$/.test(ph))return toast("الموبايل لازم 11 رقم ويبدأ بـ 01");
const{data:nid,error}=await sb.rpc("add_customer",{p_name:n,p_phone:ph||null});if(error)return toast(error.message);const rf=($("ac_r")?.value||"").trim();let rm="";if(rf){const{error:e2}=await sb.rpc("staff_set_referrer",{p_customer:nid,p_key:rf});if(e2)rm=" (لكن المُحيل: "+e2.message+")"}toast("تمت إضافة "+n+" ✓"+rm);V.cust()}

const custRows=()=>{const q=(C.cq||"").trim(),L=C.CU.filter(x=>!q||x.name.includes(q)||(x.phone||"").includes(q));return `<div class="m" style="margin-bottom:8px">${L.length} عميل</div>`+L.map(x=>`<div class="row" role="button" style="cursor:pointer" onclick="openCust(${x.id})"><div><b>${esc(x.name)}</b><div class="m">${esc(x.phone||"")} · ${x.visits} زيارة · دفع ${fm(x.spent)}</div></div><div style="display:flex;gap:6px;align-items:center"><span class="tag" style="background:var(--brass);color:#fff">${x.points} نقطة</span>${waBtn(x.phone,0,waAppMsg(x.name))}</div></div>`).join("")};

async function openCust(id){const x=C.CU.find(y=>y.id==id);const[{data},{data:ap}]=await Promise.all([dfQ(sb.from("invoices").select("id,no,subtotal,discount,total,created_at,payment_method,invoice_items(name,qty,unit_price)").eq("customer_id",id),"created_at","cu",true).order("created_at",{ascending:false}).limit(dfOn("cu")?300:15),dfQ(sb.from("appointments").select("day,status,profiles(full_name),appointment_services(services(name))").eq("customer_id",id),"day","cu").order("day",{ascending:false}).limit(dfOn("cu")?300:10)]);
setTimeout(()=>custAv(id),0);const A=ap||[],staff=[...new Set(A.map(a=>a.profiles?.full_name).filter(Boolean))],fv=n=>n?new Date(n).toLocaleDateString("ar-EG"):"—";
put(`<button class="btn g s" style="margin-top:12px" onclick="V.cust()">‹ رجوع</button><div id="cav"></div><h1>${esc(x.name)}</h1><div class="m" dir="ltr" style="text-align:right">${esc(x.phone||"")}</div>
<div class="cc-grid" style="margin-top:10px"><div class="box cc-stat" role="button" style="cursor:pointer" onclick="dsCust(${x.id})"><div class="cc-l">زيارات</div><div class="cc-n">${x.visits}</div></div><div class="box cc-stat" role="button" style="cursor:pointer" onclick="dsCust(${x.id})"><div class="cc-l">إجمالي الدفع</div><div class="cc-n">${fm(x.spent)}</div></div><div class="box cc-stat" role="button" style="cursor:pointer" onclick="dsLoyC(${x.id})"><div class="cc-l">نقاط</div><div class="cc-n">${x.points}</div></div><div class="box cc-stat" role="button" style="cursor:pointer" onclick="dsCust(${x.id})"><div class="cc-l">آخر زيارة</div><div class="cc-n" style="font-size:1rem">${fv(x.last_visit)}</div></div></div>
${waKit(x,(data||[])[0])}
<div class="chips" style="margin-top:10px">${waBtn(x.phone,1)}${can("use_pos")?`<button class="btn" onclick="custSell(${id})">بيع</button>`:""}${can("manage_appts")?`<button class="btn g" onclick="custBook(${id})">حجز</button>`:""}${can("use_pos")?`<button class="btn s g" onclick="setRef(${id})">جاي عن طريق</button>`:""}${can("use_pos")&&!x.phone?`<button class="btn" onclick="attachPh(${id})">ربط برقم موبايل</button>`:""}${isAdm(me)?`<button class="btn s g" onclick="adjP(${id})">تعديل النقاط</button><button class="btn s g" style="color:var(--red)" onclick="delC(${id})">حذف</button>`:""}</div>
${can("view_customers")?`<div class="box" style="margin-top:10px"><div class="m">كود دخول العميل من جهاز جديد (صالح 15 دقيقة)</div><div class="code-big" id="ccode" dir="ltr">••••••</div><div class="chips"><button class="btn s g" onclick="custCode(${id})">إصدار كود دخول</button></div></div>`:""}
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
async function custCode(id){const x=C.CU.find(y=>y.id==id);if(!x)return;
const{data,error}=await sb.rpc("staff_issue_login_code",{p_phone:x.phone});
if(error||!data)return toast(error?error.message:"تعذّر إصدار الكود");
const e=$("ccode");if(e)e.textContent=data;
const w=$("ccw");if(w)w.remove();
e.insertAdjacentHTML("afterend",`<span id="ccw">${waBtn(x.phone,0,"كود دخولك على تطبيق "+C.cfg.salon_name+": "+data+" (صالح 15 دقيقة)")}</span>`)}

async function claimOk(id){if(!confirm("تأكد إن اللي بيطلب الربط هو صاحب الرقم فعلًا. تربط؟"))return;const{error}=await sb.rpc("approve_claim",{p_id:id});error?toast(error.message):(toast("تم ربط الحساب ✓"),V.cust())}

async function attachPh(id){const x=C.CU.find(y=>y.id==id);if(!x)return;
const v=prompt("رقم موبايل "+x.name+" (01xxxxxxxxx)\nلو الرقم مسجل لعميل تاني هتتنقل النقاط عليه والسجلين يتدمجوا");if(v===null)return;
const ph=v.replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/\D/g,"");if(!/^01\d{9}$/.test(ph))return toast("الموبايل لازم 11 رقم ويبدأ بـ 01");
const{data,error}=await sb.rpc("attach_customer_phone",{p_customer:id,p_phone:ph});if(error)return toast(error.message);
toast(data==id?"تم ربط الرقم ✓":"الرقم كان مسجل — اتدمجت النقاط والسجل ✓");await V.cust();openCust(data)}

async function setRef(id){const v=prompt("رقم موبايل أو كود الدعوة بتاع اللي رشّح العميل ده");if(v===null||!v.trim())return;
const{data,error}=await sb.rpc("staff_set_referrer",{p_customer:id,p_key:v.replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d))});error?toast(error.message):toast("تم ✓ المُحيل: "+data+" — النقاط بعد أول فاتورة")}

async function custAv(id){const{data}=await sb.from("customers").select("name,avatar,birthday").eq("id",id).maybeSingle();const e=$("cav");if(!e||!data)return;if(!data.birthday){const wb=$("wa-bd");if(wb)wb.remove()}e.innerHTML=`<div style="display:flex;align-items:center;gap:12px;margin-top:10px">${avatarHtml(data,64,false)}${data.birthday?`<span class="m">🎂 ${new Date(data.birthday+"T00:00").toLocaleDateString("ar-EG",{day:"numeric",month:"long",year:"numeric"})}</span>`:""}${isAdm(me)?` <button class="btn s g" onclick="cuBday(${id},'${data.birthday||""}')">${data.birthday?"تعديل الميلاد":"إضافة ميلاد"}</button>`:""}</div><div id="cbd"></div>`}

function cuBday(id,cur){const e=$("cbd");if(!e)return;e.innerHTML=`<div class="chips" style="margin-top:8px"><input id="cbd_v" type="date" value="${esc(cur)}" max="${ymd(new Date())}" style="flex:1;margin:0"><button class="btn s" onclick="cuBdaySave(${id})">حفظ</button>${cur?`<button class="btn s g" onclick="cuBdaySave(${id},true)">مسح</button>`:""}</div>`}

async function cuBdaySave(id,clear){const v=clear?null:$("cbd_v").value;if(!clear&&!v)return toast("اختار التاريخ");const{error}=await sb.rpc("admin_set_customer_birthday",{p_customer:id,p_birthday:v});if(error)return toast(error.message);toast("اتحفظ ✓");custAv(id)}

// ===== آراء العملاء (للإدارة) =====
async function fbList(){const{data,error}=await sb.from("customer_feedback").select("id,message,created_at,read_at,reply,contact_phone,customers(name,phone)").order("created_at",{ascending:false}).limit(200);if(error)return toast(error.message);
const L=data||[],un=L.filter(x=>!x.read_at).length;
dsOpen("آراء العملاء"+(un?" ("+un+" جديدة)":""),L.length?L.map(x=>{const c=x.customers,d=new Date(x.created_at).toLocaleDateString("ar-EG");
return `<div class="box" style="margin-bottom:8px;${x.read_at?"opacity:.75":"border-color:var(--gold)"}"><div class="m">${c?"👤 "+esc(c.name)+(c.phone?" · <span dir=ltr>"+esc(c.phone)+"</span>":""):"🕶 من غير اسم"} · ${d}</div><div style="margin:6px 0;white-space:pre-wrap">${esc(x.message)}</div>${x.reply?`<div class="m" style="white-space:pre-wrap">↩️ ردك: ${esc(x.reply)}</div>`:""}${x.contact_phone?`<div class="m">📞 طلب تواصل: <span dir="ltr">${esc(x.contact_phone)}</span></div>`:""}<div class="chips">${c&&c.phone?waBtn(c.phone,0,"أهلاً "+c.name+" 👋\nشكرًا على رأيك في "+waSalon()+"، وصلتنا رسالتك:\n«"+x.message.slice(0,200)+"»\n"):""}${!c&&x.contact_phone?waBtn(x.contact_phone,0,"أهلاً 👋 بخصوص رسالتك لصالون "+waSalon().replace(/^صالون\s*/,"")+"، عايزين نساعدك."):""}<button class="btn s g" onclick="fbReply(${x.id})">${x.reply?"تعديل الرد":"رد"}</button>${x.read_at?"":`<button class="btn s g" onclick="fbRead(${x.id})">تمت القراءة</button>`}<button class="btn s g" style="color:var(--red)" onclick="fbDel(${x.id})">حذف</button></div></div>`}).join(""):`<p class="m">مفيش رسايل لسه.</p>`)}
async function fbRead(id){const{error}=await sb.from("customer_feedback").update({read_at:new Date().toISOString()}).eq("id",id);error?toast(error.message):fbList()}
async function fbDel(id){if(!confirm("حذف الرسالة دي؟"))return;const{error}=await sb.from("customer_feedback").delete().eq("id",id);error?toast(error.message):fbList()}
async function fbReply(id){const r=prompt("اكتب ردك (العميل هيشوفه في تطبيقه)");if(r==null)return;const t=r.trim();if(t.length<2)return toast("اكتب رد");const{error}=await sb.from("customer_feedback").update({reply:t,replied_at:new Date().toISOString(),read_at:new Date().toISOString()}).eq("id",id);error?toast(error.message):(toast("اتبعت الرد"),fbList())}
