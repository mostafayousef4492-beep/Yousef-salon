/* features/catalog/materials.js — خامات الخدمات (كريم/ماسك/شفرات...) وخصمها التلقائي عند قفل الفاتورة */

const matQ=v=>{if(v===null)return null;const n=Number(String(v).trim().replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace("٫","."));return Number.isFinite(n)?n:NaN};
const matFm=n=>{n=Number(n)||0;return String(Math.round(n*1000)/1000)};
const matMissing=e=>e&&/materials|service_materials|material_/i.test(e.message||"")&&/(does not exist|schema cache|Could not find)/i.test(e.message||"");

V.mat=async function(){
const mgr=me.role=="owner"||me.role=="manager";
const[m,sm,sv]=await Promise.all([sb.from("materials").select("*").order("name"),sb.from("service_materials").select("*"),sb.from("services").select("id,name").order("name")]);
if(m.error)return put(`<h1>خامات الخدمات</h1><button class="btn s g" onclick="go('stock')">← المخزون</button><p class="m" style="margin-top:10px">${matMissing(m.error)?"الخامات لسه مش متفعّلة: شغّل ملف patch_materials.sql في Supabase الأول.":esc(m.error.message)}</p>`);
C.mat=m.data||[];C.smat=sm.data||[];C.msvc=sv.data||[];
const cr=can("restock"),low=C.mat.filter(x=>x.active&&Number(x.stock)<=Number(x.min_stock)).length;
const use={};C.smat.forEach(r=>{(use[r.material_id]=use[r.material_id]||[]).push(r)});
put(`<h1>خامات الخدمات</h1>
<div style="display:flex;gap:6px;flex-wrap:wrap;margin:6px 0"><button class="btn s g" onclick="go('stock')">← المخزون</button>${cr?`<button class="btn s" onclick="matNew()">+ خامة جديدة</button>`:""}${mgr?`<button class="btn s g" onclick="matRecipes()">استهلاك كل خدمة</button>`:""}</div>
<p class="m">الخامة بتتخصم تلقائي بكمية ثابتة لما الفاتورة تتقفل، وبترجع لوحدها لو الفاتورة اتلغت.</p>
${low?`<div class="m" style="margin:6px 0;color:var(--red)">${low} خامة وصلت للحد الأدنى أو أقل</div>`:""}`
+(C.mat.length?C.mat.map(x=>{const lo=Number(x.stock)<=Number(x.min_stock),n=(use[x.id]||[]).length;
return `<div class="row"><div><b>${esc(x.name)}</b>${x.active?"":` <span class="m">(موقوفة)</span>`}<div class="m">الوحدة: ${esc(x.unit)} · تكلفة الوحدة ${matFm(x.cost)} · داخلة في ${n} خدمة</div></div>
<div style="text-align:left"><span class="tag" style="${lo&&x.active?"background:var(--red);color:#fff":""}">${matFm(x.stock)} ${esc(x.unit)}</span><br>
${cr?`<button class="btn s g" onclick="matRestock(${x.id})">+ توريد</button> <button class="btn s g" onclick="matCount(${x.id})">جرد</button> <button class="btn s g" onclick="matEdit(${x.id})">تعديل</button>`:""}<button class="btn s g" onclick="matLog(${x.id})">الحركة</button></div></div>`}).join(""):`<p class="m" style="margin-top:10px">مفيش خامات لسه. دوس «+ خامة جديدة» وضيف مثلاً: شفرة (قطعة)، كريم حمام (جرام)، ماسك (جرام).</p>`))};

async function matNew(){if(C.matBusy)return;
const n=(await askInput("اسم الخامة (مثلاً: كريم حمام)")||"").trim();if(!n)return;
const u=(await askInput("الوحدة (قطعة / جرام / مللي)","جرام")||"").trim();if(!u)return;
const co=matQ(await askInput("تكلفة الوحدة الواحدة بالجنيه (مثلاً الجرام)","0"));if(co===null)return;if(!(co>=0))return toast("التكلفة غلط");
const mn=matQ(await askInput("الحد الأدنى للتنبيه","0"));if(mn===null)return;if(!(mn>=0))return toast("الحد الأدنى غلط");
const q=matQ(await askInput("الكمية الحالية الموجودة","0"));if(q===null)return;if(!(q>=0))return toast("الكمية غلط");
C.matBusy=1;const{data,error}=await sb.rpc("material_save",{p_id:null,p_name:n,p_unit:u,p_min:mn,p_cost:co,p_active:true});
if(error){C.matBusy=0;return toast(error.message)}
if(q>0){const{error:e2}=await sb.rpc("material_restock",{p_id:data,p_qty:q,p_note:"رصيد ابتدائي"});if(e2)toast("اتضافت الخامة بس الكمية فشلت: "+e2.message)}
C.matBusy=0;toast("اتضافت «"+n+"»");V.mat()}

async function matEdit(id){if(C.matBusy)return;const x=(C.mat||[]).find(a=>a.id==id);if(!x)return;
const n=(await askInput("اسم الخامة",x.name)||"").trim();if(!n)return;
const u=(await askInput("الوحدة",x.unit)||"").trim();if(!u)return;
const co=matQ(await askInput("تكلفة الوحدة",String(x.cost)));if(co===null)return;if(!(co>=0))return toast("التكلفة غلط");
const mn=matQ(await askInput("الحد الأدنى للتنبيه",String(x.min_stock)));if(mn===null)return;if(!(mn>=0))return toast("الحد الأدنى غلط");
const act=await askConfirm(x.active?"الخامة شغّالة. تفضل شغّالة؟ (إلغاء = إيقافها عن الخصم)":"الخامة موقوفة. تشغّلها؟",{ok:x.active?"تفضل شغّالة":"شغّلها"});
C.matBusy=1;const{error}=await sb.rpc("material_save",{p_id:id,p_name:n,p_unit:u,p_min:mn,p_cost:co,p_active:act});C.matBusy=0;
error?toast(error.message):(toast("اتحفظ ✓"),V.mat())}

async function matRestock(id){if(C.matBusy)return;const x=(C.mat||[]).find(a=>a.id==id);if(!x)return;
const q=matQ(await askInput("كام "+x.unit+" دخلت من «"+x.name+"»؟\nالرصيد الحالي: "+matFm(x.stock),""));if(q===null)return;if(!(q>0))return toast("اكتب كمية أكبر من صفر");
if(!await askConfirm("إضافة "+matFm(q)+" "+x.unit+" لـ «"+x.name+"»؟\nالرصيد هيبقى "+matFm(Number(x.stock)+q)))return;
C.matBusy=1;const{error}=await sb.rpc("material_restock",{p_id:id,p_qty:q,p_note:"توريد"});C.matBusy=0;
error?toast(error.message):(toast("اتسجّل التوريد ✓"),V.mat())}

async function matCount(id){if(C.matBusy)return;const x=(C.mat||[]).find(a=>a.id==id);if(!x)return;
const q=matQ(await askInput("الكمية الفعلية الموجودة من «"+x.name+"» دلوقتي ("+x.unit+")\nالنظام شايف: "+matFm(x.stock),""));if(q===null)return;if(!(q>=0))return toast("الكمية غلط");
const d=q-Number(x.stock);if(d==0)return toast("الجرد مطابق ✓");
if(!await askConfirm("الفرق: "+(d>0?"+":"")+matFm(d)+" "+x.unit+(x.cost>0?" (≈ "+matFm(Math.abs(d)*x.cost)+" ج)":"")+"\nتسجّل الجرد وتعدّل الرصيد؟"))return;
C.matBusy=1;const{error}=await sb.rpc("material_count",{p_id:id,p_counted:q,p_note:"جرد"});C.matBusy=0;
error?toast(error.message):(toast("اتسجّل الجرد ✓"),V.mat())}

async function matLog(id){const x=(C.mat||[]).find(a=>a.id==id);if(!x)return;
const{data,error}=await sb.from("material_movements").select("qty,reason,invoice_id,note,created_at").eq("material_id",id).order("created_at",{ascending:false}).limit(60);
if(error)return toast(error.message);
const R={restock:"توريد",service:"خدمة",service_void:"رجوع (إلغاء)",count:"جرد",initial:"ابتدائي"};
const o=$("sheet");if(o)o.remove();const w=document.createElement("div");w.id="sheet";w.className="sheet-bg";w.onclick=e=>{if(e.target==w)svcClose()};
w.innerHTML=`<div class="sheet" role="dialog" aria-modal="true"><div class="sheet-h"><b>حركة «${esc(x.name)}»</b><button class="btn g s" onclick="svcClose()" aria-label="إغلاق">✕</button></div>`+
((data||[]).length?data.map(r=>`<div class="row"><div><b>${R[r.reason]||esc(r.reason)}</b><div class="m">${new Date(r.created_at).toLocaleString("ar-EG")}${r.invoice_id?" · فاتورة #"+r.invoice_id:""}${r.note?" · "+esc(r.note):""}</div></div><span class="tag" style="${Number(r.qty)<0?"background:var(--red);color:#fff":""}">${Number(r.qty)>0?"+":""}${matFm(r.qty)} ${esc(x.unit)}</span></div>`).join(""):`<p class="m">مفيش حركة لسه.</p>`)+`</div>`;
document.body.appendChild(w)}

// استهلاك كل خدمة: لكل خدمة بتحدد الخامات وكمياتها الثابتة
function matRecipes(){const S=C.msvc||[],M=(C.mat||[]).filter(x=>x.active);
if(!M.length)return toast("ضيف خامة الأول");
const o=$("sheet");if(o)o.remove();const w=document.createElement("div");w.id="sheet";w.className="sheet-bg";w.onclick=e=>{if(e.target==w)svcClose()};
w.innerHTML=`<div class="sheet" role="dialog" aria-modal="true"><div class="sheet-h"><b>استهلاك كل خدمة</b><button class="btn g s" onclick="svcClose()" aria-label="إغلاق">✕</button></div>
<p class="m">اكتب الكمية اللي بتتخصم مع كل مرة الخدمة تتنفّذ. سيب الخانة فاضية لو الخدمة مبتستهلكش الخامة دي.</p>`+
S.map(s=>`<div class="row" style="display:block"><b>${esc(s.name)}</b>${M.map(x=>{const r=(C.smat||[]).find(a=>a.service_id==s.id&&a.material_id==x.id);
return `<div style="display:flex;align-items:center;gap:8px;margin-top:6px"><span style="flex:1">${esc(x.name)} <span class="m">(${esc(x.unit)})</span></span><input type="text" inputmode="decimal" style="width:90px" data-s="${s.id}" data-m="${x.id}" data-o="${r?matFm(r.qty):""}" value="${r?matFm(r.qty):""}"></div>`}).join("")}</div>`).join("")+
`<button class="btn" style="margin-top:12px;width:100%" onclick="matRecipesSave(this)">حفظ</button></div>`;
document.body.appendChild(w)}

async function matRecipesSave(b){if(b.disabled)return;const ins=[...document.querySelectorAll("#sheet input[data-s]")].filter(i=>i.value.trim()!=i.dataset.o);
if(!ins.length){svcClose();return}
const jobs=[];for(const i of ins){const q=i.value.trim()===""?0:matQ(i.value);if(Number.isNaN(q)||q<0)return toast("كمية غلط");jobs.push({p_service:+i.dataset.s,p_material:+i.dataset.m,p_qty:q})}
b.disabled=true;let err=null;for(const j of jobs){const{error}=await sb.rpc("service_material_set",j);if(error){err=error;break}}
b.disabled=false;if(err)return toast(err.message);svcClose();toast("اتحفظ ✓");V.mat()}
