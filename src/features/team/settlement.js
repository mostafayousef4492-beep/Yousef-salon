/* features/team/settlement.js — تسوية حساب الموظف */

// ---- تسوية الحساب (في شاشة حساب الموظف للمالك) ----

async function stlLoad(id){if(!$("stl"))return;const[{data:pv,error},{data:hs}]=await Promise.all([sb.rpc("staff_settlement_preview",{p_staff:id}),sb.from("staff_settlements").select("*").eq("staff_id",id).order("created_at",{ascending:false}).limit(10)]);
  if(!$("stl"))return;if(error)return $("stl").innerHTML=`<h2>تسوية الحساب</h2><p class="m">${esc(error.message)}</p>`;const bal=+pv.balance;C.stl={id,pv};
  $("stl").innerHTML=`<h2>تسوية الحساب</h2><div class="box"><div class="m">من ${new Date(pv.from).toLocaleString("ar-EG")} لحد دلوقتي</div><div style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:8px">${kc("الصافي",fm(pv.net),"","stlNet()")}${kc("اتصرف",fm(pv.paid),"","stlPaid()")}${kc("الرصيد",fm(bal),bal>0?"var(--red)":"var(--ok)","stlBal()")}</div><input id="st_a" type="number" inputmode="decimal" value="${bal>0?bal:""}" placeholder="مبلغ التسوية"><input id="st_r" placeholder="سبب التسوية (مطلوب)"><label class="row" style="cursor:pointer"><span>سجّل صرف كاش فعلي (يخصم من الخزنة)</span><input type="checkbox" id="st_p" style="width:22px;height:22px;margin:0"></label><select id="st_s">${paySrc("drawer")}</select><button class="btn" onclick="doSettle('${id}')">تنفيذ التسوية</button></div>${(hs||[]).map(h=>`<div class="row"><div><b>${fm(h.amount)}</b> · ${esc(h.reason)}<div class="m">${new Date(h.created_at).toLocaleString("ar-EG")} · الرصيد ${fm(h.balance_before)} ← ${fm(h.balance_after)}${h.salary_payment_id?" · اتسجّل صرف":""}</div></div><button class="btn s g" onclick="undoStl('${h.id}','${id}')">تراجع</button></div>`).join("")}`}

async function undoStl(sid,staff){if(!confirm("تلغي التسوية دي؟\nلو فيها صرف كاش هيتمسح كمان، والرصيد هيتحسب من جديد."))return;const{error}=await sb.rpc("admin_undo_settlement",{p_id:String(sid)});if(error)return toast(error.message);toast("اتلغت التسوية ✓");stlLoad(staff)}

async function doSettle(id){const a=parseFloat($("st_a").value),r=$("st_r").value.trim();if(!(a>0))return toast("اكتب مبلغ التسوية");if(!r)return toast("اكتب سبب التسوية");if(!confirm("تنفّذ التسوية؟ بتتسجل كسجل تدقيق ومينفعش تتمسح."))return;
  const{error}=await sb.rpc("settle_staff_account",{p_staff:id,p_amount:a,p_reason:r,p_record_payment:$("st_p").checked,p_paid_from:$("st_s").value});error?toast(error.message):(toast("تمت التسوية ✓"),stlLoad(id))}

// ================= دور المدير + كروت المالية =================
// المدير = كل صلاحيات المالك ما عدا: الحذف، مركز التحكم، وتعديل المالك/مدير تاني (الداتابيز نفسها بتمنعها).

const MGR_HIDE=/^\s*(?:svcClose\(\);\s*)?(delC|delStaff|ownerDel|delMove|delExp|delPay|undoStl|voidPur|doReset|cancelAw|delInv|delClose|delLeave)\(/;

let _mh=0;

function mgrHide(){if(_mh||!me||me.role!="manager")return;_mh=1;try{document.querySelectorAll("[onclick]").forEach(b=>{if(MGR_HIDE.test(b.getAttribute("onclick")||""))b.remove()})}finally{_mh=0}}

(()=>{const A=document.getElementById("app");if(A&&window.MutationObserver)new MutationObserver(mgrHide).observe(A,{childList:true,subtree:true})})();

// ---- المالية: المستحق / اتصرف / المتبقي ----

function fpList(t,rows,sub,end){dsOpen(t,rows.length?rows.map(r=>`<button class="row" style="cursor:pointer;width:100%;text-align:right" onclick="svcClose();openStaff('${r.s.id}','${esc(r.s.full_name)}')"><div><b>${esc(r.s.full_name)}</b><div class="m">${RL[r.s.role]||r.s.role}${sub(r)}</div></div><div style="text-align:left"><b>${end(r)}</b></div></button>`).join("")+`<div class="m" style="margin-top:6px">اضغط على الموظف تفتح حسابه بالتفصيل.</div>`:dsEmpty("مفيش حاجة هنا."))}

function fpDue(){const F=C.fp;if(!F)return;fpList("المستحق — "+mAr(F.m),F.rows.filter(r=>r.due).sort((a,b)=>b.due-a.due),r=>" · اتصرف "+fm(r.pd),r=>fm(r.due))}

function fpRem(){const F=C.fp;if(!F)return;fpList("المتبقي — "+mAr(F.m),F.rows.filter(r=>r.rem>0).sort((a,b)=>b.rem-a.rem),r=>" · مستحق "+fm(r.due)+" · اتصرف "+fm(r.pd),r=>`<span style="color:var(--red)">${fm(r.rem)}</span>`)}

function fpPaid(){const F=C.fp;if(!F)return;const P=F.pays||[];dsOpen("اللي اتصرف — "+mAr(F.m),P.length?`<div class="m" style="margin-bottom:8px">${P.length} عملية · <b>${fm(sumOf(P,x=>x.amount))}</b></div>`+P.map(p=>dsRow(`<b>${esc(p.profiles?.full_name||"—")}</b>`,`${p.paid_on} · ${p.paid_from=="drawer"?"من الدرج":"من برا الدرج"}${p.note?" · "+esc(p.note):""}`,`<b>${fm(p.amount)}</b>`)).join(""):dsEmpty("مفيش صرف الشهر ده."))}

// ---- تسوية حساب موظف: الصافي / اتصرف / الرصيد ----

async function stlNet(){const S=C.stl;if(!S)return;dsLoad("إزاي طلع الصافي");
  const{data,error}=await sb.rpc("staff_summary",{p_staff:S.id,p_from:S.pv.from,p_to:S.pv.to});if(error)return dsOpen("إزاي طلع الصافي",dsEmpty(error.message));
  const s=(data||[])[0]||{},L=[["العمولة",+s.commission||0],["راتب ثابت",+s.salary||0],["مكافآت",+s.bonuses||0],["سحب",-(+s.advances||0)],["خصومات",-(+s.deductions||0)]].filter(r=>r[1]);
  dsOpen("إزاي طلع الصافي",`<div class="m" style="margin-bottom:6px">من ${dsT(S.pv.from)} لحد دلوقتي</div><div class="box">${L.map(r=>dsKv(r[0],fm(r[1]))).join("")}${dsKv("الصافي",fm(+s.net||0),1)}</div>`)}

function stlPaid(){const S=C.stl;if(!S)return;dsQ("اللي اتصرف من آخر تسوية",sb.from("salary_payments").select("amount,paid_on,paid_from,note,created_at").eq("staff_id",S.id).gt("created_at",S.pv.from).order("created_at",{ascending:false}),L=>`<div class="m" style="margin-bottom:8px">${L.length} عملية · <b>${fm(sumOf(L,x=>x.amount))}</b></div>`+L.map(p=>dsRow(`<b>${fm(p.amount)}</b>`,`${p.paid_on} · ${p.paid_from=="drawer"?"من الدرج":"من برا الدرج"}${p.note?" · "+esc(p.note):""}`)).join(""))}

function stlBal(){const S=C.stl;if(!S)return;const b=+S.pv.balance;dsOpen("الرصيد",`<div class="box">${dsKv("الصافي المستحق",fm(+S.pv.net||0))}${dsKv("اتصرف",fm(-(+S.pv.paid||0)))}${dsKv("الرصيد",fm(b),1)}</div><div class="m" style="margin-top:6px">${b>0?"لسه له فلوس عند الصالون.":b<0?"واخد أكتر من مستحقه.":"الحساب متساوي."}</div>`)}
