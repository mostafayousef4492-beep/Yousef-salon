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
<button class="btn" style="width:100%;margin:14px 0 12px" onclick="svcOpen()">+ خدمة جديدة</button>
${S.l.length>6?`<input id="svq" type="search" placeholder="دوّر على خدمة..." aria-label="بحث" oninput="C.svc.q=this.value;svcList()">`:""}
<div class="chips" id="svch"></div><div id="svl"></div>`);svcChips();svcList()}

function svcChips(){const S=C.svc,cs=svcCats(),h=$("svch");if(!h)return;
h.innerHTML=cs.length>1?`<button class="chip ${S.c?"":"sel"}" onclick="C.svc.c='';svcChips();svcList()">الكل</button>`+cs.map((c,i)=>`<button class="chip ${S.c===c?"sel":""}" data-i="${i}" onclick="C.svc.c=svcCats()[${i}];svcChips();svcList()">${esc(c)}</button>`).join(""):""}

function svcList(){const S=C.svc,q=S.q.trim().toLowerCase(),g={};
S.l.filter(x=>(!S.c||(x.category||"قصات")==S.c)&&(!q||(x.name+" "+(x.category||"")).toLowerCase().includes(q))).forEach(x=>(g[x.category||"قصات"]=g[x.category||"قصات"]||[]).push(x));
const ks=Object.keys(g);
$("svl").innerHTML=ks.length?ks.map(k=>`<h2>${esc(k)}</h2>`+g[k].map(x=>`<button class="row svc${x.active?"":" off"}" onclick="svcOpen(${x.id})"><div><b>${esc(x.name)}</b><div class="m">${num(x.duration_min||30)} دقيقة${x.active?"":" · موقوفة (مخفية عن العملاء)"}</div></div><b class="svc-p">${fm(x.price)}</b></button>`).join("")).join(""):`<p class="m empty">${S.l.length?"مفيش خدمة بالاسم ده.":"لسه مفيش خدمات. ضيف أول خدمة من الزرار اللي فوق."}</p>`}

function svcClose(){C.dsL=null;const w=$("sheet");if(w){w.classList.add("out");setTimeout(()=>w.remove(),160)}}

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
