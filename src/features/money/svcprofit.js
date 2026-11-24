/* features/money/svcprofit.js — ربحية كل خدمة (قراءة بس): إيراد بعد الخصم − عمولة الصنايعي − المساعد − تكلفة الخامات الفعلية */

const svpMissing=e=>e&&/service_profit/i.test(e.message||"")&&/(does not exist|schema cache|Could not find)/i.test(e.message||"");
const SVP_RANGES=[["30","آخر 30 يوم"],["month","الشهر ده"],["prev","الشهر اللي فات"],["90","آخر 90 يوم"]];
const svpYmd=d=>d.toLocaleDateString("en-CA");
function svpRange(k){const t=new Date(),y=t.getFullYear(),m=t.getMonth();
  if(k=="month")return[svpYmd(new Date(y,m,1)),svpYmd(t)];
  if(k=="prev")return[svpYmd(new Date(y,m-1,1)),svpYmd(new Date(y,m,0))];
  const n=k=="90"?89:29,f=new Date(t);f.setDate(f.getDate()-n);return[svpYmd(f),svpYmd(t)]}
const svpCl={owner_draw:"سحب المالك",bank_deposit:"إيداع بنك",owner_inject:"ضخ من المالك",float:"فكة",other:"أخرى",none:"من غير تصنيف"};

V.svp=async function(){
  if(!(me.role=="owner"||me.role=="manager"))return put(`<h1>ربحية الخدمات</h1><p class="m">الشاشة دي للإدارة بس.</p>`);
  const k=C.svpK||"30";C.svpK=k;const[f,t]=svpRange(k);if((C.svpV||"svc")=="staff")return svpStaff(k,f,t);
  const[{data:r,error},{data:mv}]=await Promise.all([sb.rpc("service_profit",{p_from:f,p_to:t}),sb.from("cash_moves").select("kind,amount,category").gte("day",f).lte("day",t)]);
  if(error)return put(`<h1>ربحية الخدمات</h1><p class="m">${svpMissing(error)?"الميزة لسه مش متفعّلة: شغّل ملف patch_service_profit.sql في Supabase الأول.":esc(error.message)}</p>`);
  const L=r.rows||[],S=(a)=>L.reduce((s,x)=>s+(+x[a]||0),0),net=S("net"),prof=S("profit"),nr=L.filter(x=>!x.has_recipe).length,n=x=>fm(Math.round(+x||0));
  const mg=x=>+x.net>0?Math.round(+x.profit/+x.net*100):0;
  const owner={};(mv||[]).forEach(m=>{const c=m.category||"none",key=m.kind+":"+c;owner[key]=(owner[key]||0)+(+m.amount||0)});
  put(`<h1>ربحية الخدمات</h1>
${svpTabs()}<div class="chips" style="margin:6px 0">${SVP_RANGES.map(x=>`<button class="chip ${k==x[0]?"sel":""}" onclick="C.svpK='${x[0]}';V.svp()">${x[1]}</button>`).join("")}</div><div class="m">${f} ← ${t}</div>
<div class="cc-grid" style="margin-top:8px"><div class="box cc-stat"><div class="cc-l">إيراد الخدمات (بعد الخصم)</div><div class="cc-n">${n(net)}</div></div><div class="box cc-stat"><div class="cc-l">عمولات الصنايعية</div><div class="cc-n">${n(S("commission"))}</div></div><div class="box cc-stat"><div class="cc-l">المساعدين + الخامات</div><div class="cc-n">${n(S("assistant")+S("materials"))}</div></div><div class="box cc-stat"><div class="cc-l">الربح للصالون</div><div class="cc-n">${n(prof)}</div><div class="m">هامش ${net>0?Math.round(prof/net*100):0}%</div></div></div>
${nr?`<div class="box" style="border:1px solid var(--gold,#c9a24d);margin-top:8px"><b>${nr} خدمة من ${L.length} مالهاش وصفة خامات</b><div class="m">تكلفة الخامات ليها صفر دلوقتي، فالربح بتاعها مرتفع عن الحقيقة. اربطها بخاماتها من شاشة الخدمات والمخزون.</div></div>`:""}
<h2>كل خدمة (الأعلى ربحاً أول)</h2>
${L.length?L.map(x=>{const m=mg(x),low=m<35;return `<div class="row"><div><b>${esc(x.name)}</b> ${x.category?`<span class="tag">${esc(x.category)}</span>`:""}${x.has_recipe?"":` <span class="tag">من غير وصفة خامات</span>`}<div class="m">${x.n} مرة · سعرها ${n(x.price)} · متوسط ربح المرة ${n(+x.profit/(+x.n||1))}</div><div class="m">إيراد ${n(x.net)} − عمولة ${n(x.commission)}${+x.assistant?" − مساعد "+n(x.assistant):""}${+x.materials?" − خامات "+n(x.materials):""}</div></div><div style="text-align:left"><b>${n(x.profit)}</b><div class="m" style="color:${low?"var(--red)":"var(--ok)"}">${m}%${low?" · راجع السعر":""}</div></div></div>`}).join(""):`<p class="m">مفيش خدمات اتباعت في الفترة دي.</p>`}
<h2>حركات الدرج في نفس الفترة</h2><div class="m" style="margin-bottom:4px">دي مش من إيراد ولا مصروفات الصالون.</div>
${Object.keys(owner).length?Object.entries(owner).map(([k2,v])=>{const[kd,c]=k2.split(":");return `<div class="row"><div>${kd=="withdraw"?"سحب":"إضافة"} · ${svpCl[c]||c}</div><b>${n(v)}</b></div>`}).join(""):`<p class="m">مفيش حركات.</p>`}
<p class="m" style="margin-top:12px">طريقة الحساب: الخصم بيتوزّع على بنود الفاتورة، والعمولة بنسبة الحلاق (أو نسبة الفاتورة الخاصة) بعد خصم حصة المساعد والخامات الاختيارية، والخامات من حركات الاستهلاك الفعلية بتكلفة الخامة الحالية. الأرقام تقديرية ومبتغيّرش أي حاجة.</p>`)};

// تبويب: الخدمات / الحلاقين
const svpTabs=()=>`<div class="chips" style="margin-bottom:6px">${[["svc","الخدمات"],["staff","الحلاقين"]].map(x=>`<button class="chip ${(C.svpV||"svc")==x[0]?"sel":""}" onclick="C.svpV='${x[0]}';V.svp()">${x[1]}</button>`).join("")}</div>`;

// أداء الحلاقين: عدد العملاء والإيراد ومتوسط الفاتورة والخصومات والعمولة التقديرية
async function svpStaff(k,f,t){
  const{data:r,error}=await sb.rpc("staff_performance",{p_from:f,p_to:t});
  if(error)return put(`<h1>أداء الحلاقين</h1>${svpTabs()}<p class="m">${svpMissing({message:error.message.replace("staff_performance","service_profit")})?"الميزة لسه مش متفعّلة: شغّل ملف patch_staff_performance.sql في Supabase الأول.":esc(error.message)}</p>`);
  const L=r.rows||[],n=x=>fm(Math.round(+x||0)),S=a=>L.reduce((s,x)=>s+(+x[a]||0),0);
  put(`<h1>أداء الحلاقين</h1>${svpTabs()}
<div class="chips" style="margin:6px 0">${SVP_RANGES.map(x=>`<button class="chip ${k==x[0]?"sel":""}" onclick="C.svpK='${x[0]}';V.svp()">${x[1]}</button>`).join("")}</div><div class="m">${f} ← ${t}</div>
<div class="cc-grid" style="margin-top:8px"><div class="box cc-stat"><div class="cc-l">الإيراد المحصّل</div><div class="cc-n">${n(S("collected"))}</div><div class="m">${S("invoices")} فاتورة</div></div><div class="box cc-stat"><div class="cc-l">الخصومات</div><div class="cc-n">${n(S("discounts"))}</div><div class="m">${S("gross")>0?(S("discounts")/S("gross")*100).toFixed(1):0}% من المبيعات</div></div></div>
<h2>كل حلاق (الأعلى إيراداً أول)</h2>
${L.length?L.map(x=>`<div class="row"><div><b>${esc(x.name)}</b><div class="m">${x.invoices} فاتورة · ${x.customers} عميل مسجّل · متوسط الفاتورة ${n(x.avg_invoice)}</div><div class="m">خصومات ${n(x.discounts)} (${x.discount_pct}%) · عمولة تقديرية ${n(x.commission)}</div></div><div style="text-align:left"><b>${n(x.collected)}</b></div></div>`).join(""):`<p class="m">مفيش فواتير في الفترة دي.</p>`}
<p class="m" style="margin-top:12px">الفواتير اللي ملهاش حلاق مش داخلة هنا. العمولة تقديرية: (إجمالي الفاتورة − حصة المساعد − الخامات الاختيارية) × نسبة الحلاق. الأرقام مبتغيّرش أي حاجة.</p>`)}
