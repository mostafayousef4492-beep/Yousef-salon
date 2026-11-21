/* features/customers/merge.js — دمج عميلين (نفس الشخص برقمين) في حساب واحد + أرقام تانية للحساب */

const cmDigits=s=>String(s||"").replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/\D/g,"");
const cmMissing=e=>e&&/customer_phones|customer_merge|customer_phone_add|schema cache|does not exist/i.test(e.message||"");
const cmSetup="شغّل ملف patch_customer_merge.sql في Supabase الأول";

// تحميل الأرقام التانية (للبحث وللعرض)
async function cmLoadAlias(){try{const{data,error}=await sb.from("customer_phones").select("phone,customer_id");if(error)return;C.alias={};(data||[]).forEach(r=>{(C.alias[r.customer_id]=C.alias[r.customer_id]||[]).push(r.phone)})}catch(e){}}

(()=>{const q=V.cust;if(!q)return;V.cust=async()=>{await q();await cmLoadAlias();if(tab=="cust"||$("cl")){const l=$("cl");if(l&&typeof custRows=="function")l.innerHTML=custRows()}}})();

// شاشة العميل: الأرقام التانية + أزرار الدمج
(()=>{const o=openCust;if(!o)return;window.openCust=async function(id){await o(id);
const can2=can("use_pos")||isAdm(me),mgr=isAdm(me);if(!can2)return;
await cmLoadAlias();const al=(C.alias||{})[id]||[],h=$("cav");if(!h)return;
h.insertAdjacentHTML("afterend",`<div id="cmx" class="box" style="margin:8px 0"><div class="m">أرقام تانية لنفس الحساب: ${al.length?al.map(p=>`<span dir="ltr" class="tag">${esc(p)}${mgr?` <a role="button" style="cursor:pointer;color:var(--red)" onclick="cmRemove('${p}',${id})">✕</a>`:""}</span>`).join(" "):"مفيش"}</div><div class="chips" style="margin-top:6px"><button class="btn s g" onclick="cmAddPhone(${id})">+ رقم تاني</button>${mgr?`<button class="btn s g" onclick="cmMergePick(${id})">🔗 دمج مع عميل مكرر</button>`:""}</div></div>`)}})();

async function cmAddPhone(id){const ph=cmDigits(await askInput("الرقم التاني للعميل (11 رقم)",""));if(!ph)return;
if(!/^01\d{9}$/.test(ph))return toast("الرقم لازم يبدأ بـ 01 ويبقى 11 رقم");
const{error}=await sb.rpc("customer_phone_add",{p_customer:id,p_phone:ph});if(error)return toast(cmMissing(error)?cmSetup:error.message);
toast("اتضاف الرقم التاني ✓");openCust(id)}

async function cmRemove(ph,id){if(!await askConfirm("شيل الرقم "+ph+" من الحساب؟ (مبيمسحش أي تاريخ)",{ok:"شيل"}))return;
const{error}=await sb.rpc("customer_phone_remove",{p_phone:ph});if(error)return toast(error.message);toast("اتشال ✓");openCust(id)}

// اختيار العميل المكرر
async function cmMergePick(id){const x=(C.CU||[]).find(y=>y.id==id);if(!x)return;
const t=(await askInput("دوّر على العميل المكرر (جزء من الاسم أو الرقم)")||"").trim();if(!t)return;
const td=cmDigits(t),L=(C.CU||[]).filter(y=>y.id!=id&&(y.name.includes(t)||(td&&(y.phone||"").includes(td)))).slice(0,8);
if(!L.length)return toast("مفيش عميل بالاسم أو الرقم ده");
const o=$("sheet");if(o)o.remove();const w=document.createElement("div");w.id="sheet";w.className="sheet-bg";w.onclick=e=>{if(e.target==w)svcClose()};
w.innerHTML=`<div class="sheet" role="dialog" aria-modal="true"><div class="sheet-h"><b>اختار العميل المكرر</b><button class="btn g s" onclick="svcClose()" aria-label="إغلاق">✕</button></div><p class="m">هيتدمج في «${esc(x.name)}» (الحساب الأساسي).</p>`+
L.map(y=>`<div class="row" role="button" style="cursor:pointer" onclick="cmMergeDo(${id},${y.id})"><div><b>${esc(y.name)}</b><div class="m" dir="ltr" style="text-align:right">${esc(y.phone||"")}</div><div class="m">${y.visits} زيارة · ${y.points} نقطة · دفع ${fm(y.spent)}</div></div></div>`).join("")+`</div>`;
document.body.appendChild(w)}

async function cmMergeDo(keep,drop){if(C.cmBusy)return;const k=(C.CU||[]).find(y=>y.id==keep),d=(C.CU||[]).find(y=>y.id==drop);if(!k||!d)return;
svcClose();
if(!await askConfirm("دمج «"+d.name+"» ("+(d.phone||"بدون رقم")+") داخل «"+k.name+"» ("+(k.phone||"بدون رقم")+")؟\n\nكل فواتيره وحجوزاته ونقاطه ("+d.points+" نقطة، "+d.visits+" زيارة) هتنتقل للحساب الأساسي، ورقمه هيبقى رقم تاني للحساب. العملية دي مبتترجعش (بيتسجل أرشيف كامل للمكرر).",{ok:"ادمج",danger:true}))return;
C.cmBusy=1;const{data,error}=await sb.rpc("customer_merge",{p_keep:keep,p_drop:drop});C.cmBusy=0;
if(error)return toast(cmMissing(error)?cmSetup:error.message);
toast("اتدمج ✓ (+"+(data&&data.points_added||0)+" نقطة)");await V.cust();openCust(keep)}
