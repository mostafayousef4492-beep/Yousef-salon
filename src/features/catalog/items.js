/* features/catalog/items.js — «الأصناف والمخزون»: شاشة واحدة لكل حاجة. الصنف = علبة (فيها كام) + سعر شراء + سعر بيع (اختياري) + استهلاك كل خدمة + مجموعة.
   بيحتاج patch_items_unified.sql. بيعتمد على helpers materials.js (matQ, matFm, matLog, matRecipes). */

const itMiss=e=>e&&/item_|for_sale|items_consumption/i.test(e.message||"")&&/(does not exist|schema cache|Could not find|column)/i.test(e.message||"");
const itErr=e=>itMiss(e)?"شغّل ملف patch_items_unified.sql في Supabase الأول":esc(e.message||"حصل خطأ");
const itSheet=(title,inner)=>{const o=$("sheet");if(o)o.remove();const w=document.createElement("div");w.id="sheet";w.className="sheet-bg";w.onclick=e=>{if(e.target==w)svcClose()};
  w.innerHTML=`<div class="sheet" role="dialog" aria-modal="true"><div class="sheet-h"><b>${title}</b><button class="btn g s" onclick="svcClose()" aria-label="إغلاق">✕</button></div>${inner}</div>`;document.body.appendChild(w)};
const itIn=(l,i,v,ex)=>`<label class="m" style="display:block;margin-top:8px">${l}</label><input id="${i}" type="text" ${ex||""} style="width:100%" value="${esc(v)}">`;

const itRe=()=>tab=="cnt"?V.cnt():tab=="mat"?V.mat():V.stock();
const itLoad=async()=>{const[p,m,sm,sv]=await Promise.all([sb.from("products").select("*").order("name"),sb.from("materials").select("*").order("name"),sb.from("service_materials").select("*"),sb.from("services").select("id,name").order("name")]);
if(p.error)return p.error;C.stk=(p.data||[]).filter(x=>!x.archived);C.mat=(m.data||[]).filter(x=>!x.archived);C.smat=sm.data||[];C.msvc=sv.data||[];
const by={};C.mat.forEach(x=>{if(x.product_id)by[x.product_id]=x});C.itBy=by;return null};

// الأصناف: بيانات الصنف بس (الاسم، الأسعار، محتوى العلبة). الاستهلاك في «استهلاك الخامات» والعدد في «الجرد».
V.stock=async function(){
const mgr=me.role=="owner"||me.role=="manager";const er=await itLoad();
if(er)return put(`<h1>الأصناف</h1><p class="m">${esc(er.message)}</p>`);
const byP=C.itBy,low=C.stk.filter(x=>x.active&&x.stock<=x.min_stock).length;
const row=x=>{const mm=byP[x.id];
  const sub=[`شراء ${matFm(x.cost)}`,x.for_sale===false?"للاستهلاك بس":`بيع ${matFm(x.price)}`,mm?`العلبة ${matFm(mm.pack_size)} ${esc(mm.unit)}`:"قطعة",`حد أدنى ${x.min_stock}`].join(" · ");
  return `<div class="row"><div><b>${esc(x.name)}</b>${x.active?"":` <span class="m">(موقوف)</span>`}${x.stock<=x.min_stock&&x.active?` <span class="tag" style="background:var(--red);color:#fff">قرّب يخلص</span>`:""}<div class="m">${sub}</div></div>
<div style="text-align:left"><button class="btn s g" onclick="itLog(${x.id})">حركة</button>${mgr?` <button class="btn s g" onclick="itForm(${x.id})">تعديل</button> <button class="btn s g" style="color:var(--red)" onclick="itDel(${x.id})">مسح</button>`:""}</div></div>`};
put(`<h1>الأصناف</h1>
<p class="m">كل صنف: الاسم، سعر الشراء والبيع، وعلبته فيها كام. التوريد من فاتورة المشتريات، والعدد الفعلي في «الجرد»، واستهلاك الخدمات في «استهلاك الخامات».</p>
<div style="display:flex;gap:6px;flex-wrap:wrap;margin:6px 0">${mgr?`<button class="btn s" onclick="itForm(null)">+ صنف جديد</button><button class="btn s g" onclick="go('fin')">فاتورة مشتريات</button>`:""}<button class="btn s g" onclick="go('cnt')">الجرد</button></div>
${low?`<div class="m" style="margin:6px 0;color:var(--red)">${low} صنف وصل للحد الأدنى أو أقل (شوفهم في «الجرد»)</div>`:""}`
+(C.stk.length?C.stk.map(row).join(""):`<p class="m">لسه مفيش أصناف. ضيف صنف أو سجّل فاتورة مشتريات.</p>`))};

// استهلاك الخامات: كل الأصناف اللي بتتستهلك في الخدمات، وكمية كل خدمة، والمجموعات، والصرف للمحل، والتقرير.
V.mat=async function(){
const mgr=me.role=="owner"||me.role=="manager",cr=can("restock");const er=await itLoad();
if(er)return put(`<h1>استهلاك الخامات</h1><p class="m">${esc(er.message)}</p>`);
const use={};C.smat.forEach(r=>{(use[r.material_id]=use[r.material_id]||[]).push(r)});
const sn=Object.fromEntries(C.msvc.map(x=>[x.id,x.name]));
const L=C.mat.filter(x=>x.active&&x.product_id),O=C.mat.filter(x=>x.active&&!x.product_id);
const row=x=>{const u=use[x.id]||[];return `<div class="row"><div><b>${esc(x.name)}</b>${x.group_name?` <span class="tag">${esc(x.group_name)}</span>`:""}
<div class="m">المتاح ${matFm(x.stock)} ${esc(x.unit)}${x.product_id?` · العلبة ${matFm(x.pack_size)}`:""}</div>
<div class="m">${u.length?u.map(r=>esc(sn[r.service_id]||"؟")+" "+matFm(r.qty)).join(" · "):"مش داخل في أي خدمة"}</div></div>
<div style="text-align:left">${mgr?`<button class="btn s" onclick="itUse(${x.id})">الاستهلاك والمجموعة</button> `:""}${cr?`<button class="btn s g" onclick="itIssue(${x.id})">صرف للمحل</button> `:""}<button class="btn s g" onclick="matLog(${x.id})">حركة</button></div></div>`};
put(`<h1>استهلاك الخامات</h1>
<p class="m">هنا بتحدد كل خدمة بتستهلك كام من كل صنف. لو عندك أكتر من نوع لنفس الاستخدام (مثلًا سيداج وديموليش) حطهم في مجموعة واحدة، والخدمة بتسحب من أي نوع منهم.</p>
<div style="display:flex;gap:6px;flex-wrap:wrap;margin:6px 0">${mgr?`<button class="btn s g" onclick="matRecipes()">استهلاك كل خدمة</button><button class="btn s g" onclick="itRep()">تقرير الاستهلاك</button>`:""}</div>`
+(L.length?L.map(row).join(""):`<p class="m">مفيش صنف بيتستهلك في الخدمات. ضيف صنف وفعّل «بيتستهلك في الخدمات».</p>`)
+(O.length&&mgr?`<h2 style="margin-top:18px">خامات قديمة مش مربوطة بصنف</h2><p class="m">اتضافت بالطريقة القديمة (الوحدة بالجرام من غير علبة). حوّلها لصنف عشان تتسجّل بالعلبة وسعر الشراء الصح.</p>`+O.map(x=>`<div class="row"><div><b>${esc(x.name)}</b>${x.group_name?` <span class="tag">${esc(x.group_name)}</span>`:""}<div class="m">${matFm(x.stock)} ${esc(x.unit)} · تكلفة الوحدة ${matFm(x.cost)}</div></div><div style="text-align:left"><button class="btn s" onclick="itConv(${x.id})">حوّل لصنف</button> <button class="btn s g" onclick="itIssue(${x.id})">صرف للمحل</button> <button class="btn s g" onclick="matLog(${x.id})">حركة</button></div></div>`).join(""):""))};

// استهلاك صنف: كمية كل خدمة + المجموعة
function itUse(mid){const m=(C.mat||[]).find(a=>a.id==mid);if(!m)return;const S=C.msvc||[],grps=[...new Set((C.mat||[]).map(a=>a.group_name).filter(Boolean))];
itSheet("استهلاك «"+esc(m.name)+"»",`<label class="m" style="display:block">المجموعة (اختياري): نفس الاسم لكل الأنواع البديلة</label><input id="iu-g" list="iu-gl" type="text" style="width:100%" value="${esc(m.group_name||"")}" data-o="${esc(m.group_name||"")}" placeholder="مثلًا: ماسك صنفرة"><datalist id="iu-gl">${grps.map(g=>`<option value="${esc(g)}">`).join("")}</datalist>
<h3 style="margin:14px 0 4px">الكمية لكل مرة الخدمة تتنفّذ (${esc(m.unit)})</h3><p class="m">سيب الخانة فاضية لو الخدمة مبتستهلكش الصنف.</p>`+
S.map(sv=>{const r=(C.smat||[]).find(a=>a.service_id==sv.id&&a.material_id==m.id);return `<div style="display:flex;align-items:center;gap:8px;margin-top:6px"><span style="flex:1">${esc(sv.name)}</span><input type="text" inputmode="decimal" style="width:90px" data-s="${sv.id}" data-o="${r?matFm(r.qty):""}" value="${r?matFm(r.qty):""}"></div>`}).join("")+
`<button class="btn" style="margin-top:14px;width:100%" onclick="itUseSave(this,${m.id})">حفظ</button>`)}
async function itUseSave(b,mid){if(b.disabled||C.itBusy)return;const ins=[...document.querySelectorAll("#sheet input[data-s]")].filter(i=>i.value.trim()!=i.dataset.o);const g=$("iu-g");const gch=g.value.trim()!=g.dataset.o;
const jobs=[];for(const i of ins){const q=i.value.trim()===""?0:matQ(i.value);if(Number.isNaN(q)||q<0)return toast("كمية غلط");jobs.push({p_service:+i.dataset.s,p_material:mid,p_qty:q})}
if(!jobs.length&&!gch){svcClose();return}
C.itBusy=1;b.disabled=true;let err=null;if(gch){const r=await sb.rpc("material_set_group",{p_id:mid,p_group:g.value.trim()||null});if(r.error)err=r.error}
if(!err)for(const j of jobs){const r=await sb.rpc("service_material_set",j);if(r.error){err=r.error;break}}
C.itBusy=0;b.disabled=false;if(err)return toast(itErr(err));svcClose();toast("اتحفظ ✓");V.mat()}

// الجرد: عدد العلب والقطع الفعلي لكل صنف
V.cnt=async function(){
const er=await itLoad();if(er)return put(`<h1>الجرد</h1><p class="m">${esc(er.message)}</p>`);
if(!can("restock"))return put(`<h1>الجرد</h1><p class="m">مش معاك صلاحية الجرد.</p>`);
const P=C.stk.filter(x=>x.active),O=C.mat.filter(x=>!x.product_id&&x.active);
put(`<h1>الجرد</h1><p class="m">اكتب العدد الفعلي الموجود عندك لكل صنف: علب أو قطع كاملة، وللأصناف اللي بتتستهلك كمان اللي في العلبة المفتوحة. اللي مش متغيّر مش هيتسجّل.</p>
<button class="btn s g" onclick="document.querySelectorAll('#cnt-b input[data-k]').forEach(i=>i.value=0)">صفّر الكل وابدأ من جديد</button><div id="cnt-b">`+
P.map(x=>{const mm=C.itBy[x.id];return `<div class="row" style="display:block"><b>${esc(x.name)}</b> <span class="m">${mm?"(بالعلبة)":"(بالقطعة)"}</span><div style="display:flex;gap:8px;align-items:center;margin-top:6px"><span class="m" style="flex:1">${mm?"علب كاملة":"قطع"}</span><input type="text" inputmode="numeric" style="width:80px" data-k="p" data-id="${x.id}" data-o="${x.stock}" value="${x.stock}">${mm?`<span class="m">+ مفتوح (${esc(mm.unit)})</span><input type="text" inputmode="decimal" style="width:80px" data-k="o" data-id="${x.id}" data-o="${matFm(mm.open_qty)}" value="${matFm(mm.open_qty)}">`:""}</div></div>`}).join("")+
O.map(x=>`<div class="row" style="display:block"><b>${esc(x.name)}</b> <span class="m">(خامة قديمة)</span><div style="display:flex;gap:8px;align-items:center;margin-top:6px"><span class="m" style="flex:1">الكمية (${esc(x.unit)})</span><input type="text" inputmode="decimal" style="width:90px" data-k="m" data-id="${x.id}" data-o="${matFm(x.stock)}" value="${matFm(x.stock)}"></div></div>`).join("")+
`</div><button class="btn" style="margin-top:12px;width:100%" onclick="itBulkSave(this)">حفظ الجرد</button>`)};

// ===== صنف جديد / تعديل =====
function itForm(id){if(C.itBusy)return;const x=id==null?null:(C.stk||[]).find(a=>a.id==id);if(id!=null&&!x)return;
const mm=x?C.itBy[x.id]:null,cons=!!(mm&&mm.active)||(!x);
itSheet(x?"تعديل «"+esc(x.name)+"»":"صنف جديد",`
${itIn("اسم الصنف","it-n",x?x.name:"")}
<label style="display:flex;gap:8px;align-items:center;margin-top:10px"><input type="checkbox" id="it-c" ${cons?"checked":""}> بيتستهلك في الخدمات (بالجرام أو المللي)</label>
<div id="it-cb" style="${cons?"":"display:none"}"><div style="display:flex;gap:8px"><div style="flex:1">${itIn("الوحدة","it-u",mm?mm.unit:"جرام")}</div><div style="flex:1">${itIn("العلبة فيها كام؟","it-p",mm?matFm(mm.pack_size):"","inputmode=\"decimal\"")}</div></div>
</div>
<div style="display:flex;gap:8px"><div style="flex:1">${itIn("سعر شراء العلبة/القطعة","it-co",x?matFm(x.cost):"0","inputmode=\"decimal\"")}</div><div style="flex:1">${itIn("الحد الأدنى للتنبيه (علب)","it-mn",x?x.min_stock:String(+(C.cfg&&C.cfg.low_stock_default)||2),"inputmode=\"decimal\"")}</div></div>
<label style="display:flex;gap:8px;align-items:center;margin-top:10px"><input type="checkbox" id="it-s" ${!x||x.for_sale!==false?(x&&Number(x.price)==0?"":"checked"):""}> بيتباع في الكاشير</label>
<div id="it-sb" style="${!x||x.for_sale!==false?(x&&Number(x.price)==0?"display:none":""):"display:none"}">${itIn("سعر البيع","it-pr",x?matFm(x.price):"","inputmode=\"decimal\"")}</div>
${x?"":itIn("الكمية الموجودة دلوقتي (علب/قطع، اختياري)","it-q","0","inputmode=\"numeric\"")}
<button class="btn" style="margin-top:14px;width:100%" onclick="itSave(this,${x?x.id:"null"})">حفظ</button>`);
$("it-c").onchange=e=>{$("it-cb").style.display=e.target.checked?"":"none"};$("it-s").onchange=e=>{$("it-sb").style.display=e.target.checked?"":"none"}}

async function itSave(b,id){if(C.itBusy||b.disabled)return;const x=id==null?null:(C.stk||[]).find(a=>a.id==id);
const n=$("it-n").value.trim();if(!n)return toast("اكتب اسم الصنف");
const c=$("it-c").checked,u=$("it-u").value.trim()||"جرام",pk=c?matQ($("it-p").value):1,co=matQ($("it-co").value),mn=matQ($("it-mn").value),sale=$("it-s").checked,pr=sale?matQ($("it-pr").value):0,q=x?0:matQ($("it-q").value);
if(c&&!(pk>0))return toast("اكتب العلبة فيها كام");if(!(co>=0))return toast("سعر الشراء غلط");if(!(mn>=0))return toast("الحد الأدنى غلط");if(sale&&!(pr>=0&&$("it-pr").value.trim()!==""))return toast("اكتب سعر البيع");
if(!x&&(!(q>=0)||!Number.isInteger(q)))return toast("الكمية لازم عدد صحيح");
const rec=[],gm=x&&C.itBy[x.id];
C.itBusy=1;b.disabled=true;
const{data,error}=await sb.rpc("item_save",{p_id:id,p_name:n,p_unit:u,p_pack:pk,p_cost:co,p_price:pr,p_for_sale:sale,p_min:mn,p_group:c&&gm?gm.group_name||null:null,p_consumable:c,p_consumption:rec});
let w2="";if(!error&&!x&&q>0){const r=await sb.rpc("restock_product",{p_id:data,p_qty:q});if(r.error)w2=r.error.message}
C.itBusy=0;b.disabled=false;if(error)return toast(itErr(error));svcClose();toast(w2?"اتحفظ بس الكمية فشلت: "+w2:"اتحفظ ✓");itRe()}

// ===== جرد صنف =====
async function itCount(id){if(C.itBusy)return;const x=(C.stk||[]).find(a=>a.id==id);if(!x)return;const mm=C.itBy[x.id];
const b=matQ(await askInput("عدد العلب الكاملة الموجودة من «"+x.name+"»\nالنظام شايف: "+x.stock,String(x.stock)));if(b===null)return;if(!(b>=0)||!Number.isInteger(b))return toast("عدد العلب لازم رقم صحيح");
let o=0;if(mm){o=matQ(await askInput("كام "+mm.unit+" في العلبة المفتوحة؟ (0 لو مفيش)\nالنظام شايف: "+matFm(mm.open_qty),String(matFm(mm.open_qty))));if(o===null)return;if(!(o>=0))return toast("الكمية غلط")}
C.itBusy=1;const{error}=await sb.rpc("item_count",{p_product:id,p_boxes:b,p_open:o,p_note:"جرد"});C.itBusy=0;error?toast(itErr(error)):(toast("اتسجّل الجرد ✓"),itRe())}

// ===== صرف للمحل =====
async function itIssue(mid){if(C.itBusy)return;const m=(C.mat||[]).find(a=>a.id==mid);if(!m)return;
const q=matQ(await askInput("كام "+m.unit+" نازلين من «"+m.name+"» للمحل؟\nالرصيد: "+matFm(m.stock)+" "+m.unit+"\nالكمية دي بتتخصم من المخزون وبتتسجّل في الاستهلاك.",""));if(q===null)return;if(!(q>0))return toast("اكتب كمية أكبر من صفر");
const nt=await askInput("ملاحظة (اختياري)","");
C.itBusy=1;const{data,error}=await sb.rpc("item_issue",{p_material:mid,p_qty:q,p_note:nt||null});C.itBusy=0;error?toast(itErr(error)):(toast("اتسجّل. الباقي "+matFm(data)+" "+m.unit),itRe())}

// ===== مسح =====
async function itDel(id){if(C.itBusy)return;const x=(C.stk||[]).find(a=>a.id==id);if(!x)return;
if(!await askConfirm("مسح «"+x.name+"»؟\nهيتشال من المخزون والكاشير واستهلاك الخدمات، وسجلّه وفواتيره القديمة بتفضل محفوظة. الرصيد الحالي: "+x.stock,{ok:"امسح"}))return;
C.itBusy=1;const{data,error}=await sb.rpc("product_delete",{p_id:id});C.itBusy=0;if(error)return toast(error.message);toast(data=="deleted"?"اتمسح ✓":"اتمسح (اتأرشف وسجله محفوظ) ✓");itRe()}

// ===== تحويل خامة قديمة =====
async function itConv(mid){if(C.itBusy)return;const m=(C.mat||[]).find(a=>a.id==mid);if(!m)return;
const pk=matQ(await askInput("العلبة من «"+m.name+"» فيها كام "+m.unit+"؟",""));if(pk===null)return;if(!(pk>0))return toast("الرقم غلط");
const pc=matQ(await askInput("سعر شراء العلبة الواحدة (جنيه)\nالتكلفة الحالية المسجّلة: "+matFm(m.cost)+" للـ"+m.unit,""));if(pc===null)return;if(!(pc>=0))return toast("السعر غلط");
const pr=matQ(await askInput("سعر البيع في الكاشير (اكتب 0 لو للاستهلاك بس)","0"));if(pr===null)return;if(!(pr>=0))return toast("السعر غلط");
C.itBusy=1;const{error}=await sb.rpc("item_from_material",{p_material:mid,p_pack:pk,p_pack_cost:pc,p_price:pr,p_for_sale:pr>0});C.itBusy=0;error?toast(itErr(error)):(toast("اتحوّل لصنف ✓"),itRe())}

// ===== حركة صنف (مخزون + استهلاك) =====
async function itLog(id){const x=(C.stk||[]).find(a=>a.id==id);if(!x)return;const mm=C.itBy[x.id];
const[a,b]=await Promise.all([sb.from("stock_movements").select("qty,reason,created_at").eq("product_id",id).order("created_at",{ascending:false}).limit(60),
  mm?sb.from("material_movements").select("qty,reason,invoice_id,note,created_at").eq("material_id",mm.id).order("created_at",{ascending:false}).limit(60):Promise.resolve({data:[]})]);
if(a.error)return toast(a.error.message);
const R={restock:"توريد",count:"جرد",sale:"بيع",service_open:"فتح علبة للاستهلاك",service_void:"رجوع علبة (إلغاء فاتورة)",purchase_void:"إلغاء فاتورة شراء",service:"خدمة",issue:"صرف للمحل",service_option:"خامة اختيارية"};
const L=[...(a.data||[]).map(r=>({t:r.created_at,l:(R[r.reason]||r.reason)+" (علب)",q:r.qty,n:""})),...(b.data||[]).filter(r=>r.reason!="restock").map(r=>({t:r.created_at,l:(R[r.reason]||r.reason)+" ("+mm.unit+")",q:r.qty,n:(r.invoice_id?" · فاتورة #"+r.invoice_id:"")+(r.note?" · "+r.note:"")}))].sort((p,q)=>q.t<p.t?-1:1).slice(0,80);
itSheet("حركة «"+esc(x.name)+"»",L.length?L.map(r=>`<div class="row"><div><b>${esc(r.l)}</b><div class="m">${new Date(r.t).toLocaleString("ar-EG")}${esc(r.n)}</div></div><span class="tag" style="${Number(r.q)<0?"background:var(--red);color:#fff":""}">${Number(r.q)>0?"+":""}${matFm(r.q)}</span></div>`).join(""):`<p class="m">مفيش حركة.</p>`)}

// ===== حفظ الجرد =====
async function itBulkSave(b){if(b.disabled)return;const ins=[...document.querySelectorAll("#cnt-b input[data-k]")],jobs=[],seen={};
for(const i of ins){const k=i.dataset.k,id=+i.dataset.id;if(k=="m"){if(i.value.trim()==i.dataset.o)continue;const q=matQ(i.value);if(!(q>=0))return toast("كمية غلط");jobs.push({m:id,q});continue}
 const pe=document.querySelector(`#cnt-b input[data-k="p"][data-id="${id}"]`),oe=document.querySelector(`#cnt-b input[data-k="o"][data-id="${id}"]`);if(seen[id])continue;seen[id]=1;
 const ch=pe.value.trim()!=pe.dataset.o||(oe&&oe.value.trim()!=oe.dataset.o);if(!ch)continue;const bx=matQ(pe.value),op=oe?matQ(oe.value):0;
 if(!(bx>=0)||!Number.isInteger(bx))return toast("عدد العلب لازم رقم صحيح");if(!(op>=0))return toast("كمية المفتوح غلط");jobs.push({p:id,b:bx,o:op})}
if(!jobs.length)return toast("مفيش تغيير")
if(!await askConfirm("تسجّل جرد "+jobs.length+" صنف وتعدّل الأرصدة؟"))return;
b.disabled=true;let err=null,done=0;for(const j of jobs){const r=j.m!=null?await sb.rpc("material_count",{p_id:j.m,p_counted:j.q,p_note:"جرد شامل"}):await sb.rpc("item_count",{p_product:j.p,p_boxes:j.b,p_open:j.o,p_note:"جرد شامل"});if(r.error){err=r.error;break}done++}
b.disabled=false;if(err){toast("اتسجّل "+done+" وبعدين وقف: "+itErr(err));V.cnt();return}toast("اتسجّل جرد "+done+" صنف ✓");V.cnt()}

// ===== تقرير الاستهلاك =====
async function itRep(){const d=new Date(),f=new Date(d.getFullYear(),d.getMonth(),1),y=x=>new Date(x.getTime()-x.getTimezoneOffset()*6e4).toISOString().slice(0,10);
C.itFrom=C.itFrom||y(f);C.itTo=C.itTo||y(d);const{data,error}=await sb.rpc("items_consumption",{p_from:C.itFrom,p_to:C.itTo});if(error)return toast(itErr(error));
const T=(data||[]).reduce((a,r)=>a+Number(r.cost),0);
itSheet("تقرير الاستهلاك",`<div class="chips" style="align-items:center"><span class="m">من</span><input type="date" value="${C.itFrom}" onchange="C.itFrom=this.value;itRep()" style="width:auto;margin:0"><span class="m">إلى</span><input type="date" value="${C.itTo}" onchange="C.itTo=this.value;itRep()" style="width:auto;margin:0"></div>
<p class="m">إجمالي تكلفة الاستهلاك: <b>${fm(T)}</b></p>`+((data||[]).length?data.map(r=>`<div class="row"><div><b>${esc(r.name)}</b><div class="m">خدمات ${matFm(r.service_qty)} · صرف للمحل ${matFm(r.issue_qty)} ${esc(r.unit)}</div></div><span class="tag">${fm(r.cost)}</span></div>`).join(""):`<p class="m">مفيش استهلاك في الفترة دي.</p>`))}
