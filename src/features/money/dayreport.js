/* features/money/dayreport.js — تقرير اليوم + التنبيهات الذكية (أرقام حقيقية من قاعدة البيانات، قراءة فقط) */

const dyMissing=e=>e&&/day_report/i.test(e.message||"")&&/(does not exist|schema cache|Could not find)/i.test(e.message||"");
const DY_LV={high:["🔴","var(--red)"],warn:["🟠","var(--gold,#c9a24d)"],info:["🔵","var(--mut,#888)"]};

V.day=async function(){
if(!(me.role=="owner"||me.role=="manager"))return put(`<h1>تقرير اليوم</h1><p class="m">الشاشة دي للإدارة بس.</p>`);
const d=C.dyDay||new Date().toLocaleDateString("en-CA");C.dyDay=d;
const{data:r,error}=await sb.rpc("day_report",{p_day:d});
if(error)return put(`<h1>تقرير اليوم</h1><p class="m">${dyMissing(error)?"التقرير لسه مش متفعّل: شغّل ملف patch_day_report.sql في Supabase الأول.":esc(error.message)}</p>`);
const f=r.figures||{},s=r.sales||{},v=r.voids||{},a=r.attendance||{},al=r.alerts||[],low=[...(r.low_stock?.materials||[]),...(r.low_stock?.products||[])];
const h=new Date().getHours(),stage=r.closed?"تقرير الإغلاق":h<14?"تقرير بداية اليوم":h<20?"تقرير منتصف اليوم":"تقرير آخر اليوم";
const n=x=>fm(+x||0),st=(l,x,sub)=>`<div class="box cc-stat"><div class="cc-l">${l}</div><div class="cc-n">${x}</div>${sub?`<div class="m">${sub}</div>`:""}</div>`;
put(`<h1>${stage}</h1>
<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin:6px 0"><input type="date" value="${d}" onchange="C.dyDay=this.value;V.day()" style="margin:0"><button class="btn s g" onclick="V.day()">تحديث</button>${r.closed?`<span class="tag st-done">اليوم مقفول</span>`:`<span class="tag">لسه مفتوح</span>`}</div>
<h2>تنبيهات (${al.length})</h2>
${al.length?al.map(x=>{const l=DY_LV[x.level]||DY_LV.info;return `<div class="row" style="border-inline-start:4px solid ${l[1]}"><div>${l[0]} ${esc(x.text)}</div></div>`}).join(""):`<p class="m">مفيش تنبيهات ✓ — الأرقام سليمة.</p>`}
<h2>المبيعات</h2>
<div class="cc-grid">${st("الإيراد",n(s.total),(s.invoices||0)+" فاتورة")}${st("الخصومات",n(s.discount),(s.discount_pct||0)+"% من المبيعات"+(+s.company_discount?" · شركات "+n(s.company_discount):""))}${st("مصروفات",n(r.expenses))}${st("آجل",n(s.unpaid))}</div>
<div class="m" style="margin-top:6px">كاش ${n(f.cash_sales)} · كارت ${n(f.card_sales)} · محفظة ${n(f.wallet_sales)}${f.opening!=null?" · رصيد أول اليوم "+n(f.opening):""}</div>
<h2>الرقابة</h2>
<div class="row"><div>فواتير ملغية</div><b>${v.count||0}${+v.total?" · "+n(v.total):""}</b></div>
<div class="row"><div>طلبات موافقة مستنية</div><b>${r.pending_approvals||0}</b>${(r.pending_approvals||0)?`<button class="btn s" onclick="go('apr')">افتح</button>`:""}</div>
<div class="row"><div>فواتير مفتوحة من +3 ساعات</div><b>${r.open_stale||0}</b></div>
${r.closing?`<div class="row"><div>فرق الجرد</div><b>كاش ${n(r.closing.diff_cash)} · كارت ${n(r.closing.diff_card)} · محفظة ${n(r.closing.diff_wallet)}</b></div>`:""}
<h2>الفريق</h2>
<div class="row"><div>حاضرين</div><b>${a.present||0}</b></div>
<div class="row"><div>متأخرين</div><b>${a.late||0}${a.late_min?" · "+a.late_min+" دقيقة":""}</b></div>
${(a.absent||[]).length?`<div class="row"><div>لسه ماسجلوش حضور</div><b>${a.absent.map(esc).join("، ")}</b></div>`:""}
${low.length?`<h2>مخزون على الحد الأدنى</h2><p class="m">${low.map(esc).join("، ")}</p>`:""}
<p class="m" style="margin-top:12px">الأرقام دي بتتحسب من بيانات الصالون الفعلية ومبتغيّرش أي حاجة. القرار ليك.</p>`)};
