/* features/money/backfill.js — تسجيل مبيعات يوم فات */

/* ===== تسجيل مبيعات يوم فات (المالك) — بيستخدم admin_backfill_invoices ===== */

const bfRow=()=>({n:1,time:"",barber:"",method:"cash",s:[],p:{},cust:null,cn:""});

async function bfOpen(){const box=$("bf");if(!box)return;if(box.innerHTML){box.innerHTML="";C.bf=null;return}
box.innerHTML=`<p class="m">بنحمّل الخدمات...</p>`;
const[{data:sv,error:e1},{data:pr},{data:br}]=await Promise.all([sb.from("services").select("id,name,price").eq("active",true).order("name"),sb.from("products").select("id,name,price").eq("active",true).order("name"),sb.from("profiles").select("id,full_name").eq("role","barber").order("full_name")]);
if(e1){box.innerHTML="";return toast(e1.message)}
const y=new Date();y.setDate(y.getDate()-1);
C.bf={day:C.cd&&C.cd<ymd(new Date())?C.cd:ymd(y),sv:sv||[],pr:pr||[],br:br||[],rows:[bfRow()]};bfDraw()}

function bfPrice(r){const B=C.bf;return sumOf(r.s,id=>(B.sv.find(x=>x.id==id)||{}).price)+sumOf(Object.keys(r.p),id=>((B.pr.find(x=>x.id==id)||{}).price||0)*r.p[id])}

function bfDraw(){const B=C.bf,box=$("bf");if(!B||!box)return;
const tot=sumOf(B.rows,r=>bfPrice(r)*r.n),cnt=sumOf(B.rows,r=>r.n),M=[["cash","كاش"],["card","كارت"],["wallet","محفظة"]];
box.innerHTML=`<div class="box" style="margin:8px 0"><div class="m" style="margin-bottom:6px">فواتير يوم فات (بتتسجل بتاريخ اليوم ده، والمخزون والنقاط والعمولة بتتحسب عادي)</div><label class="m">اليوم</label><input type="date" max="${ymd(new Date())}" value="${B.day}" onchange="C.bf.day=this.value" style="width:auto"></div>`+
B.rows.map((r,i)=>`<div class="box" style="margin:8px 0"><div class="chips" style="align-items:center;justify-content:space-between"><b>فاتورة ${i+1}</b>${B.rows.length>1?`<button class="btn s g" onclick="bfDel(${i})">حذف</button>`:""}</div>
<div class="m">العميل (اختياري — بيتحسبله النقاط والزيارة)</div>${r.cust?`<div class="chips" style="align-items:center"><span class="chip sel">${esc(r.cn)}</span><button class="btn s g" onclick="bfCu(${i},null,'')">شيل</button></div>`:`<input id="bfq${i}" placeholder="دوّر باسم أو موبايل العميل" oninput="bfFind(${i})" autocomplete="off"><div id="bfl${i}"></div>`}
<select onchange="bfSet(${i},'barber',this.value)"><option value="">الحلاق (اختياري)</option>${B.br.map(b=>`<option value="${b.id}" ${r.barber==b.id?"selected":""}>${esc(b.full_name)}</option>`).join("")}</select>
<div class="m">الخدمات</div><div class="chips">${B.sv.map(x=>`<button class="chip ${r.s.includes(x.id)?"sel":""}" onclick="bfSv(${i},${x.id})">${esc(x.name)} · ${fm(x.price)}</button>`).join("")||`<span class="m">مفيش خدمات</span>`}</div>
${B.pr.length?`<div class="m">المنتجات (اضغط يزيد واحد، − ينقص)</div><div class="chips">${B.pr.map(x=>{const q=r.p[x.id]||0;return `<button class="chip ${q?"sel":""}" onclick="bfPr(${i},${x.id},1)">${esc(x.name)}${q?" ×"+q:""}</button>${q?`<button class="chip" onclick="bfPr(${i},${x.id},-1)">−</button>`:""}`}).join("")}</div>`:""}
<div class="chips" style="align-items:center"><select onchange="bfSet(${i},'method',this.value)" style="width:auto;margin:0">${M.map(m=>`<option value="${m[0]}" ${r.method==m[0]?"selected":""}>${m[1]}</option>`).join("")}</select>${t24("bft"+i,r.time,`onchange="bfSet(${i},'time',this.value)"`)}<span class="m">الوقت (اختياري)</span></div>
<label class="m">عدد مرات تكرار الفاتورة دي (لو نفس الشغل اتكرر)</label><input type="number" inputmode="numeric" min="1" value="${r.n}" onchange="bfSet(${i},'n',Math.max(1,parseInt(this.value)||1))" style="width:90px">
<div class="m">إجمالي الفاتورة: <b>${fm(bfPrice(r))}</b>${r.n>1?` × ${r.n} = <b>${fm(bfPrice(r)*r.n)}</b>`:""}</div></div>`).join("")+
`<div class="chips"><button class="btn g" style="flex:1" onclick="bfAdd()">+ فاتورة تانية</button></div><div class="box" style="margin:8px 0"><b>${cnt} فاتورة · ${fm(tot)}</b><button class="btn" style="width:100%;margin-top:8px" onclick="bfSave()">حفظ كل الفواتير</button></div>`}

function bfSet(i,k,v){C.bf.rows[i][k]=v;if(k=="n")bfDraw()}

function bfSv(i,id){const r=C.bf.rows[i];r.s=r.s.includes(id)?r.s.filter(x=>x!=id):[...r.s,id];bfDraw()}

function bfPr(i,id,d){const r=C.bf.rows[i],q=Math.max(0,(r.p[id]||0)+d);if(q)r.p[id]=q;else delete r.p[id];bfDraw()}

function bfAdd(){C.bf.rows.push(bfRow());bfDraw()}

function bfDel(i){C.bf.rows.splice(i,1);bfDraw()}

async function bfSave(force){const B=C.bf;if(!B||C.bfBusy)return;if(!B.day)return toast("اختار اليوم");
if(B.rows.some(r=>!r.s.length&&!Object.keys(r.p).length))return toast("فيه فاتورة فاضية، اختار فيها خدمة أو احذفها");
const list=[];B.rows.forEach(r=>{const items=[...r.s.map(id=>({type:"service",id,qty:1})),...Object.keys(r.p).map(id=>({type:"product",id:+id,qty:r.p[id]}))];for(let k=0;k<r.n;k++)list.push({customer:r.cust||null,barber:r.barber||null,method:r.method,time:r.time||null,items})});
const tot=sumOf(B.rows,r=>bfPrice(r)*r.n);
if(!force&&!confirm("تسجل "+list.length+" فاتورة بتاريخ "+B.day+" بإجمالي "+fm(tot)+"؟"))return;
C.bfBusy=1;try{const{data,error}=await sb.rpc("admin_backfill_invoices",{p_day:B.day,p_invoices:list,p_force:!!force});
if(error)return toast(error.code=="PGRST202"||/Could not find the function/i.test(error.message||"")?"شغّل ملف backfill_invoices.sql في Supabase الأول":error.message);
if(data&&data.needs_force){C.bfBusy=0;if(confirm("يوم "+data.day+" مقفول في الخزنة.\nلو سجلت فواتير فيه أرقام القفل هتبقى مختلفة عن اللي اتجرد.\nتكمّل؟"))return bfSave(true);return}
toast("اتسجل "+data.count+" فاتورة ✓ بإجمالي "+fm(data.total));C.bf=null;C.cd=B.day;V.cash()}finally{C.bfBusy=0}}


function bfCu(i,id,nm){C.bf.rows[i].cust=id;C.bf.rows[i].cn=nm;bfDraw()}
async function bfFind(i){const t=($("bfq"+i)?.value||"").trim().replace(/[%,()]/g,"");const el=$("bfl"+i);if(!el)return;if(!t){el.innerHTML="";return}
  const{data,error}=await sb.from("customers").select("id,name,phone").or("name.ilike.%"+t+"%,phone.ilike.%"+t+"%").order("name").limit(8);
  if(!$("bfl"+i))return;el.innerHTML=(error?`<p class="m">${esc(error.message)}</p>`:(data||[]).map(c=>`<button class="row" style="cursor:pointer;width:100%;text-align:right" onclick="bfCu(${i},${c.id},this.dataset.n)" data-n="${esc(c.name)}"><b>${esc(c.name)}</b><span class="m">${c.phone?`<span dir="ltr">${esc(c.phone)}</span>`:"من غير رقم"}</span></button>`).join(""))+`<button class="btn s g" style="margin-top:6px" onclick="bfNewCu(${i})">+ إضافة "${esc(t)}" كعميل جديد (اسم بس)</button>`}
async function bfNewCu(i){const n=($("bfq"+i)?.value||"").trim();if(!n)return;const{data:id,error}=await sb.rpc("add_customer",{p_name:n,p_phone:null});if(error)return toast(error.message);bfCu(i,id,n)}
