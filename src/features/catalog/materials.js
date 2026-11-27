/* features/catalog/materials.js — خامات الخدمات (كريم/ماسك/شفرات...) وخصمها التلقائي عند قفل الفاتورة */

const matQ=v=>{if(v===null)return null;const n=Number(String(v).trim().replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace("٫","."));return Number.isFinite(n)?n:NaN};
const matFm=n=>{n=Number(n)||0;return String(Math.round(n*1000)/1000)};
const matMissing=e=>e&&/materials|service_materials|material_/i.test(e.message||"")&&/(does not exist|schema cache|Could not find)/i.test(e.message||"");

V.mat=async function(){
const mgr=me.role=="owner"||me.role=="manager";
const[m,sm,sv]=await Promise.all([sb.from("materials").select("*").order("name"),sb.from("service_materials").select("*"),sb.from("services").select("id,name").order("name")]);
if(m.error)return put(`<h1>خامات الخدمات</h1><button class="btn s g" onclick="go('stock')">← المخزون</button><p class="m" style="margin-top:10px">${matMissing(m.error)?"الخامات لسه مش متفعّلة: شغّل ملف patch_materials.sql في Supabase الأول.":esc(m.error.message)}</p>`);
C.mat=(m.data||[]).filter(x=>!x.archived);C.smat=sm.data||[];C.msvc=sv.data||[];
const cr=can("restock"),low=C.mat.filter(x=>x.active&&Number(x.stock)<=Number(x.min_stock)).length;
const use={};C.smat.forEach(r=>{(use[r.material_id]=use[r.material_id]||[]).push(r)});
put(`<h1>خامات الخدمات</h1>
<div style="display:flex;gap:6px;flex-wrap:wrap;margin:6px 0"><button class="btn s g" onclick="go('stock')">← المخزون</button>${cr?`<button class="btn s" onclick="matNew()">+ خامة جديدة</button>`:""}${mgr?`<button class="btn s g" onclick="matRecipes()">استهلاك كل خدمة</button>`:""}</div>
<p class="m">الخامة بتتخصم تلقائي بكمية ثابتة لما الفاتورة تتقفل، وبترجع لوحدها لو الفاتورة اتلغت.</p>
${low?`<div class="m" style="margin:6px 0;color:var(--red)">${low} خامة وصلت للحد الأدنى أو أقل</div>`:""}`
+(C.mat.length?C.mat.map(x=>{const lo=Number(x.stock)<=Number(x.min_stock),n=(use[x.id]||[]).length;
return `<div class="row"><div><b>${esc(x.name)}</b>${x.active?"":` <span class="m">(موقوفة)</span>`}${x.optional?` <span class="tag">اختيارية</span>`:""}${x.group_name?` <span class="tag">${esc(x.group_name)}</span>`:""}${x.product_id?` <span class="tag">رصيدها من المخزون</span>`:""}<div class="m">الوحدة: ${esc(x.unit)} · تكلفة الوحدة ${matFm(x.cost)} · داخلة في ${n} خدمة</div></div>
<div style="text-align:left"><span class="tag" style="${lo&&x.active?"background:var(--red);color:#fff":""}">${matFm(x.stock)} ${esc(x.unit)}</span><br>
${cr&&!x.product_id?`<button class="btn s g" onclick="matRestock(${x.id})">+ توريد</button> <button class="btn s g" onclick="matCount(${x.id})">جرد</button> <button class="btn s g" onclick="matEdit(${x.id})">تعديل</button>`:""}${me.role=="owner"||me.role=="manager"?`<button class="btn s g" style="color:var(--red)" onclick="matDel(${x.id})">مسح</button>`:""}<button class="btn s g" onclick="matLog(${x.id})">الحركة</button></div></div>`}).join(""):`<p class="m" style="margin-top:10px">مفيش خامات لسه. دوس «+ خامة جديدة» وضيف مثلاً: شفرة (قطعة)، كريم حمام (جرام)، ماسك (جرام).</p>`))};

// شاشة واحدة للخامة: الاسم + الوحدة + التكلفة + الحد الأدنى + الكمية + الاستهلاك مع كل خدمة
function matNew(){matForm(null)}
function matEdit(id){matForm(id)}
function matForm(id){if(C.matBusy)return;const x=id==null?null:(C.mat||[]).find(a=>a.id==id);if(id!=null&&!x)return;
const mgr=me.role=="owner"||me.role=="manager",S=C.msvc||[];
const o=$("sheet");if(o)o.remove();const w=document.createElement("div");w.id="sheet";w.className="sheet-bg";w.onclick=e=>{if(e.target==w)svcClose()};
const f=(l,i,v,ex)=>`<label class="m" style="display:block;margin-top:8px">${l}</label><input id="${i}" type="text" ${ex||""} style="width:100%" value="${esc(v)}">`;
w.innerHTML=`<div class="sheet" role="dialog" aria-modal="true"><div class="sheet-h"><b>${x?"تعديل «"+esc(x.name)+"»":"خامة جديدة"}</b><button class="btn g s" onclick="svcClose()" aria-label="إغلاق">✕</button></div>
${x?"":`<div style="display:flex;gap:14px;margin-top:8px"><label><input type="radio" name="mf-t" value="m" checked> خامة (بتستهلك في الخدمات)</label><label><input type="radio" name="mf-t" value="p"> صنف للبيع</label><label><input type="radio" name="mf-t" value="b"> للبيع وللاستهلاك</label></div>`}
${f("الاسم","mf-n",x?x.name:"")}
<div id="mf-pb" style="display:none"><div style="display:flex;gap:8px"><div style="flex:1">${f("سعر البيع","mf-pp","",'inputmode="decimal"')}</div><div style="flex:1">${f("سعر الشراء","mf-pc","0",'inputmode="decimal"')}</div></div>${f("الكمية الموجودة دلوقتي","mf-pq","0",'inputmode="numeric"')}</div>
<div id="mf-bb" style="display:none">${mgr&&S.length?`<h3 style="margin:14px 0 4px">الاستهلاك مع كل خدمة</h3><p class="m">رصيد واحد: بتبيع الصنف بالقطعة وبتستهلكه في الخدمات بوحدة أصغر. الاستهلاك بيتخصم من العبوة المفتوحة، ولما تخلص بيتفتح قطعة جديدة من المخزون.</p><div style="display:flex;gap:8px"><div style="flex:1">${f("وحدة الاستهلاك (جرام / مللي / قطعة)","mf-bu","جرام")}</div><div style="flex:1">${f("القطعة الواحدة فيها كام؟","mf-bp","1",'inputmode="decimal"')}</div></div>`+S.map(sv=>`<div style="display:flex;align-items:center;gap:8px;margin-top:6px"><span style="flex:1">${esc(sv.name)}</span><input type="text" inputmode="decimal" style="width:90px" data-b="${sv.id}" value=""></div>`).join(""):""}</div>
<div id="mf-mb">
<div style="display:flex;gap:8px"><div style="flex:1">${f("الوحدة (قطعة / جرام / مللي)","mf-u",x?x.unit:"جرام")}</div><div style="flex:1">${f("تكلفة الوحدة (ج)","mf-c",x?matFm(x.cost):"0",'inputmode="decimal"')}</div></div>
<div style="display:flex;gap:8px"><div style="flex:1">${f("الحد الأدنى للتنبيه","mf-m",x?matFm(x.min_stock):"0",'inputmode="decimal"')}</div>${x?"":`<div style="flex:1">${f("الكمية الموجودة دلوقتي","mf-q","0",'inputmode="decimal"')}</div>`}</div>
${x&&!("group_name" in x)?"":`<label class="m" style="display:block;margin-top:8px">المجموعة (اختياري): أنواع بديلة لنفس الخامة، مثلًا «ماسك صنفرة»</label><input id="mf-g" list="mf-gl" type="text" style="width:100%" value="${esc(x&&x.group_name||"")}" placeholder="سيبها فاضية لو الخامة لوحدها"><datalist id="mf-gl">${[...new Set((C.mat||[]).map(m=>m.group_name).filter(Boolean))].map(g=>`<option value="${esc(g)}">`).join("")}</datalist><div class="m">الخدمة المربوطة بأي نوع في المجموعة بتسحب من أي نوع فيها (الأقدم الأول)، فاربطها بنوع واحد بس.</div>`}
${x?`<label style="display:flex;gap:8px;align-items:center;margin-top:10px"><input type="checkbox" id="mf-a" ${x.active?"checked":""}> شغّالة (الخصم التلقائي)</label>`:""}
<label style="display:flex;gap:8px;align-items:center;margin-top:8px"><input type="checkbox" id="mf-o" ${x&&x.optional?"checked":""}> اختيارية (بتظهر في الكاشير مع الخدمة، وتمنها بيتخصم قبل نسبة الصنايعي)</label>
${x&&!("cost_in_commission" in x)?"":`<label style="display:flex;gap:8px;align-items:center;margin-top:8px"><input type="checkbox" id="mf-cc" ${x&&x.cost_in_commission?"checked":""}> تكلفتها تتخصم تلقائي قبل نسبة الصنايعي لما تتباع خدمة مربوطة بيها (زي كيس الحنة مع الصبغة)</label>`}
<div id="mf-oq" style="${x&&x.optional?"":"display:none"}">${f("الكمية اللي بتتخصم كل مرة (اختيارية)","mf-oqv",x?matFm(x.opt_qty||1):"1",'inputmode="decimal"')}</div>
${mgr&&S.length?`<h3 style="margin:14px 0 4px">الاستهلاك مع كل خدمة</h3><p class="m">اكتب الكمية اللي بتتخصم كل مرة الخدمة تتنفّذ، وسيب الخانة فاضية لو الخدمة مبتستهلكهاش.</p>`+S.map(sv=>{const r=x?(C.smat||[]).find(a=>a.service_id==sv.id&&a.material_id==x.id):null;
return `<div style="display:flex;align-items:center;gap:8px;margin-top:6px"><span style="flex:1">${esc(sv.name)}</span><input type="text" inputmode="decimal" style="width:90px" data-s="${sv.id}" data-o="${r?matFm(r.qty):""}" value="${r?matFm(r.qty):""}"></div>`}).join(""):""}
</div>
<button class="btn" style="margin-top:14px;width:100%" onclick="matFormSave(this,${x?x.id:"null"})">حفظ</button></div>`;
document.body.appendChild(w);$("mf-o").onchange=e=>{$("mf-oq").style.display=e.target.checked?"":"none"};
w.querySelectorAll('input[name="mf-t"]').forEach(r=>r.onchange=()=>{const t=w.querySelector('input[name="mf-t"]:checked').value;$("mf-pb").style.display=t=="m"?"none":"";$("mf-mb").style.display=t=="m"?"":"none";$("mf-bb").style.display=t=="b"?"":"none"})}

async function matFormSave(b,id){if(C.matBusy||b.disabled)return;const x=id==null?null:(C.mat||[]).find(a=>a.id==id);
const tp=document.querySelector('input[name="mf-t"]:checked');
if(tp&&(tp.value=="p"||tp.value=="b")){const both=tp.value=="b";const n=$("mf-n").value.trim();if(!n)return toast("اكتب اسم الصنف");
if((C.stk||[]).some(p=>String(p.name).trim()==n))return toast("الصنف ده موجود، استخدم «+ توريد»");
const pr=Number(String($("mf-pp").value).trim()),co=Number(String($("mf-pc").value).trim()||"0"),q=Number(String($("mf-pq").value).trim()||"0");
if(!(pr>=0)||$("mf-pp").value.trim()==="")return toast("سعر البيع غلط");if(!(co>=0))return toast("سعر الشراء غلط");if(!Number.isInteger(q)||q<0)return toast("الكمية لازم تكون عدد صحيح");
C.matBusy=1;b.disabled=true;const{data,error}=await sb.from("products").insert({name:n,price:pr,cost:co,stock:0,min_stock:+(C.cfg&&C.cfg.low_stock_default)||5}).select("id").single();
let w2="";if(!error&&q>0){const r=await sb.rpc("restock_product",{p_id:data.id,p_qty:q});if(r.error)w2=r.error.message}
if(!error&&both){const cons=[...document.querySelectorAll("#sheet input[data-b]")].filter(i=>i.value.trim()!=="").map(i=>({service_id:+i.dataset.b,qty:matQ(i.value)})),bu=($("mf-bu")?$("mf-bu").value.trim():"")||"قطعة",bp=$("mf-bp")?matQ($("mf-bp").value):1;
if(cons.some(c=>!(c.qty>=0))||!(bp>0)){w2="كمية الاستهلاك أو حجم القطعة غلط (الصنف اتضاف من غير استهلاك)"}else{const r=await sb.rpc("item_make_shared",{p_product:data.id,p_consumption:cons,p_unit:bu,p_pack:bp});if(r.error)w2=/item_make_shared|schema cache|does not exist/i.test(r.error.message)?"شغّل ملف patch_shared_stock.sql في Supabase الأول":r.error.message}}
C.matBusy=0;b.disabled=false;if(error)return toast(error.message);svcClose();toast(w2?"اتضاف الصنف بس التوريد فشل: "+w2:"اتضاف «"+n+"» ✓");return matRefresh()}
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
if(!err&&$("mf-g")&&(($("mf-g").value.trim())||(x&&x.group_name))){const r=await sb.rpc("material_set_group",{p_id:mid,p_group:$("mf-g").value.trim()});if(r.error)warn.push(r.error.message)}
if(!err&&$("mf-cc")&&($("mf-cc").checked||(x&&x.cost_in_commission))){const r=await sb.rpc("material_set_cost_commission",{p_id:mid,p_on:$("mf-cc").checked});if(r.error)warn.push(r.error.message)}
if(!err&&!x&&q>0){const r=await sb.rpc("material_restock",{p_id:mid,p_qty:q,p_note:"رصيد ابتدائي"});if(r.error)warn.push("الكمية فشلت: "+r.error.message)}
if(!err)for(const r of rec){const e=await sb.rpc("service_material_set",{p_service:r.p_service,p_material:mid,p_qty:r.q});if(e.error){warn.push("الاستهلاك: "+e.error.message);break}}
C.matBusy=0;b.disabled=false;if(err)return toast(err.message);
svcClose();toast(warn.length?"اتحفظت بس: "+warn[0]:"اتحفظ ✓");matRefresh()}

async function matRestock(id){if(C.matBusy)return;const x=(C.mat||[]).find(a=>a.id==id);if(!x)return;
const q=matQ(await askInput("كام "+x.unit+" دخلت من «"+x.name+"»؟\nالرصيد الحالي: "+matFm(x.stock),""));if(q===null)return;if(!(q>0))return toast("اكتب كمية أكبر من صفر");
if(!await askConfirm("إضافة "+matFm(q)+" "+x.unit+" لـ «"+x.name+"»؟\nالرصيد هيبقى "+matFm(Number(x.stock)+q)))return;
C.matBusy=1;const{error}=await sb.rpc("material_restock",{p_id:id,p_qty:q,p_note:"توريد"});C.matBusy=0;
error?toast(error.message):(toast("اتسجّل التوريد ✓"),matRefresh())}

async function matCount(id){if(C.matBusy)return;const x=(C.mat||[]).find(a=>a.id==id);if(!x)return;
const q=matQ(await askInput("الكمية الفعلية الموجودة من «"+x.name+"» دلوقتي ("+x.unit+")\nالنظام شايف: "+matFm(x.stock),""));if(q===null)return;if(!(q>=0))return toast("الكمية غلط");
const d=q-Number(x.stock);if(d==0)return toast("الجرد مطابق ✓");
if(!await askConfirm("الفرق: "+(d>0?"+":"")+matFm(d)+" "+x.unit+(x.cost>0?" (≈ "+matFm(Math.abs(d)*x.cost)+" ج)":"")+"\nتسجّل الجرد وتعدّل الرصيد؟"))return;
C.matBusy=1;const{error}=await sb.rpc("material_count",{p_id:id,p_counted:q,p_note:"جرد"});C.matBusy=0;
error?toast(error.message):(toast("اتسجّل الجرد ✓"),matRefresh())}

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
b.disabled=false;if(err)return toast(err.message);svcClose();toast("اتحفظ ✓");matRefresh()}

// الخامات جوه شاشة المخزون: كل حاجة في مكان واحد
function matRefresh(){return tab=="stock"?V.stock():V.mat()}
const stkV0=V.stock;
V.stock=async function(){await stkV0();if(tab!="stock")return;
try{const[m,sm,sv]=await Promise.all([sb.from("materials").select("*").order("name"),sb.from("service_materials").select("*"),sb.from("services").select("id,name").order("name")]);
if(m.error||tab!="stock")return;C.mat=(m.data||[]).filter(x=>!x.archived);C.smat=sm.data||[];C.msvc=sv.data||[];
const mgr=me.role=="owner"||me.role=="manager",cr=can("restock"),use={};C.smat.forEach(r=>{(use[r.material_id]=use[r.material_id]||[]).push(r)});
const el=$("app")||document.body;
el.insertAdjacentHTML("beforeend",`<h2 style="margin-top:18px">الخامات (كريم / ماسك / شفرات)</h2><div style="margin:6px 0;display:flex;gap:6px;flex-wrap:wrap">${mgr?`<button class="btn s g" onclick="matRecipes()">استهلاك كل خدمة</button>`:""}</div>`
+(C.mat.length?C.mat.map(x=>{const lo=Number(x.stock)<=Number(x.min_stock),n=(use[x.id]||[]).length;
return `<div class="row"><div><b>${esc(x.name)}</b>${x.active?"":` <span class="m">(موقوفة)</span>`}${x.optional?` <span class="tag">اختيارية</span>`:""}${x.product_id?` <span class="tag">رصيدها من المخزون</span>`:""}<div class="m">${esc(x.unit)} · تكلفة الوحدة ${matFm(x.cost)} · داخلة في ${n} خدمة</div></div>
<div style="text-align:left"><span class="tag" style="${lo&&x.active?"background:var(--red);color:#fff":""}">${matFm(x.stock)} ${esc(x.unit)}</span><br>
${cr&&!x.product_id?`<button class="btn s g" onclick="matRestock(${x.id})">+ توريد</button> <button class="btn s g" onclick="matCount(${x.id})">جرد</button> <button class="btn s g" onclick="matEdit(${x.id})">تعديل</button>`:""}${me.role=="owner"||me.role=="manager"?`<button class="btn s g" style="color:var(--red)" onclick="matDel(${x.id})">مسح</button>`:""}<button class="btn s g" onclick="matLog(${x.id})">الحركة</button></div></div>`}).join(""):`<p class="m">مفيش خامات لسه.</p>`))}catch(e){}};

async function matDel(id){if(C.matBusy)return;const x=(C.mat||[]).find(a=>a.id==id);if(!x)return;
if(!await askConfirm("مسح الخامة «"+x.name+"»؟\nهتتشال من الشاشات ومن استهلاك الخدمات، وسجل حركتها القديم بيفضل محفوظ. الرصيد الحالي: "+matFm(x.stock)+" "+x.unit,{ok:"امسح"}))return;
C.matBusy=1;const{data,error}=await sb.rpc("material_delete",{p_id:id});C.matBusy=0;
if(error)return toast(/material_delete|schema cache|does not exist/i.test(error.message)?"شغّل ملف patch_material_delete.sql في Supabase الأول":error.message);
toast(data=="deleted"?"اتمسحت ✓":"اتمسحت (اتأرشفت وسجلها محفوظ) ✓");matRefresh()}

// ربط صنف موجود بالاستهلاك في الخدمات (رصيد واحد، البيع بالقطعة والاستهلاك بوحدة أصغر)
async function stockUse(id){const p=(C.stk||[]).find(x=>x.id==id);if(!p)return;
const[m,sm,sv]=await Promise.all([sb.from("materials").select("id,product_id,unit,pack_size").eq("product_id",id),sb.from("service_materials").select("*"),sb.from("services").select("id,name").order("name")]);
if(m.error)return toast(/product_id|pack_size|schema cache|does not exist/i.test(m.error.message)?"شغّل ملف patch_shared_stock.sql في Supabase الأول":m.error.message);
const mm=(m.data||[])[0],mid=mm&&mm.id,S=sv.data||[];if(!S.length)return toast("مفيش خدمات");
const o=$("sheet");if(o)o.remove();const w=document.createElement("div");w.id="sheet";w.className="sheet-bg";w.onclick=e=>{if(e.target==w)svcClose()};
w.innerHTML=`<div class="sheet" role="dialog" aria-modal="true"><div class="sheet-h"><b>استهلاك «${esc(p.name)}» في الخدمات</b><button class="btn g s" onclick="svcClose()" aria-label="إغلاق">✕</button></div>
<p class="m">رصيد واحد: البيع بينقّص قطع، والاستهلاك بيتخصم من العبوة المفتوحة ولما تخلص بيتفتح قطعة جديدة. رصيد الصنف الحالي: ${p.stock} قطعة.</p>
<div style="display:flex;gap:8px"><div style="flex:1"><label class="m">وحدة الاستهلاك</label><input id="su-u" type="text" style="width:100%" value="${esc(mm?mm.unit:"جرام")}"></div><div style="flex:1"><label class="m">القطعة الواحدة فيها كام؟</label><input id="su-p" type="text" inputmode="decimal" style="width:100%" value="${mm?matFm(mm.pack_size):""}"></div></div>`+
S.map(s2=>{const r=mid?(sm.data||[]).find(a=>a.service_id==s2.id&&a.material_id==mid):null;return `<div style="display:flex;align-items:center;gap:8px;margin-top:6px"><span style="flex:1">${esc(s2.name)}</span><input type="text" inputmode="decimal" style="width:90px" data-u="${s2.id}" data-o="${r?matFm(r.qty):""}" value="${r?matFm(r.qty):""}"></div>`}).join("")+
`<button class="btn" style="margin-top:14px;width:100%" onclick="stockUseSave(this,${id},${mm?`'${String(mm.unit||"").replace(/'/g,"")}',${+mm.pack_size}`:"null,null"})">حفظ</button></div>`;document.body.appendChild(w)}

async function stockUseSave(b,id,u0,p0){if(b.disabled)return;const u=$("su-u").value.trim()||"قطعة",pk=matQ($("su-p").value);
if(!(pk>0))return toast("اكتب القطعة الواحدة فيها كام");
const ins=[...document.querySelectorAll("#sheet input[data-u]")].filter(i=>i.value.trim()!=i.dataset.o);
if(!ins.length&&u==u0&&pk==p0){svcClose();return}
const cons=ins.map(i=>({service_id:+i.dataset.u,qty:i.value.trim()===""?0:matQ(i.value)}));
if(cons.some(c=>!(c.qty>=0)))return toast("كمية غلط");
b.disabled=true;const{error}=await sb.rpc("item_make_shared",{p_product:id,p_consumption:cons,p_unit:u,p_pack:pk});b.disabled=false;
if(error)return toast(/item_make_shared|schema cache|does not exist/i.test(error.message)?"شغّل ملف patch_shared_stock.sql في Supabase الأول":error.message);
svcClose();toast("اتحفظ ✓");V.stock()}
