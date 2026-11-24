/* ui/bundles-ui.js — الباقات في شاشات الحجز (تطبيق العميل، /book، التابلت)
   الحالة المشتركة: b = {s:[ids الخدمات], bd: id الباقة المختارة أو null}. لو الباقة اتقفلت أو الجدول مش موجود، القايمة بتبقى فاضية والحجز عادي. */
const BN={L:[]};

BN.SV=[];
BN.load=async function(client){try{const{data,error}=await client.rpc("bundles_list");BN.L=!error&&Array.isArray(data)?data:[]}catch(e){BN.L=[]}
  try{const{data}=await client.from("services").select("id,name,price,group_name,active").eq("active",true);BN.SV=data||[]}catch(e){BN.SV=[]}};
BN.get=id=>BN.L.find(x=>x.id==id);
BN.ids=bd=>(bd.services||[]).map(x=>x.id);                 // الخدمات الثابتة
BN.slots=bd=>bd.slots||[];                                 // خانات الاختيار [{group, options:[{id,name,price}]}]
BN.optIds=bd=>BN.slots(bd).flatMap(s=>(s.options||[]).map(o=>o.id));
BN.all=bd=>[...BN.ids(bd),...BN.optIds(bd)];
// الباقة مكتملة على قايمة خدمات: كل الثابتة + اختيار واحد على الأقل من كل خانة
BN.pr=id=>{const s=BN.SV.find(x=>x.id==id);if(s)return+s.price;for(const bd of BN.L){const f=(bd.services||[]).find(x=>x.id==id);if(f)return+f.price}return null};
// تبديل جوه الباقة: خدمة ثابتة ناقصة + خدمة تانية بنفس السعر بالظبط مش من الباقة ولا من خاناتها = بديل لها (نفس ترتيب السيرفر bundle_eff)
BN.swaps=(bd,sel)=>{const fx=BN.ids(bd),so=BN.optIds(bd),gr=BN.slots(bd).map(s=>s.group),used=new Set(),out={};
  const ext=sel.filter(i=>!fx.includes(i)&&!so.includes(i)).map(i=>BN.SV.find(s=>s.id==i)).filter(s=>s&&!(s.group_name&&gr.includes(s.group_name))).sort((a,b)=>a.id-b.id);
  fx.filter(i=>!sel.includes(i)).sort((a,b)=>a-b).forEach(n=>{const p=BN.pr(n),e=ext.find(s=>!used.has(s.id)&&+s.price===p);if(e){used.add(e.id);out[n]=e.id}});return out};
BN.swapOpts=(bd,sel,n)=>{const p=BN.pr(n),gr=BN.slots(bd).map(s=>s.group),al=BN.all(bd);
  return p==null?[]:BN.SV.filter(s=>s.id!=n&&+s.price===p&&!al.includes(s.id)&&!sel.includes(s.id)&&!(s.group_name&&gr.includes(s.group_name)))};
BN.swapTo=function(n,v){const b=BN.cur;if(!b||!b.bd||!v)return;const bd=BN.get(b.bd);if(!bd)return;const cur=BN.swaps(bd,b.s)[n]||n,nw=+v;
  let s=b.s.filter(x=>x!=cur);
  if(nw==n){if(!s.includes(n))s.push(n)}else if(!s.includes(nw))s=SG.tog(s,nw,BN.SV);
  b.s=s;BN.sync(b);if(BN.rd&&typeof window[BN.rd]=="function")window[BN.rd]()};
BN.ok=(bd,sel)=>{const sw=BN.swaps(bd,sel);return BN.ids(bd).every(i=>sel.includes(i)||sw[i])&&BN.slots(bd).every(s=>(s.options||[]).some(o=>sel.includes(o.id)))};
// الاختيار الافتراضي لكل خانة = أرخص خيار (اللي الخصم محسوب عليه)
BN.baseOpt=s=>(s.options||[]).find(o=>o.id==s.base)||(s.options||[])[0]||null;   // الخيار اللي الباقة اتسعّرت عليه
BN.defOpt=s=>(BN.baseOpt(s)||{}).id;
// بيضيف خدمات الباقة (الثابتة + خيار لكل خانة لو مفيش) على قايمة sel
BN.fill=(bd,sel)=>{const o=[...new Set([...sel,...BN.ids(bd)])];BN.slots(bd).forEach(s=>{if(!(s.options||[]).some(x=>o.includes(x.id))&&BN.defOpt(s))o.push(BN.defOpt(s))});return o};
// بيشيل خدمات الباقة (الثابتة + أي خيار من خاناتها) من قايمة sel
BN.strip=(bd,sel)=>{const sw=Object.values(BN.swaps(bd,sel));return sel.filter(x=>!BN.all(bd).includes(x)&&!sw.includes(x))};
BN.names=bd=>[...(bd.services||[]).map(s=>esc(s.name)),...BN.slots(bd).map(s=>esc(s.group)+" (اختيار)")].join(" + ");

// اختيار/إلغاء باقة: بتنوّر خدماتها (بتتضاف لـ b.s) وبتشيل خدمات الباقة اللي قبلها
BN.pick=function(b,id){
  const old=b.bd&&BN.get(b.bd);
  if(b.bd==id){b.s=BN.strip(old,b.s);b.bd=null;return}
  if(old)b.s=BN.strip(old,b.s);
  const nw=BN.get(id);if(!nw)return;
  b.s=BN.fill(nw,b.s);b.bd=id};

// بعد أي تعديل في الخدمات: لو خدمات الباقة ما بقتش كلها موجودة، الباقة بتتشال (الخدمات الباقية بتتحسب بسعرها)
BN.sync=function(b){if(!b.bd)return;const bd=BN.get(b.bd);if(!bd||!BN.ok(bd,b.s))b.bd=null};

BN.calc=function(b,SV){const sv=SV.filter(x=>b.s.includes(x.id)),full=sv.reduce((a,x)=>a+(+x.price||0),0),bd=b.bd&&BN.get(b.bd),saving=bd?+bd.saving||0:0;
  return{full,saving,total:Math.max(full-saving,0),dur:sv.reduce((a,x)=>a+(+x.duration_min||0),0),bd}};

BN.star=(b,id)=>b.bd&&BN.get(b.bd)&&(BN.all(BN.get(b.bd)).includes(id)||Object.values(BN.swaps(BN.get(b.bd),b.s)).includes(id))?"★ ":"";

// كروت الباقات (fn = اسم دالة الاختيار في الصفحة) + ملخص الحساب لما تكون باقة مختارة
BN.html=function(b,fn,fm){
  if(!BN.L.length)return"";
  const sel="border-color:var(--gold,#c9a24a);box-shadow:0 0 0 2px var(--gold,#c9a24a) inset;";
  return`<h2>الباقات <span class="m">(أوفر من الخدمات لوحدها)</span></h2>`+BN.L.map(x=>`<button class="row" style="cursor:pointer;width:100%;text-align:right;${b.bd==x.id?sel:""}" onclick="${fn}(${x.id})"><div><b>${esc(x.name)}</b><div class="m">${BN.names(x)}</div>${x.description?`<div class="m">${esc(x.description)}</div>`:""}</div><div style="text-align:left"><s class="m">${BN.slots(x).length?"من ":""}${fm(x.full)}</s><br><b>${BN.slots(x).length?"من ":""}${fm(x.price)}</b><br><span class="tag">وفّر ${fm(x.saving)}</span></div></button>`).join("")};

BN.swapHtml=function(b,bd){const sw=BN.swaps(bd,b.s),nm=id=>{const s=BN.SV.find(x=>x.id==id);return s?s.name:""};
  const rows=(bd.services||[]).map(f=>{const o=BN.swapOpts(bd,b.s,f.id),cur=sw[f.id];if(!o.length&&!cur)return"";
    return`<div class="m" style="padding-top:4px">${cur?`${esc(f.name)} ← بدلتها بـ <b>${esc(nm(cur))}</b>`:esc(f.name)} <select aria-label="بدّل ${esc(f.name)}" onchange="BN.swapTo(${f.id},this.value)" style="width:auto;display:inline-block"><option value="">بدّل بنفس السعر…</option>${cur?`<option value="${f.id}">رجّع «${esc(f.name)}»</option>`:""}${o.map(s=>`<option value="${s.id}">${esc(s.name)}</option>`).join("")}</select></div>`}).join("");
  return rows?`<div style="margin-top:6px"><div class="m"><b>تبديل جوه الباقة</b> (بنفس السعر بالظبط، والباقة بتفضل بسعرها)</div>${rows}</div>`:""};
BN.summary=function(b,SV,fm,rd){const c=BN.calc(b,SV);if(!c.bd)return"";BN.cur=b;BN.rd=rd||null;
  return`<div class="box" style="margin:10px 0;border-color:var(--gold,#c9a24a)"><b>🎁 ${esc(c.bd.name)}</b>
${BN.slots(c.bd).map(s=>{const o=(s.options||[]).find(x=>b.s.includes(x.id)),base=BN.baseOpt(s),d=o&&base?+o.price-+base.price:0;return`<div class="m" style="padding-top:4px">${esc(s.group)}: <b>${o?esc(o.name):"اختار نوع من الخدمات تحت"}</b>${d>0?` · زيادة ${fm(d)} عن «${esc(base.name)}»`:d<0?` · أرخص ${fm(-d)} من «${esc(base.name)}»`:""}</div>`}).join("")}
${BN.swapHtml(b,c.bd)}<div style="display:flex;justify-content:space-between;padding-top:6px"><span>الخدمات دي كلها لوحدها</span><span>${fm(c.full)}</span></div>
<div style="display:flex;justify-content:space-between"><span>خصم الباقة</span><b style="color:var(--ok,#2ea66b)">− ${fm(c.saving)}</b></div>
<div style="display:flex;justify-content:space-between;border-top:1px solid var(--line,#2a2f3a);margin-top:6px;padding-top:6px"><b>الإجمالي بعد الباقة</b><b>${fm(c.total)}</b></div></div>`};

// بعد ما التذكرة تتحجز: نربط الباقة بيها (السيرفر بيتأكد إن الخدمات مطابقة). phone للزائر من غير حساب.
BN.attach=async function(client,b,ticketId,phone){if(!b.bd||!ticketId)return true;
  try{const{error}=await client.rpc("set_ticket_bundle",{p_id:ticketId,p_bundle:b.bd,p_phone:phone||null});return!error}catch(e){return false}};

/* ===== خيارات الخدمة (SG): خدمة ليها اختيارات كل واحد بسعره (مثلًا قص الشعر: كلاسيك / تدريج)
   كل اختيار خدمة حقيقية في جدول services ليها group_name (اسم المجموعة) و option_label (اسم الاختيار)؛
   باقي النظام (الحجز، الكاشير، الفواتير، التقارير) بيشوف الاختيار كخدمة عادية. العميل بيختار اختيار واحد بس من المجموعة. */
const SG={};
// اختيار/إلغاء خدمة: لو من مجموعة، بيشيل أي اختيار تاني من نفس المجموعة
SG.tog=function(sel,id,SV){if(sel.includes(id))return sel.filter(x=>x!=id);
  const s=SV.find(x=>x.id==id),g=s&&s.group_name;
  return[...(g?sel.filter(x=>{const o=SV.find(y=>y.id==x);return!(o&&o.group_name==g)}):sel),id]};
// item(x,isSel,short): بيرجّع زرار الخدمة؛ short=true للاختيارات جوه المجموعة (اسم الاختيار بس)
SG.secOrder=["الشعر","الدقن","الصبغات","التصفيف","العناية","إضافات"];SG.secIcon={"الشعر":"✂️","الدقن":"🧔","الصبغات":"🎨","التصفيف":"💇","العناية":"🧖","إضافات":"➕"};
SG.render=function(SV,sel,item){const seen={},out=[];let loose=[];
  const rk=c=>{const i=SG.secOrder.indexOf(c);return i<0?99:i};
  const cats=[...new Set(SV.map(x=>x.category||""))];
  if(cats.length>1){SV=SV.map((x,i)=>[x,i]).sort((a,b)=>rk(a[0].category)-rk(b[0].category)||String(a[0].category||"").localeCompare(String(b[0].category||""),"ar")||a[1]-b[1]).map(a=>a[0])}
  let lastC=null;
  const flush=()=>{if(loose.length){out.push(`<div class="chips">${loose.join("")}</div>`);loose=[]}};
  SV.forEach(x=>{const g=x.group_name;
    if(cats.length>1&&x.category&&x.category!==lastC&&!(g&&seen[g])){lastC=x.category;flush();out.push(`<div class="m" style="margin:12px 0 4px;width:100%"><b>${SG.secIcon[x.category]||""} ${esc(x.category)}</b></div>`)}
    if(!g){loose.push(item(x,sel.includes(x.id),false));return}
    if(seen[g])return;seen[g]=1;flush();
    const opts=SV.filter(y=>y.group_name==g),pick=opts.some(y=>sel.includes(y.id));
    out.push(`<div style="border:1px solid ${pick?"var(--gold,#c9a24a)":"var(--line,#2a2f3a)"};border-radius:14px;padding:10px;margin:8px 0;width:100%;box-sizing:border-box"><div style="margin-bottom:8px"><b>${esc(g)}</b> <span class="m">(اختار واحد)</span></div><div class="chips">${opts.map(y=>item(y,sel.includes(y.id),true)).join("")}</div></div>`)});
  flush();return out.join("")};
SG.label=x=>x.option_label||x.name;
