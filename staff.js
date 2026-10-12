/* features/team/staff.js — الموظفين وحساب الموظف */

// ===== شاشة الموظف والإدارة =====

const mm=x=>x==null?"—":fm(x);

const KIND={advance:"سحب / سلفة",deduction:"خصم",bonus:"إيداع / مكافأة"};

C.rg="month";

const rangeOf=k=>{const a=new Date();a.setHours(0,0,0,0);const b=new Date(a);
if(k=="week"){a.setDate(a.getDate()-((a.getDay()+1)%7));b.setTime(a.getTime());b.setDate(b.getDate()+7)}
else if(k=="month"){a.setDate(1);b.setTime(a.getTime());b.setMonth(b.getMonth()+1)}else b.setDate(b.getDate()+1);
return[a.toISOString(),b.toISOString()]};

async function panel(id,owner){
C.reload=()=>panel(id,owner);const[f,t]=rangeOf(C.rg);
const[{data:sm,error:e1},{data:al},{data:tx},{data:rv},{data:sc},{data:at},{data:op},{data:sh},{data:lv}]=await Promise.all([
sb.rpc("staff_summary",{p_staff:id,p_from:f,p_to:t}),
sb.rpc("assist_log",{p_staff:id,p_from:f,p_to:t}),
sb.from("staff_transactions").select("*").eq("staff_id",id).gte("created_at",f).lt("created_at",t).order("created_at",{ascending:false}),
sb.from("reviews").select("id,rating,tags,note,created_at").eq("barber_id",id).order("created_at",{ascending:false}).limit(20),
sb.rpc("staff_schedule",{p_staff:id}),sb.from("attendance").select("*").eq("staff_id",id).gte("check_in",f).lt("check_in",t).order("check_in",{ascending:false}),sb.from("attendance").select("id,check_in").eq("staff_id",id).is("check_out",null).limit(1),sb.from("staff_shifts").select("*").eq("staff_id",id),sb.from("staff_leaves").select("*").eq("staff_id",id).gte("to_date",new Date().toISOString().slice(0,10)).order("from_date")]);
if(e1)return $("panel").innerHTML=`<p class="m">${esc(e1.message)}</p>`;
const s=sm?.[0]||{};C.pn={id,owner,f,t,s,tx:tx||[],al:al||[]};const avg=rv?.length?(rv.reduce((a,r)=>a+r.rating,0)/rv.length).toFixed(1):"-";
const S=owner?{f:1,s:1,r:1}:{f:can("view_own_finance"),s:can("view_own_schedule"),r:can("view_own_reviews")};const card=(l,v,c,a)=>`<div class="box kpi"${a?` role="button" tabindex="0" onclick="${a}" style="cursor:pointer"`:""}><div class="kpi-l">${l}</div><div class="kpi-v" style="color:${c||"inherit"}">${v}</div>${a?`<div class="m" style="font-size:11px">اضغط للتفاصيل</div>`:""}</div>`;
const hm=d=>new Date(d).toLocaleTimeString("ar-EG",{hour:"2-digit",minute:"2-digit",hourCycle:"h23"}),DN=["الأحد","الاثنين","الثلاثاء","الأربعاء","الخميس","الجمعة","السبت"];
const attOn=owner||can("use_attendance");
const attBox=!owner&&can("use_attendance")?`<div class="box" style="margin:10px 0;text-align:center">${op?.length?`<div class="m">حاضر من ${hm(op[0].check_in)}</div><button class="btn" style="width:100%" onclick="att('check_out')">تسجيل انصراف</button>`:`<button class="btn" style="width:100%;background:var(--ok)" onclick="att('check_in')">تسجيل حضور</button>`}</div>`:"";
C.attRows=Object.fromEntries((at||[]).map(r=>[String(r.id),r]));const hrs=(at||[]).reduce((a,r)=>a+((r.check_out?new Date(r.check_out):new Date())-new Date(r.check_in))/36e5,0),late=(at||[]).reduce((a,r)=>a+r.late_min,0);
const td=new Date().toLocaleDateString("en-CA"),attAdm=owner?`<div class="box" id="aa_box" style="margin:8px 0"><div class="m" id="aa_t" style="margin-bottom:6px">تسجيل حضور / انصراف يدوي (يوم فات أو نسيان)</div><label class="m">التاريخ</label><input id="aa_d" type="date" max="${td}" value="${td}"><label class="m">الحضور</label><input id="aa_i" type="time"><label class="m">الانصراف (سيبه فاضي لو لسه شغال)</label><input id="aa_o" type="time"><input id="aa_l" type="number" inputmode="numeric" min="0" placeholder="دقايق التأخير (اختياري، بيتحسب من الشيفت)"><input id="aa_n" placeholder="السبب (اختياري)"><div class="chips"><button class="btn" id="aa_b" style="flex:1" onclick="attSave('${id}')">حفظ</button><button class="btn g" id="aa_c" style="display:none" onclick="attCancel()">إلغاء</button></div><div class="m">لو الانصراف بعد نص الليل اكتب وقته عادي، هيتحسب لليوم اللي بعده.</div></div>`:"",attHist=attOn?`<h2>الحضور والانصراف</h2><div class="m" style="margin-bottom:6px">${(at||[]).length} يوم · ${hrs.toFixed(1)} ساعة · تأخير ${late} دقيقة</div>${(at||[]).map(r=>`<div class="row"><div><b>${new Date(r.check_in).toLocaleDateString("ar-EG",{weekday:"short",day:"numeric",month:"numeric"})}</b><div class="m">${hm(r.check_in)} ← ${r.check_out?hm(r.check_out):"لسه حاضر"}</div></div><div style="text-align:left">${r.source=="admin"?`<span class="tag">يدوي</span> `:r.edited_at?`<span class="tag">معدّل</span> `:""}${r.late_min?`<span class="tag" style="background:var(--red);color:#fff">متأخر ${r.late_min} د</span>`:`<span class="tag">في الميعاد</span>`}${r.note?`<div class="m">${esc(r.note)}</div>`:""}${owner?`<div style="margin-top:4px"><button class="btn s g" onclick="attEdit('${r.id}')">${r.check_out?"تعديل":"تسجيل انصراف"}</button> <button class="btn s g" onclick="attDel('${r.id}')">حذف</button></div>`:""}</div></div>`).join("")}`:"";
const shBox=`<h2>جدول شغلي</h2>${sh?.length?[0,1,2,3,4,5,6].map(d=>{const x=sh.find(y=>y.weekday==d);return x?`<div class="row"><b>${DN[d]}</b><span>${x.is_off?"إجازة":x.start_time.slice(0,5)+" ← "+x.end_time.slice(0,5)}</span></div>`:""}).join(""):`<p class="m">لسه مفيش شيفت محدد.</p>`}${lv?.length?`<div class="m">إجازات جاية:</div>`+lv.map(l=>`<div class="row"><span>${l.from_date} ← ${l.to_date}</span><span class="m">${esc(l.reason||"")}</span></div>`).join(""):""}`;
$("panel").innerHTML=`${attBox}<div class="chips">${[["day","اليوم"],["week","الأسبوع"],["month","الشهر"]].map(x=>`<button class="chip ${C.rg==x[0]?"sel":""}" onclick="C.rg='${x[0]}';C.reload()">${x[1]}</button>`).join("")}</div>
<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">${s.who=="assistant"?card("راتب الفترة",mm(s.salary),"var(--ok)","pnNet()")+card("خدمات شاركت فيها",s.assisted??0,"","pnAl()"):card("مبيعاتي"+(s.cuts==null?"":" ("+s.cuts+" زبون)"),mm(s.sales),"","pnInv()")+card("عمولتي",mm(s.commission),"var(--ok)","pnInv()")+(s.assistant_cuts==null?"":card("خصم مساعد",mm(s.assistant_cuts),"var(--red)","pnAl()"))+(+s.salary>0?card("راتب ثابت",mm(s.salary),"var(--ok)","pnNet()"):"")}${card("مكافآت",mm(s.bonuses),"var(--ok)","pnTx('bonus')")}${card("سحب",mm(s.advances),"var(--red)","pnTx('advance')")}${card("خصومات",mm(s.deductions),"var(--red)","pnTx('deduction')")}${card("الصافي المستحق",mm(s.net),"var(--brass)","pnNet()")}</div>
${S.f?(setTimeout(()=>stmtLoad(id),0),`<div id="stmt"></div>`):""}${owner?`<h2>تسجيل حركة</h2><div class="box"><select id="tk">${Object.entries(KIND).map(k=>`<option value="${k[0]}">${k[1]}</option>`).join("")}</select><input id="ta" type="number" inputmode="decimal" placeholder="المبلغ"><input id="tn" placeholder="ملاحظة (اختياري)"><button class="btn" onclick="addTx('${id}')">حفظ الحركة</button></div>`:""}
${owner?(setTimeout(()=>{stlLoad(id);dwgLoad(id)},0),`<div id="stl"></div><div id="dwg"></div>`):""}
${al?.length?`<h2>${s.who=="assistant"?"الخدمات اللي شاركت فيها":"خصم المساعدين على خدماتك"}</h2>`+al.map(x=>`<div class="row"><div><b>#${x.inv_no}</b> · ${esc(x.service_name)} · ${fm(x.price)}<div class="m">${new Date(x.created).toLocaleDateString("ar-EG")} · ${s.who=="assistant"?"مع الحلاق "+esc(x.barber_name||"—"):"اتخصم للمساعد "+esc(x.assistant_name)}</div></div>${s.who=="assistant"?"":`<b style="color:var(--red)">- ${fm(x.cut)}</b>`}</div>`).join(""):""}
<h2 ${S.f?"":"hidden"}>الحركات</h2>${tx?.length?tx.map(x=>`<div class="row"><div><b style="color:${x.kind=="bonus"?"var(--ok)":"var(--red)"}">${KIND[x.kind]}</b> · ${fm(x.amount)}<div class="m">${new Date(x.created_at).toLocaleDateString("ar-EG")} ${esc(x.note||"")}</div></div>${owner?`<button class="btn s g" onclick="delTx(${x.id})">حذف</button>`:""}</div>`).join(""):`<p class="m" ${S.f?"":"hidden"}>مفيش حركات في الفترة دي.</p>`}
<h2 ${S.s?"":"hidden"}>دور زباينك (اليوم والجاي)</h2>${sc?.length?sc.map(a=>`<div class="row"><div><b>#${a.ticket_no}</b> · ${esc(a.customer_name)}${a.customer_phone?" · "+esc(a.customer_phone):""}<div class="m">${a.day} · ${PLB[a.period]} · ${esc(a.services)} · ${fm(a.total)}</div></div><div style="text-align:left"><span class="tag">${a.finished?"خلصت":a.called&&a.status=="upcoming"?"مستدعى"+(a.eta=="on_way"?" (في الطريق)":""):ST[a.status]}</span>${!owner?`<br>${a.status!="in_service"&&!a.called?`<button class="btn s" onclick="tk('call_ticket',${a.id})">استدعاء</button> `:""}${a.status!="in_service"?`<button class="btn s g" onclick="myS(${a.id},'in_service')">ابدأ</button>`:!a.finished?`<button class="btn s" onclick="tk('finish_ticket',${a.id})">خلصت</button>`:""}`:""}</div></div>`).join(""):`<p class="m" ${S.s?"":"hidden"}>مفيش زباين محجوزة.</p>`}
${attAdm}${attHist}${attOn?shBox:""}<h2 ${S.r?"":"hidden"}>تقييماتي (المتوسط ★ ${avg})</h2>${rv?.length?rv.map(r=>`<div class="row" style="display:block"><b style="color:var(--brass)">${"★".repeat(r.rating)}</b> <span class="m">${(r.tags||[]).map(esc).join(" · ")}</span>${r.note?`<div>${esc(r.note)}</div>`:""}${owner?`<button class="btn s g" style="margin-top:4px" onclick="ownerDel('reviews','${r.id}',()=>C.reload(),'تحذف التقييم ده؟')">حذف</button>`:""}</div>`).join(""):`<p class="m" ${S.r?"":"hidden"}>لسه مفيش تقييمات.</p>`}`}

async function addTx(id){const a=+$("ta").value;if(!(a>0))return toast("اكتب مبلغ صحيح");
const{error}=await sb.from("staff_transactions").insert({staff_id:id,kind:$("tk").value,amount:a,note:$("tn").value});error?toast(error.message):(toast("تم الحفظ"),C.reload())}

async function ownerDel(t,id,after,msg){if(!confirm(msg||"حذف السجل ده؟ (هيتسجّل في سجل المحذوفات)"))return;let{error}=await sb.rpc("admin_delete_record",{p_table:t,p_id:String(id)});if(error&&(error.code=="PGRST202"||/Could not find the function/i.test(error.message||""))){({error}=await sb.from(t).delete().eq("id",id))}if(error)return toast(error.message);toast("اتحذف ✓");after&&after()}

function delTx(id){return ownerDel("staff_transactions",id,()=>C.reload(),"حذف الحركة؟")}

async function myS(id,st){const{error}=await sb.rpc("set_my_appt_status",{p_id:id,p_status:st});error?toast(error.message):C.reload()}

V.me=()=>{put(`<h1>شاشتي — ${esc(me.full_name)}</h1>${me.role=="barber"?`<div id="bnow"></div>`:""}<div id="panel"></div>`);if(me.role=="barber")barberNow();panel(me.id,false)};

async function barberNow(){const t=new Date().toLocaleDateString("en-CA"),{data,error}=await sb.from("appointments").select("id,ticket_no,status,customers(name),appointment_services(services(name))").eq("day",t).eq("barber_id",me.id).in("status",["upcoming","checked_in","in_service"]).order("ticket_no");const e=$("bnow");if(!e||error)return;
const sv=a=>(a.appointment_services||[]).map(x=>esc(x.services?.name||"")).filter(Boolean).join(" + "),nm=a=>esc(a.customers?.name||"عميل"),cur=data.find(a=>a.status=="in_service"),q=data.filter(a=>a.status!="in_service"),nx=q.find(a=>a.status=="checked_in")||q[0],ca=can("manage_appts");
e.innerHTML=`<div class="box"><div class="cc-l">العميل الحالي</div>${cur?`<div class="cc-n" style="font-size:1.4rem">${nm(cur)}</div><div class="m">${sv(cur)||"—"} · #${cur.ticket_no}</div>`:`<div class="m">مفيش حد على الكرسي دلوقتي</div>`}</div>
<div class="box" style="margin-top:8px"><div class="cc-l">العميل التالي</div>${nx?`<b>${nm(nx)}</b> <span class="m">#${nx.ticket_no} · ${nx.status=="checked_in"?"وصل وبينتظر":"لسه ما وصلش"}${sv(nx)?" · "+sv(nx):""}</span>${ca&&!cur&&nx.status=="checked_in"?`<button class="btn s" style="margin-top:8px" onclick="setS(${nx.id},'in_service')">ابدأ الخدمة</button>`:""}`:`<div class="m">مفيش حد في الانتظار</div>`}</div>${q.length>1?`<div class="m" style="margin-top:6px">و ${q.length-1} كمان في الانتظار</div>`:""}`}

V.team=async()=>{
let{data}=await sb.from("profiles").select(PCOLS).neq("role","customer").order("role").order("full_name");if(me.role=="manager")data=(data||[]).filter(p=>p.role!="owner"&&p.role!="manager");await addSalary(data);C.tmN=Object.fromEntries((data||[]).map(p=>[p.id,p.full_name]));
put(`<h1>الموظفين</h1><h2>إضافة موظف جديد</h2><div class="box"><input id="ns_n" placeholder="اسم الموظف"><input id="ns_e" type="text" placeholder="كود الموظف (مثلاً 101) - هيدخل بيه"><input id="ns_p" type="text" placeholder="كلمة سر (6 حروف على الأقل)"><div class="chips" style="align-items:center"><select id="ns_r" style="width:auto;margin:0"><option value="barber">حلاق</option><option value="assistant">مساعد</option><option value="cashier">كاشير</option>${me.role=="owner"?`<option value="manager">مدير</option>`:""}</select><input id="ns_c" type="number" value="${C.cfg.default_commission||40}" style="width:80px;margin:0" aria-label="العمولة"><span class="m">% عمولة (للمساعد: نسبة خصم المحل من خدماته)</span></div><input id="ns_s" type="number" inputmode="decimal" placeholder="الراتب الشهري (اختياري)"><button class="btn" onclick="addStaff()">إضافة الموظف</button></div><h2>كل الحسابات</h2>`+data.map(p=>`<div class="row" style="display:block"><b>${esc(p.full_name)}</b> <span class="tag">${RL[p.role]}</span>${p.code?` <span class="m">كود ${esc(p.code)}</span>`:""}
<div class="chips" style="margin-top:8px;align-items:center"><select id="r${p.id}" style="width:auto;margin:0">${Object.entries(RL).filter(r=>me.role=="owner"||!["owner","manager","customer"].includes(r[0])).map(r=>`<option value="${r[0]}" ${p.role==r[0]?"selected":""}>${r[1]}</option>`).join("")}</select><input id="c${p.id}" type="number" value="${p.commission_pct}" style="width:80px;margin:0" aria-label="العمولة %"><span class="m">%</span>${p.role!="owner"?`<input id="s${p.id}" type="number" value="${+p.salary||0}" style="width:100px;margin:0" aria-label="الراتب الشهري"><span class="m">راتب شهري</span>`:""}<button class="btn s" onclick="saveP('${p.id}')">حفظ</button>${["barber","cashier","assistant"].includes(p.role)?`<button class="btn s g" onclick="C.pb='team';openPerms('${p.id}')">الشاشة والصلاحيات</button><button class="btn s g" onclick="openShift('${p.id}')">الشيفت والإجازة</button>`:""}${["barber","assistant"].includes(p.role)?`<button class="btn s g" onclick="openStaff('${p.id}','${esc(p.full_name)}')">الحساب</button>`:""}${["barber","cashier","assistant"].includes(p.role)&&p.id!=me.id?`<button class="btn s g" style="color:var(--red)" onclick="delStaff('${p.id}')">حذف</button>`:""}</div></div>`).join(""))};

const DLB={attendance:"حضور وانصراف",staff_transactions:"سحب وخصومات ومكافآت",salary_payments:"مرتبات مصروفة",appointments:"حجوزات",invoices:"فواتير",reviews:"تقييمات",staff_settlements:"تسويات حساب",staff_target_awards:"مكافآت تارجت",salary_day_adjustments:"تسويات أجر يومي",loyalty_ledger:"نقاط ولاء"};

async function delStaff(id,force){const n=(C.tmN||{})[id]||"الموظف";if(!force&&!confirm("حذف "+n+" نهائيًا؟\nحسابه هيتمسح ومش هيقدر يدخل تاني."))return;const{data,error}=await sb.rpc("admin_delete_staff",{p_staff:id,p_force:!!force});if(error)return toast(error.message);if(data?.needs_force){const t=Object.entries(data.history||{}).map(([k,v])=>"• "+(DLB[k]||k)+": "+v).join("\n");if(!confirm("عند "+n+" سجلات مرتبطة بيه:\n"+t+"\n\nلو كمّلت، السجلات دي هتتمسح أو تتفصل عنه، وأرقام التقارير والأرباح القديمة ممكن تتغيّر.\nتكمّل الحذف النهائي؟"))return;return delStaff(id,true)}toast("اتحذف "+n+" ✓");V.team()}

async function saveP(id){const u={role:$("r"+id).value,commission_pct:+$("c"+id).value||0};if($("s"+id))u.salary=+$("s"+id).value||0;const{error}=await sb.from("profiles").update(u).eq("id",id);error?toast(error.message):(toast("تم الحفظ"),V.team())}

function openStaff(id,name){put(`<button class="btn g s" style="margin-top:12px" onclick="V.team()">‹ رجوع</button><h1>حساب ${name}</h1><div id="panel"></div>`);panel(id,true)}

async function addStaff(){
const n=$("ns_n").value.trim(),e=(x=>x.includes("@")?x:x+"@staff.abu-yousef-salon.com")($("ns_e").value.trim()),pw=$("ns_p").value,r=$("ns_r").value,c=+$("ns_c").value||0,sal=+($("ns_s")?.value)||0;
if(!n||!e||pw.length<6)return toast("اكمل الاسم والبريد وكلمة سر 6 حروف");
const tmp=supabase.createClient(SUPABASE_URL,SUPABASE_KEY,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false,storageKey:"tmp-signup"}});
const{data,error}=await tmp.auth.signUp({email:e,password:pw,options:{data:{full_name:n}}});
if(error)return toast(error.message);
if(!data.user||!(data.user.identities||[]).length)return toast("البريد ده مسجل قبل كده، غيّر دوره من القائمة تحت");
const{error:e2}=await sb.from("profiles").update({role:r,commission_pct:c,full_name:n,code:e.split("@")[0],...(sal?{salary:sal}:{})}).eq("id",data.user.id);
if(e2)return toast(e2.message);
toast("تمت إضافة "+n+" ✓ — كوده "+e.split("@")[0]);V.team()}

// ---- شاشة الموظف (مبيعاتي / عمولتي / سحب ...) ----

function pnInv(){const P=C.pn;if(!P)return;if(!(isAdm(me)||can("view_invoices")))return toast("عرض الفواتير مش متاح لحسابك");dsInv({t:P.owner?"فواتير الحلاق في الفترة":"فواتيري في الفترة",from:P.f,to:P.t,barber:P.id})}

function pnTx(k){const P=C.pn;if(!P)return;const L=(P.tx||[]).filter(x=>x.kind==k);dsOpen({bonus:"المكافآت",advance:"السحب",deduction:"الخصومات"}[k]+" في الفترة",L.length?`<div class="m" style="margin-bottom:8px">${L.length} حركة · <b>${fm(sumOf(L,x=>x.amount))}</b></div>`+L.map(x=>dsRow(`<b>${fm(x.amount)}</b>`,dsT(x.created_at)+(x.note?" · "+esc(x.note):""))).join(""):dsEmpty())}

function pnAl(){const P=C.pn;if(!P)return;const as=P.s.who=="assistant",L=P.al||[];dsOpen(as?"الخدمات اللي شاركت فيها":"خصم المساعدين على خدماتك",L.length?L.map(x=>dsRow(`<b>#${x.inv_no}</b> · ${esc(x.service_name)} · ${fm(x.price)}`,new Date(x.created).toLocaleDateString("ar-EG")+" · "+(as?"مع الحلاق "+esc(x.barber_name||"—"):"اتخصم للمساعد "+esc(x.assistant_name)),as?"":`<b style="color:var(--red)">- ${fm(x.cut)}</b>`)).join(""):dsEmpty())}

function pnNet(){const P=C.pn;if(!P)return;const s=P.s,L=[["العمولة",+s.commission||0],["راتب ثابت",+s.salary||0],["مكافآت",+s.bonuses||0],["سحب",-(+s.advances||0)],["خصومات",-(+s.deductions||0)]].filter(r=>r[1]);
  dsOpen("إزاي طلع الصافي",`<div class="box">${L.map(r=>dsKv(r[0],fm(r[1]))).join("")}${dsKv("الصافي المستحق",fm(+s.net||0),1)}</div><div class="m" style="margin-top:6px">العمولة محسوبة بعد خصم نسبة المساعدين.</div>`)}
