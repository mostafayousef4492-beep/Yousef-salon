/* features/control/audit.js — الأرشيف الكامل لكل حركة (للمالك بس): إضافة / تعديل / حذف، مين عملها ووقتها وقبل/بعد */
const AU_T={invoices:"الفواتير",invoice_items:"أصناف الفواتير",open_invoices:"فواتير مفتوحة",expenses:"المصروفات",expense_categories:"أقسام المصروفات",cash_moves:"حركات الدرج",cash_closings:"قفل الدرج",staff_transactions:"حركات الموظفين",salary_payments:"صرف الرواتب",staff_settlements:"تسويات الموظفين",salary_day_adjustments:"تسويات الرواتب",appointments:"الحجوزات",appointment_services:"خدمات الحجز",attendance:"الحضور",services:"الخدمات",products:"المنتجات",bundles:"الباقات",bundle_items:"عناصر الباقات",customers:"العملاء",profiles:"الموظفين",app_settings:"الإعدادات",staff_pay_profile:"ملف أجر الموظف",staff_shifts:"مواعيد الشغل",staff_leaves:"الإجازات",purchases:"المشتريات",purchase_items:"أصناف المشتريات",supplier_payments:"مدفوعات الموردين",suppliers:"الموردين",stock_movements:"حركة المخزون",loyalty_rewards:"مكافآت الولاء",loyalty_redemptions:"استبدال النقاط",loyalty_ledger:"النقاط",discount_requests:"طلبات الخصم",late_rule:"طريقة خصم التأخير",reviews:"التقييمات"};
const AU_OP={insert:"➕ إضافة",update:"✏️ تعديل",delete:"🗑 حذف"};
const AU_CH=[["","الكل"],["invoices","الفواتير"],["expenses","المصروفات"],["cash_moves","الدرج"],["staff_transactions","حركات الموظفين"],["salary_payments","الرواتب"],["appointments","الحجوزات"],["attendance","الحضور"],["services","الخدمات"],["customers","العملاء"],["app_settings","الإعدادات"]];
function auditOpen(){if(me.role!="owner")return toast("للمالك بس");C.au={t:"",op:"",q:"",from:"",to:"",rows:[],more:false,busy:false};auDraw();auLoad(true)}
function auDraw(){const A=C.au;
put(`<h1>🗂 الأرشيف الكامل</h1><p class="m">أي إضافة أو تعديل أو حذف بيتسجل هنا تلقائيًا (مين عملها، وإمتى، وقبل/بعد). الأرشيف للمالك بس ومبيتعدلش ولا بيتمسح.</p>
<div class="chips">${AU_CH.map(c=>`<button class="chip ${A.t==c[0]?"sel":""}" onclick="C.au.t='${c[0]}';auLoad(true)">${c[1]}</button>`).join("")}</div>
<div class="chips">${[["","كل العمليات"],["insert","إضافة"],["update","تعديل"],["delete","حذف"]].map(c=>`<button class="chip ${A.op==c[0]?"sel":""}" onclick="C.au.op='${c[0]}';auLoad(true)">${c[1]}</button>`).join("")}</div>
<div style="display:flex;gap:6px;margin:8px 0"><input type="date" id="au_f" value="${A.from}" aria-label="من" style="margin:0"><input type="date" id="au_t" value="${A.to}" aria-label="إلى" style="margin:0"></div>
<div style="display:flex;gap:6px"><input id="au_q" placeholder="ابحث (اسم، ملاحظة، رقم، مبلغ...)" value="${esc(A.q)}" style="margin:0" onkeydown="if(event.key=='Enter')auFind()"><button class="btn s" onclick="auFind()">بحث</button></div>
<div id="au_l" style="margin-top:10px"></div>`)}
function auFind(){const A=C.au;A.q=($("au_q").value||"").trim();A.from=$("au_f").value;A.to=$("au_t").value;auLoad(true)}
async function auLoad(reset){const A=C.au;if(A.busy)return;A.busy=true;if(reset){A.rows=[];auDraw()}
  let q=sb.from("audit_log").select("*").order("at",{ascending:false}).range(A.rows.length,A.rows.length+49);
  if(A.t)q=q.eq("table_name",A.t);if(A.op)q=q.eq("op",A.op);
  if(A.q)q=q.ilike("summary","%"+A.q.replace(/[%,]/g,"")+"%");
  if(A.from)q=q.gte("at",new Date(A.from+"T00:00").toISOString());
  if(A.to){const d=new Date(A.to+"T00:00");d.setDate(d.getDate()+1);q=q.lt("at",d.toISOString())}
  const{data,error}=await q;A.busy=false;
  if(error)return $("au_l")&&($("au_l").innerHTML=`<p class="m">${esc(error.code=="42P01"||/audit_log/.test(error.message)?"شغّل patch_audit_archive.sql في Supabase الأول":error.message)}</p>`);
  A.rows=A.rows.concat(data||[]);A.more=(data||[]).length==50;auList()}
function auList(){const A=C.au,e=$("au_l");if(!e)return;
  e.innerHTML=A.rows.length?A.rows.map((r,i)=>`<button class="row" style="cursor:pointer;text-align:right;${r.op=="delete"?"border-color:var(--red)":""}" onclick="auOne(${i})"><div><b>${AU_OP[r.op]||r.op} · ${esc(AU_T[r.table_name]||r.table_name)}</b><div class="m">${esc((r.summary||"").slice(0,90))}</div><div class="m">${esc(r.actor_name||"")}${r.actor_role&&r.actor_role!="system"?" ("+esc(RL[r.actor_role]||r.actor_role)+")":""} · ${new Date(r.at).toLocaleString("ar-EG",{dateStyle:"short",timeStyle:"short"})}</div></div></button>`).join("")+(A.more?`<button class="btn g" style="width:100%;margin-top:8px" onclick="auLoad(false)">عرض أكتر</button>`:""):`<p class="m">مفيش حركات بالفلاتر دي.</p>`}
function auVal(v){if(v===null||v===undefined)return"—";if(typeof v=="object")return JSON.stringify(v);return String(v)}
function auOne(i){const r=C.au.rows[i];if(!r)return;
  const o=r.old_data||{},n=r.new_data||{},keys=[...new Set([...Object.keys(o),...Object.keys(n)])];
  const body=keys.map(k=>r.op=="update"?`<div class="row" style="display:block"><div class="m">${esc(k)}</div><div><span style="color:var(--red)">${esc(auVal(o[k]))}</span> ← <b>${esc(auVal(n[k]))}</b></div></div>`:`<div class="row" style="display:flex;justify-content:space-between;gap:10px"><span class="m">${esc(k)}</span><span dir="auto" style="text-align:left">${esc(auVal(r.op=="delete"?o[k]:n[k]))}</span></div>`).join("");
  dsOpen((AU_OP[r.op]||"")+" · "+(AU_T[r.table_name]||r.table_name),`<div class="m" style="margin-bottom:6px">${esc(r.actor_name||"")} · ${new Date(r.at).toLocaleString("ar-EG")} · رقم السجل ${esc(r.row_id||"-")}</div>${body||`<p class="m">مفيش تفاصيل.</p>`}`,{back:1})}
