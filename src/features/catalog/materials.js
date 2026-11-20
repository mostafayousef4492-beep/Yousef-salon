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
return `<div class="row"><div><b>${esc(x.name)}</b>${x.active?"":` <span class="m">(موقوفة)</span>`}${x.optional?` <span class="tag">اختيارية</span>`:""}<div class="m">الوحدة: ${esc(x.unit)} · تكلفة الوحدة ${matFm(x.cost)} · داخلة في ${n} خدمة</div></div>
<div style="text-align:left"><span class="tag" style="${lo&&x.active?"background:var(--red);color:#fff":""}">${matFm(x.stock)} ${esc(x.unit)}</span><br>
${cr?`<button class="btn s g" onclick="matRestock(${x.id})">+ توريد</button> <button class="btn s g" onclick="matCount(${x.id})">جرد</button> <button class="btn s g" onclick="matEdit(${x.id})">تعديل</button>`:""}<button class="btn s g" onclick="matLog(${x.id})">الحركة</button></div></div>`}).join(""):`<p class="m" style="margin-top:10px">مفيش خامات لسه. دوس «+ خامة جديدة» وضيف مثلاً: شفرة (قطعة)، كريم حمام (جرام)، ماسك (جرام).</p>`))};

// شاشة واحدة للخامة: الاسم + الوحدة + التكلفة + الحد الأدنى + الكمية + الاستهلاك مع كل خدمة
function matNew(){matForm(null)}
function matEdit(id){matForm(id)}
function matForm(id){if(C.matBusy)return;const x=id==null?null:(C.mat||[]).find(a=>a.id==id);if(id!=null&&!x)return;
const mgr=me.role=="owner"||me.role=="manager",S=C.msvc||[];
const o=$("sheet");if(o)o.remove();const w=document.createElement("div");w.id="sheet";w.className="sheet-bg";w.onclick=e=>{if(e.target==w)svcClose()};
const f=(l,i,v,ex)=>`<label class="m" style="display:block;margin-top:8px">${l}</label><input id="${i}" type="text" ${ex||""} style="width:100%" value="${esc(v)}">`;
w.innerHTML=`<div class="sheet" role="dialog" aria-modal="true"><div class="sheet-h"><b>${x?"تعديل «"+esc(x.name)+"»":"خامة جديدة"}</b><button class="btn g s" onclick="svcClose()" aria-label="إغلاق">✕</button></div>
${f("اسم الخامة","mf-n",x?x.name:"")}
<div style="display:flex;gap:8px"><div style="flex:1">${f("الوحدة (قطعة / جرام / مللي)","mf-u",x?x.unit:"جرام")}</div><div style="flex:1">${f("تكلفة الوحدة (ج)","mf-c",x?matFm(x.cost):"0",'inputmode="decimal"')}</div></div>
<div style="display:flex;gap:8px"><div style="flex:1">${f("الحد الأدنى للتنبيه","mf-m",x?matFm(x.min_stock):"0",'inputmode="decimal"')}</div>${x?"":`<div style="flex:1">${f("الكمية الموجودة دلوقتي","mf-q","0",'inputmode="decimal"')}</div>`}</div>
${x?`<label style="display:flex;gap:8px;align-items:center;margin-top:10px"><input type="checkbox" id="mf-a" ${x.active?"checked":""}> شغّالة (الخصم التلقائي)</label>`:""}
<label style="display:flex;gap:8px;align-items:center;margin-top:8px"><input type="checkbox" id="mf-o" ${x&&x.optional?"checked":""}> اختيارية (بتظهر في الكاشير مع الخدمة، وتمنها بيتخصم قبل نسبة الصنايعي)</label>
<div id="mf-oq" style="${x&&x.optional?"":"display:none"}">${f("الكمية اللي بتتخصم كل مرة (اختيارية)","mf-oqv",x?matFm(x.opt_qty||1):"1",'inputmode="decimal"')}</div>
${mgr&&S.length?`<h3 style="margin:14px 0 4px">الاستهلاك مع كل خدمة</h3><p class="m">اكتب الكمية اللي بتتخصم كل مرة الخدمة تتنفّذ، وسيب الخانة فاضية لو الخدمة مبتستهلكهاش.</p>`+S.map(sv=>{const r=x?(C.smat||[]).find(a=>a.service_id==sv.id&&a.material_id==x.id):null;
return `<div style="display:flex;align-items:center;gap:8px;margin-top:6px"><span style="flex:1">${esc(sv.name)}</span><input type="text" inputmode="decimal" style="width:90px" data-s="${sv.id}" data-o="${r?matFm(r.qty):""}" value="${r?matFm(r.qty):""}"></div>`}).join(""):""}
<button class="btn" style="margin-top:14px;width:100%" onclick="matFormSave(this,${x?x.id:"null"})">حفظ</button></div>`;
document.body.appendChild(w);$("mf-o").onchange=e=>{$("mf-oq").style.display=e.target.checked?"":"none"}}

async function matFormSave(b,id){if(C.matBusy||b.disabled)return;const x=id==null?null:(C.mat||[]).find(a=>a.id==id);
const n=$("mf-n").value.trim(),u=$("mf-u").value.trim();if(!n)return toast("اكتب اسم الخامة");if(!u)return toast("اكتب الوحدة");
const co=matQ($("mf-c").value),mn=matQ($("mf-m").value),q=x?0:matQ($("mf-q").value);
if(!(co>=0))return toast("التكلفة غلط");if(!(mn>=0))return toast("الحد الأدنى غلط");if(!(q>=0))return toast("الكمية غلط");
const opt=$("mf-o").checked;let oq=1;if(opt){oq=matQ($("mf-oqv").value);if(!(oq>0))return toast("كمية الخامة الاختيارية غلط")}
const act=x?$("mf-a").checked:true;
const rec=[...document.querySelectorAll("#sheet input[data-s]")].filter(i=>i.value.trim()!=i.dataset.o).map(i=>({p_service:+i.dataset.s,q:i.value.trim()===""?0:matQ(i.value)}));
if(rec.some(r=>Number.isNaN(r.q)||r.q<0))return toast("كمية استهلاك غلط");
C.matBusy=1;b.disabled=true;let mid=id,err=null,warn=[];
{const r=await sb.rpc("material_save",{p_id:id,p_name:n,p_unit:u,p_min:mn,p_cost:co,p_active:act});if(r.error)err=r.error;else mid=id==null?r.data:id}
if(!err&&(opt||(x&&x.optional))){const r=await sb.rpc("material_set_optional",{p_id:mid,p_optional:opt,p_qty:oq});if(r.error)warn.push(r.error.message)}
if(!err&&!x&&q>0){const r=await sb.rpc("material_restock",{p_id:mid,p_qty:q,p_note:"رصيد ابتدائي"});if(r.error)warn.push("الكمية فشلت: "+r.error.message)}
if(!err)for(const r of rec){const e=await sb.rpc("service_material_set",{p_service:r.p_service,p_material:mid,p_qty:r.q});if(e.error){warn.push("الاستهلاك: "+e.error.message);break}}
C.matBusy=0;b.disabled=false;if(err)return toast(err.message);
svcClose();toast(warn.length?"اتحفظت بس: "+warn[0]:"اتحفظ ✓");V.mat()}

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
const R={restock:"توريد",service:"خدمة",service_void:"رجوع (إلغاء)",count:"جرد",initial:"ابتدائي",service_option:"خامة اختيارية مع الخدمة"};
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
