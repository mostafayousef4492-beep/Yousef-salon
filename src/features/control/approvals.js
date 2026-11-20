/* features/control/approvals.js — مركز الموافقات: كل اللي محتاج قرار في مكان واحد (خصومات + طلبات إلغاء/طلبات حرة) */

const AP_ST={approved:"✅ اتوافق",rejected:"⛔ اترفض",cancelled:"↩️ اتسحب"};
const apMissing=e=>e&&/approvals_inbox|approval_request|approval_decide/i.test(e.message||"")&&/(does not exist|schema cache|Could not find)/i.test(e.message||"");
const apWhen=t=>t?new Date(t).toLocaleString("ar-EG",{dateStyle:"short",timeStyle:"short"}):"";

V.apr=async function(){
const{data,error}=await sb.rpc("approvals_inbox");
if(error)return put(`<h1>الموافقات</h1><p class="m">${apMissing(error)?"الميزة لسه مش متفعّلة: شغّل ملف patch_approvals.sql في Supabase الأول.":esc(error.message)}</p>`);
C.apr=data||{};const D=C.apr.discounts||[],R=C.apr.requests||[],H=C.apr.recent||[],own=!!C.apr.owner;
put(`<h1>الموافقات</h1>
<div style="display:flex;gap:6px;flex-wrap:wrap;margin:6px 0"><button class="btn s" onclick="aprAsk('custom')">+ طلب موافقة من المالك</button><button class="btn s g" onclick="V.apr()">تحديث</button>${me.role=="owner"||me.role=="manager"?`<button class="btn s g" onclick="go('auto')">⚙️ التشغيل الذاتي</button>`:""}</div>
<p class="m">${own?"كل الطلبات اللي محتاجة قرارك. القرار بتاعك، والنظام بينفّذ بس بعد موافقتك وبيسجّل كل حاجة في الأرشيف.":"طلباتك للمالك وحالتها. الإلغاء مبيتنفّذش غير بعد موافقته."}</p>
${D.length?`<h2>طلبات خصم (${D.length})</h2>`+D.map(r=>`<div class="row"><div><b>خصم ${+r.pct}% · كرسي ${r.chair||"-"}</b><div class="m">${esc(r.by||"")}${r.subtotal?" · على "+fm(r.subtotal):""}${r.reason?" · "+esc(r.reason):""}</div><div class="m">${apWhen(r.at)}</div></div><div><button class="btn s" onclick="aprDisc(${r.id},true)">موافقة</button> <button class="btn s g" onclick="aprDisc(${r.id},false)">رفض</button></div></div>`).join(""):""}
${R.length?`<h2>طلبات (${R.length})</h2>`+R.map(r=>`<div class="row"><div><b>${esc(r.title)}</b><div class="m">${esc(r.by||"")} · ${apWhen(r.at)}</div><div class="m">السبب: ${esc(r.reason)}</div></div><div>${own?`<button class="btn s" onclick="aprDecide(${r.id},true)">موافقة</button> <button class="btn s g" onclick="aprDecide(${r.id},false)">رفض</button>`:r.mine?`<button class="btn s g" onclick="aprCancel(${r.id})">سحب الطلب</button>`:""}</div></div>`).join(""):""}
${!D.length&&!R.length?`<p class="m" style="margin-top:12px">مفيش طلبات مستنية قرار ✓</p>`:""}
${H.length?`<h2>آخر القرارات</h2>`+H.map(r=>`<div class="row"><div><b>${esc(r.title)}</b><div class="m">${AP_ST[r.status]||esc(r.status)} · ${esc(r.by||"")} · ${apWhen(r.at)}${r.note?" · "+esc(r.note):""}</div></div></div>`).join(""):""}`)};

// طلب جديد: kind = void_invoice (ref = رقم الفاتورة الداخلي) أو custom (طلب حر بعنوان)
async function aprAsk(kind,ref){if(C.aprBusy)return;let title="";
if(kind=="custom"){title=(await askInput("اكتب الطلب (مثال: تغيير سعر خدمة، سلفة استثنائية...)")||"").trim();if(!title)return}
const why=(await askInput(kind=="void_invoice"?"سبب طلب إلغاء الفاتورة:":"سبب الطلب:")||"").trim();if(!why)return;
C.aprBusy=1;const{error}=await sb.rpc("approval_request",{p_kind:kind,p_ref:ref==null?null:String(ref),p_title:title,p_reason:why});C.aprBusy=0;
error?toast(apMissing(error)?"شغّل patch_approvals.sql الأول":error.message):(toast("اتبعت للمالك ⏳"),tab=="apr"&&V.apr())}

async function aprDecide(id,ok){if(C.aprBusy)return;const note=await askInput(ok?"ملاحظة (اختياري):":"سبب الرفض (اختياري):");if(note===null)return;
if(ok&&!await askConfirm("تأكيد الموافقة؟ الإجراء هيتنفّذ فورًا."))return;
C.aprBusy=1;const{error}=await sb.rpc("approval_decide",{p_id:id,p_ok:ok,p_note:note||null});C.aprBusy=0;
error?toast(error.message):(toast(ok?"تمت الموافقة ✓":"اتم الرفض"),V.apr())}

async function aprCancel(id){if(!await askConfirm("سحب الطلب؟"))return;const{error}=await sb.rpc("approval_cancel",{p_id:id});error?toast(error.message):(toast("اتسحب"),V.apr())}

async function aprDisc(id,ok){const{error}=await sb.rpc("decide_discount",{p_id:id,p_ok:ok});error?toast(error.message):(toast(ok?"تمت الموافقة ✓":"اتم الرفض"),V.apr())}

// طلبات حذف حساب عميل (للمالك): تنفيذ = إخفاء هوية العميل مع بقاء الفواتير
const apV0=V.apr;
V.apr=async function(){await apV0();if(tab!="apr"||me.role!="owner")return;
try{const{data,error}=await sb.rpc("deletion_requests_list");if(error||!data||!data.length||tab!="apr")return;C.adr=data;const el=$("app");if(!el)return;
el.insertAdjacentHTML("beforeend",`<h2>طلبات حذف حساب (${data.length})</h2>`+data.map((r,i)=>`<div class="row"><div><b>${esc(r.name||"")}</b> <span class="m" dir="ltr">${esc(r.phone||"")}</span><div class="m">${r.visits||0} زيارة · ${r.points||0} نقطة · ${apWhen(r.at)}</div></div><div><button class="btn s g" onclick="adrDo(${i},true)">تنفيذ الحذف</button> <button class="btn s g" onclick="adrDo(${i},false)">رفض</button></div></div>`).join("")+`<p class="m">التنفيذ بيخفي هوية العميل ويمسح صوره ورسايله وتفضيلاته، والفواتير بتفضل من غير اسم. حساب الدخول نفسه بيتشال من لوحة Supabase (Authentication) بعد التنفيذ.</p>`)}catch(e){}};
async function adrDo(i,ok){const r=(C.adr||[])[i];if(!r||C.aprBusy)return;
if(ok&&!await askConfirm("تنفيذ حذف بيانات «"+r.name+"»؟ العملية دي مش بترجع."))return;
let note=null;if(!ok){note=await askInput("سبب الرفض (اختياري):");if(note===null)return}
C.aprBusy=1;const{data,error}=ok?await sb.rpc("deletion_execute",{p_id:r.id}):await sb.rpc("deletion_reject",{p_id:r.id,p_note:note||null});C.aprBusy=0;
if(error)return toast(error.message);
if(ok&&data&&data.auth_user_id)try{await navigator.clipboard.writeText(data.auth_user_id)}catch(e){}
toast(ok?"اتنفّذ ✓ — لو عايز تشيل حساب الدخول: Supabase ← Authentication، ومعرّفه اتنسخ":"اترفض");V.apr()}
