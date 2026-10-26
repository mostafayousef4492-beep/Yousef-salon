/* features/catalog/services.js — الخدمات والأسعار */

async function editItem(t,id){const x=C.cat[t].find(y=>y.id==id),n=prompt("الاسم",x.name);if(n===null)return;const pr=prompt("سعر البيع",x.price);if(pr===null)return;const u={name:n,price:+pr};
if(t=="services"){const d=prompt("المدة بالدقايق",x.duration_min);if(d===null)return;u.duration_min=+d;u.category=prompt("القسم (قصات / ذقن / عناية ...)",x.category||"قصات")||"قصات";u.description=prompt("وصف قصير (اختياري)",x.description||"")||null}else{const c=prompt("سعر الشراء",x.cost);if(c===null)return;const m=prompt("الحد الأدنى للمخزون",x.min_stock);if(m===null)return;u.cost=+c;u.min_stock=+m}
const{error}=await sb.from(t).update(u).eq("id",id);error?toast(error.message):V.set()}

async function toggleItem(t,id,a){await sb.from(t).update({active:a}).eq("id",id);V.set()}

async function addItem(t){const n=prompt("الاسم");if(!n)return;const pr=+prompt("سعر البيع");if(!(pr>=0))return;const o=t=="services"?{name:n,price:pr,duration_min:+prompt("المدة بالدقايق","30")||30,category:prompt("القسم (قصات / ذقن / عناية ...)","قصات")||"قصات"}:{name:n,price:pr,cost:+prompt("سعر الشراء","0")||0,stock:+prompt("الكمية الحالية","0")||0,min_stock:+C.cfg.low_stock_default||5};
const{error}=await sb.from(t).insert(o);error?toast(error.message):V.set()}

// ===== نظام الخدمات (شاشة مستقلة للمالك) =====

V.svc=async()=>{const{data,error}=await sb.from("services").select("*").order("category").order("price");
if(error)return put(`<h1>الخدمات</h1><p class="m">${esc(error.message)}</p>`);
C.svc={l:data||[],q:"",c:"",e:0};drawSvc()};

const svcCats=()=>[...new Set(C.svc.l.map(x=>x.category||"قصات"))];

function drawSvc(){const S=C.svc,on=S.l.filter(x=>x.active).length;
put(`<h1>الخدمات</h1><div class="m">${num(on)} شغّالة${S.l.length-on?" · "+num(S.l.length-on)+" موقوفة":""}</div>
<div class="chips" style="margin:14px 0 12px"><button class="btn" style="flex:1" onclick="svcOpen()">+ خدمة جديدة</button><button class="btn g" style="flex:1" onclick="grpOpen()">+ خدمة بخيارات</button></div><div id="bnd"></div>
${S.l.length>6?`<input id="svq" type="search" placeholder="دوّر على خدمة..." aria-label="بحث" oninput="C.svc.q=this.value;svcList()">`:""}
<div class="chips" id="svch"></div><div id="svl"></div>`);svcChips();svcList();bndLoad()}

function svcChips(){const S=C.svc,cs=svcCats(),h=$("svch");if(!h)return;
h.innerHTML=cs.length>1?`<button class="chip ${S.c?"":"sel"}" onclick="C.svc.c='';svcChips();svcList()">الكل</button>`+cs.map((c,i)=>`<button class="chip ${S.c===c?"sel":""}" data-i="${i}" onclick="C.svc.c=svcCats()[${i}];svcChips();svcList()">${esc(c)}</button>`).join(""):""}

function svcList(){const S=C.svc,q=S.q.trim().toLowerCase(),g={};
S.l.filter(x=>(!S.c||(x.category||"قصات")==S.c)&&(!q||(x.name+" "+(x.category||"")).toLowerCase().includes(q))).forEach(x=>(g[x.category||"قصات"]=g[x.category||"قصات"]||[]).push(x));
const ks=Object.keys(g);
$("svl").innerHTML=ks.length?ks.map(k=>`<h2>${esc(k)}</h2>`+g[k].map(x=>x.group_name?(g[k].find(y=>y.group_name==x.group_name)===x?grpRow(x.group_name):""):`<button class="row svc${x.active?"":" off"}" onclick="svcOpen(${x.id})"><div><b>${esc(x.name)}</b><div class="m">${num(x.duration_min||30)} دقيقة${x.active?"":" · موقوفة (مخفية عن العملاء)"}</div></div><b class="svc-p">${fm(x.price)}</b></button>`).join("")).join(""):`<p class="m empty">${S.l.length?"مفيش خدمة بالاسم ده.":"لسه مفيش خدمات. ضيف أول خدمة من الزرار اللي فوق."}</p>`}


function svcOpen(id){const x=id?C.svc.l.find(y=>y.id==id):{name:"",price:"",duration_min:30,category:"",description:"",active:true};if(!x)return;C.svc.e=id||0;
const o=$("sheet");if(o)o.remove();const w=document.createElement("div");w.id="sheet";w.className="sheet-bg";w.onclick=e=>{if(e.target==w)svcClose()};
w.innerHTML=`<div class="sheet" role="dialog" aria-modal="true"><div class="sheet-h"><b>${id?"تعديل خدمة":"خدمة جديدة"}</b><button class="btn g s" onclick="svcClose()" aria-label="إغلاق">✕</button></div>
<label class="m" for="sf-n">اسم الخدمة</label><input id="sf-n" value="${esc(x.name)}" placeholder="مثال: قصة + دقن" autocomplete="off">
<div class="svc-2"><div><label class="m" for="sf-p">السعر (${esc(C.cfg.currency)})</label><input id="sf-p" type="number" inputmode="decimal" min="0" value="${esc(x.price)}"></div><div><label class="m" for="sf-d">المدة (دقيقة)</label><input id="sf-d" type="number" inputmode="numeric" min="5" step="5" value="${esc(x.duration_min||30)}"></div></div>
<label class="m" for="sf-c">القسم</label><input id="sf-c" value="${esc(id?(x.category||"قصات"):"")}" placeholder="قصات / ذقن / عناية ..." autocomplete="off">
<div class="chips">${svcCats().map((c,i)=>`<button type="button" class="chip" onclick="$('sf-c').value=svcCats()[${i}]">${esc(c)}</button>`).join("")}</div>
<label class="m" for="sf-ds">وصف قصير (اختياري)</label><input id="sf-ds" value="${esc(x.description||"")}" autocomplete="off">
<label class="svc-sw"><input id="sf-a" type="checkbox" ${x.active?"checked":""}><span>شغّالة — ظاهرة للعملاء وفي الكاشير</span></label>
<button class="btn" id="sf-s" style="width:100%" onclick="svcSave()">${id?"حفظ التعديل":"إضافة الخدمة"}</button></div>`;
document.body.appendChild(w);setTimeout(()=>$("sf-n").focus(),60)}

async function svcSave(){const n=$("sf-n").value.trim(),p=parseFloat($("sf-p").value),d=Math.round(+$("sf-d").value)||30;
if(!n)return toast("اكتب اسم الخدمة");if(!(p>=0))return toast("اكتب سعر صحيح");
const o={name:n,price:p,duration_min:d,category:$("sf-c").value.trim()||"قصات",description:$("sf-ds").value.trim()||null,active:$("sf-a").checked};
const b=$("sf-s");b.disabled=true;
const{error}=C.svc.e?await sb.from("services").update(o).eq("id",C.svc.e):await sb.from("services").insert(o);
b.disabled=false;if(error)return toast(error.message);svcClose();toast("تم الحفظ ✓");V.svc()}


// ===== الباقات (إدارة): مجموعة خدمات بسعر أقل من مجموعها =====

async function bndLoad(){const el=$("bnd");if(!el)return;
  const{data,error}=await sb.rpc("bundles_list",{p_all:true});
  if(error){el.innerHTML=/bundles_list|PGRST202|42883/.test(error.code+" "+error.message)?"":`<p class="m">${esc(error.message)}</p>`;return}
  C.bnd=data||[];
  el.innerHTML=`<h2>الباقات</h2><button class="btn g" style="width:100%;margin-bottom:8px" onclick="bndOpen()">+ باقة جديدة</button>`
   +(C.bnd.length?C.bnd.map(b=>`<button class="row svc${b.active?"":" off"}" onclick="bndOpen(${b.id})"><div><b>🎁 ${esc(b.name)}</b><div class="m">${(b.services||[]).map(x=>esc(x.name)).join(" + ")}</div><div class="m">لوحدها ${fm(b.full)} · وفّر ${fm(b.saving)}${b.active?"":" · موقوفة (مخفية عن العملاء)"}</div></div><b class="svc-p">${fm(b.price)}</b></button>`).join(""):`<p class="m">لسه مفيش باقات. الباقة بتجمّع كذا خدمة بسعر أقل من مجموعهم.</p>`)}

function bndOpen(id){const b=id&&(C.bnd||[]).find(x=>x.id==id);
  C.bn=b?{id:b.id,name:b.name,desc:b.description||"",price:String(b.price),active:b.active,s:(b.services||[]).map(x=>x.id)}:{id:null,name:"",desc:"",price:"",active:true,s:[]};bndDraw()}

function bndSum(){const B=C.bn,full=(C.svc?C.svc.l:[]).filter(x=>B.s.includes(x.id)).reduce((a,x)=>a+(+x.price||0),0),pr=+B.price||0;
  return B.s.length<2?`<div class="m">اختار خدمتين على الأقل</div>`:`<div class="m">الخدمات لوحدها ${fm(full)}${pr>0&&pr<full?` · الباقة ${fm(pr)} · الخصم ${fm(full-pr)} (${Math.round((full-pr)/full*100)}%)`:pr>=full?` · <span style="color:var(--red)">سعر الباقة لازم يبقى أقل من ${fm(full)}</span>`:""}</div>`}

function bndDraw(){const B=C.bn,SV=(C.svc?C.svc.l:[]).filter(x=>x.active||B.s.includes(x.id));
  dsOpen(B.id?"تعديل باقة":"باقة جديدة",`<div class="box"><input id="bn_n" placeholder="اسم الباقة (مثلاً: باقة العريس)" value="${esc(B.name)}" oninput="C.bn.name=this.value"><input id="bn_d" placeholder="وصف قصير (اختياري)" value="${esc(B.desc)}" oninput="C.bn.desc=this.value">
<div class="m">الخدمات اللي في الباقة:</div><div class="chips">${SV.map(x=>`<button class="chip ${B.s.includes(x.id)?"sel":""}" onclick="bndTg(${x.id})">${esc(x.name)} · ${x.price}</button>`).join("")}</div>
<input id="bn_p" type="number" inputmode="decimal" placeholder="سعر الباقة" value="${esc(B.price)}" oninput="C.bn.price=this.value;$('bn_s').innerHTML=bndSum()"><div id="bn_s">${bndSum()}</div>
<label class="chips" style="align-items:center"><input type="checkbox" ${B.active?"checked":""} onchange="C.bn.active=this.checked" style="width:auto;margin:0"> <span>شغّالة (ظاهرة للعملاء)</span></label>
<button class="btn" onclick="bndSave()">حفظ</button>${B.id?`<button class="btn g" onclick="bndDel(${B.id})">حذف الباقة</button>`:""}</div>`)}

function bndTg(id){const B=C.bn;B.s=B.s.includes(id)?B.s.filter(x=>x!=id):[...B.s,id];bndDraw()}

async function bndSave(){const B=C.bn;if(B.s.length<2)return toast("اختار خدمتين على الأقل");const pr=parseFloat(B.price);if(!(pr>=0))return toast("اكتب سعر الباقة");
  const{error}=await sb.rpc("admin_save_bundle",{p_id:B.id,p_name:B.name,p_desc:B.desc,p_price:pr,p_active:B.active,p_services:B.s});
  if(error)return toast(error.message);toast("اتحفظت ✓");svcClose();bndLoad()}

async function bndDel(id){if(!confirm("تحذف الباقة؟ الحجوزات اللي عليها هتفضل بخدماتها بس من غير خصم."))return;const{error}=await sb.rpc("admin_delete_bundle",{p_id:id});if(error)return toast(error.message);svcClose();bndLoad()}


// ===== خدمة بخيارات: كل اختيار بسعره (قص الشعر: كلاسيك / تدريج) =====
// كل اختيار بيتخزن كخدمة عادية (name = «المجموعة — الاختيار») ليها group_name و option_label، فباقي النظام شغال زي ما هو
const grpNames=()=>[...new Set(C.svc.l.filter(x=>x.group_name).map(x=>x.group_name))];
function grpRow(g){const L=C.svc.l.filter(x=>x.group_name==g),on=L.filter(x=>x.active);
return `<button class="row svc${on.length?"":" off"}" onclick="grpOpen(${grpNames().indexOf(g)})"><div><b>${esc(g)}</b><div class="m">${on.length?on.map(x=>esc(x.option_label)+" "+fm(x.price)).join(" · "):"كل الاختيارات موقوفة"}</div></div><span class="tag">${num(on.length)} اختيارات</span></button>`}
function grpOpen(i){const g=i==null?"":grpNames()[i]||"",L=g?C.svc.l.filter(x=>x.group_name==g):[];
C.svg={g,rows:L.length?L.map(x=>({id:x.id,label:x.option_label,price:x.price,dur:x.duration_min||30,active:x.active,cat:x.category})):[{label:"",price:"",dur:30,active:true},{label:"",price:"",dur:30,active:true}],cat:L[0]?L[0].category:""};
const o=$("sheet");if(o)o.remove();const w=document.createElement("div");w.id="sheet";w.className="sheet-bg";w.onclick=e=>{if(e.target==w)svcClose()};
w.innerHTML=`<div class="sheet" role="dialog" aria-modal="true"><div class="sheet-h"><b>${g?"تعديل خدمة بخيارات":"خدمة بخيارات"}</b><button class="btn g s" onclick="svcClose()" aria-label="إغلاق">✕</button></div>
<label class="m" for="sg-g">اسم الخدمة</label><input id="sg-g" value="${esc(g)}" placeholder="مثال: قص الشعر" autocomplete="off">
<label class="m" for="sg-c">القسم</label><input id="sg-c" value="${esc(C.svg.cat||"")}" placeholder="قصات / ذقن / صبغة ..." autocomplete="off">
<div class="m" style="margin-top:8px">الاختيارات (العميل بيختار واحد بس، وكل واحد بسعره)</div><div id="sg-r"></div>
<button class="btn g s" onclick="grpAdd()">+ اختيار جديد</button>
<button class="btn" id="sg-s" style="width:100%;margin-top:12px" onclick="grpSave()">حفظ</button>${g?`<div class="chips" style="margin-top:10px"><button class="btn g s" style="flex:1" onclick="grpAll(${L.some(x=>x.active)?0:1})">${L.some(x=>x.active)?"إيقاف الخدمة كلها":"تشغيل الخدمة كلها"}</button><button class="btn g s" style="flex:1;color:var(--red)" onclick="grpDel()">🗑 حذف الخدمة</button></div><div class="m" style="margin-top:6px">الإيقاف بيخفيها عن العملاء من غير ما يمسح حاجة. الحذف بيمسحها نهائيًا، ولو مستخدمة في حجوزات قديمة بتتوقف بدل ما تتمسح.</div>`:""}</div>`;
document.body.appendChild(w);grpDraw();setTimeout(()=>$("sg-g").focus(),60)}
function grpDraw(){const R=C.svg.rows;$("sg-r").innerHTML=R.map((r,i)=>r.gone?"":`<div class="box" style="margin:6px 0${r.active?"":";opacity:.6"}"><input placeholder="اسم الاختيار (مثال: كلاسيك)" value="${esc(r.label)}" oninput="C.svg.rows[${i}].label=this.value"><div class="svc-2"><div><input type="number" inputmode="decimal" min="0" placeholder="السعر" value="${esc(r.price)}" oninput="C.svg.rows[${i}].price=this.value"></div><div><input type="number" inputmode="numeric" min="5" step="5" placeholder="المدة (دقيقة)" value="${esc(r.dur)}" oninput="C.svg.rows[${i}].dur=this.value"></div></div><div class="chips"><label class="svc-sw" style="margin:0"><input type="checkbox" ${r.active?"checked":""} onchange="C.svg.rows[${i}].active=this.checked;grpDraw()"><span>شغّال</span></label>${r.id?`<button class="btn s g" style="color:var(--red)" onclick="grpOptDel(${i})">حذف</button>`:`<button class="btn s g" onclick="C.svg.rows[${i}].gone=1;grpDraw()">حذف</button>`}</div></div>`).join("")}
function grpAdd(){C.svg.rows.push({label:"",price:"",dur:30,active:true});grpDraw()}
async function grpSave(){const S=C.svg,g=$("sg-g").value.trim(),cat=$("sg-c").value.trim()||"قصات";
if(!g)return toast("اكتب اسم الخدمة");
const rows=S.rows.filter(r=>!r.gone&&(r.id||r.label.trim()||r.price!==""));
for(const r of rows){if(!r.label.trim())return toast("اكتب اسم كل اختيار");if(!(parseFloat(r.price)>=0))return toast("اكتب سعر صحيح للاختيار «"+r.label+"»")}
const labs=rows.map(r=>r.label.trim());if(new Set(labs).size!=labs.length)return toast("اسم الاختيار متكرر");
{const on=rows.filter(r=>r.active).length;if(on==1)return toast("لازم اختياريين شغّالين على الأقل (أو وقّف الخدمة كلها)، وإلا اعمل خدمة عادية")}
if(g!==S.g&&C.svc.l.some(x=>x.group_name==g))return toast("فيه خدمة بخيارات بنفس الاسم");
const b=$("sg-s");b.disabled=true;let err=null;
for(const r of rows){const o={name:g+" — "+r.label.trim(),price:parseFloat(r.price),duration_min:Math.round(+r.dur)||30,category:cat,group_name:g,option_label:r.label.trim(),active:r.active};
const q=r.id?await sb.from("services").update(o).eq("id",r.id):await sb.from("services").insert(o);if(q.error){err=q.error;break}}
b.disabled=false;if(err)return toast(err.message);svcClose();toast("تم الحفظ ✓");V.svc()}

/* حذف/إيقاف الخدمات اللي بخيارات: الحذف الفعلي لو مفيش حجوزات عليها، وإلا بتتوقف */
async function grpRemove(ids){
  if(!ids.length)return{del:0,off:0};
  const gone=[];
  for(const id of ids){const d=await sb.from("services").delete().eq("id",id).select("id");if(!d.error&&d.data&&d.data.length)gone.push(id)}
  const rest=ids.filter(i=>!gone.includes(i));
  let off=0;
  if(rest.length){const u=await sb.from("services").update({active:false}).in("id",rest);if(u.error)throw u.error;off=rest.length}
  return{del:gone.length,off}}
async function grpDel(){const g=C.svg&&C.svg.g;if(!g)return;
  if(!confirm("حذف الخدمة «"+g+"» بكل اختياراتها؟"))return;
  try{const ids=C.svc.l.filter(x=>x.group_name==g).map(x=>x.id),r=await grpRemove(ids);
    svcClose();toast(r.off?"اتمسح "+r.del+" واتوقف "+r.off+" (مستخدمين في حجوزات قديمة)":"اتمسحت الخدمة ✓");V.svc()}catch(e){toast(e.message)}}
async function grpOptDel(i){const r=C.svg.rows[i];if(!r||!r.id)return;
  const live=C.svg.rows.filter(x=>!x.gone&&x.id!=r.id&&x.active).length;
  if(r.active&&live<2&&!confirm("كده هيفضل أقل من اختياريين شغّالين. الأحسن توقف الخدمة كلها. تكمل الحذف؟"))return;
  if(!confirm("حذف الاختيار «"+r.label+"»؟"))return;
  try{const x=await grpRemove([r.id]);r.gone=1;toast(x.off?"الاختيار مستخدم في حجوزات قديمة فاتوقف بدل ما يتمسح":"اتمسح ✓");grpDraw();V.svc()}catch(e){toast(e.message)}}
async function grpAll(on){const g=C.svg&&C.svg.g;if(!g)return;
  const{error}=await sb.from("services").update({active:!!on}).eq("group_name",g);
  if(error)return toast(error.message);svcClose();toast(on?"الخدمة اشتغلت ✓":"الخدمة اتوقفت وبقت مخفية عن العملاء");V.svc()}
