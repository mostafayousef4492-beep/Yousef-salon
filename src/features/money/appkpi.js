/* features/money/appkpi.js — مؤشرات نجاح تطبيق العملاء (أرقام حقيقية، قراءة فقط) */

const kpMissing=e=>e&&/app_kpis/i.test(e.message||"")&&/(does not exist|schema cache|Could not find)/i.test(e.message||"");
const kpP=(a,b)=>b>0?Math.round(a/b*100)+"%":"—";

V.kpi=async function(){
if(!(me.role=="owner"||me.role=="manager"||can("view_reports")))return put(`<h1>مؤشرات التطبيق</h1><p class="m">الشاشة دي للإدارة بس.</p>`);
const d=C.kpDays||30;C.kpDays=d;
const{data:r,error}=await sb.rpc("app_kpis",{p_days:d});
if(error)return put(`<h1>مؤشرات التطبيق</h1><p class="m">${kpMissing(error)?"الميزة لسه مش متفعّلة: شغّل ملف patch_app_kpis.sql في Supabase الأول.":esc(error.message)}</p>`);
const u=r.users,b=r.bookings,s=r.spend,l=r.loyalty,t=r.tryon,v=r.reviews,f=r.feedback,c=r.conversion;
const st=(a,x,sub)=>`<div class="box cc-stat"><div class="cc-l">${a}</div><div class="cc-n">${x}</div>${sub?`<div class="m">${sub}</div>`:""}</div>`;
const fin=b.done+b.no_show+b.cancelled,src={app:"التطبيق",public:"صفحة الحجز",admin:"الكاشير",fixed:"ميعاد ثابت",walk_in:"حضور مباشر"};
put(`<h1>مؤشرات التطبيق</h1>
<div class="chips" style="margin:6px 0"><span class="m">آخر</span>${[7,30,90,365].map(x=>`<button class="chip ${x==d?"sel":""}" onclick="C.kpDays=${x};V.kpi()">${x} يوم</button>`).join("")}</div>
<h2>المستخدمين</h2>
<div class="cc-grid">${st("مسجّلين بالتطبيق",u.total,"من "+u.all_customers+" عميل")}${st("جداد",u.new)}${st("نشطين",u.active,"حجزوا في الفترة")}${st("اتحوّلوا لعملاء فعليين",kpP(c.with_invoice,c.app_users),c.with_invoice+" من "+c.app_users+" عندهم فاتورة")}</div>
<h2>الحجوزات</h2>
<div class="cc-grid">${st("إجمالي",b.total)}${st("نسبة الإتمام",kpP(b.done,fin),b.done+" من "+fin+" منتهي")}${st("عدم الحضور",kpP(b.no_show,b.done+b.no_show),b.no_show+" حجز")}${st("الإلغاء",kpP(b.cancelled,fin),b.cancelled+" حجز")}</div>
<div class="m" style="margin-top:6px">المصدر: ${Object.entries(b.by_source||{}).map(([k,n])=>(src[k]||esc(k))+" "+n).join(" · ")||"—"}</div>
<div class="m">حجوزات التطبيق: تمّت ${b.app_done} · ماحضروش ${b.app_no_show} · اتلغت ${b.app_cancelled}</div>
<h2>الإنفاق والولاء</h2>
<div class="cc-grid">${st("متوسط فاتورة مستخدمي التطبيق",s.app_avg!=null?fm(s.app_avg):"—",s.app_n+" فاتورة")}${st("متوسط باقي العملاء",s.other_avg!=null?fm(s.other_avg):"—",s.other_n+" فاتورة")}${st("مكافآت اتطلبت",l.redeemed,l.used+" اتستخدمت · "+l.customers+" عميل")}${st("تجارب القصات",t.total,t.ok+" ناجحة · "+t.customers+" عميل")}</div>
<h2>الرضا والشكاوى</h2>
<div class="cc-grid">${st("التقييمات",v.n,v.avg!=null?"المتوسط "+v.avg+" / 5":"")}${st("تقييم الخدمة",v.avg_service??"—")}${st("تقييم المكان",v.avg_place??"—")}${st("الشكاوى",f.complaints,f.complaints_open+" لسه مفتوحة")}</div>
<div class="m" style="margin-top:6px">رسائل العملاء ${f.total} · اترد على ${f.replied}</div>
<p class="m" style="margin-top:12px">كل الأرقام محسوبة من بيانات الصالون الفعلية (حجوزات من ${r.data_since?new Date(r.data_since).toLocaleDateString("ar-EG"):"—"}) — مفيش أرقام تقديرية. الدقة بتزيد مع الوقت.</p>`)};

// تقرير الحجوزات والدور (تحت مؤشرات التطبيق)
const kpV0=V.kpi;
V.kpi=async function(){await kpV0();if(tab!="kpi")return;
try{const{data:r,error}=await sb.rpc("booking_report",{p_days:C.kpDays||30});if(error||!r||tab!="kpi")return;const el=$("app");if(!el)return;
const hs=Object.entries(r.by_hour||{}).map(([h,n])=>[+h,+n]).sort((a,b)=>a[0]-b[0]),mx=Math.max(1,...hs.map(x=>x[1]));
const WD=["الأحد","الاتنين","التلات","الأربع","الخميس","الجمعة","السبت"],wd=Object.entries(r.by_weekday||{}).map(([d,n])=>[+d,+n]).sort((a,b)=>b[1]-a[1]);
const peak=hs.slice().sort((a,b)=>b[1]-a[1]).slice(0,3).map(x=>x[0]+":00");
el.insertAdjacentHTML("beforeend",`<h2>الدور والانتظار</h2>
<div class="cc-grid"><div class="box cc-stat"><div class="cc-l">متوسط الانتظار</div><div class="cc-n">${r.wait.avg!=null?r.wait.avg+" د":"—"}</div><div class="m">من ${r.wait.n} زيارة · ${r.wait.over30} زيارة +30 د</div></div><div class="box cc-stat"><div class="cc-l">متوسط مدة الخدمة</div><div class="cc-n">${r.service_min!=null?r.service_min+" د":"—"}</div></div><div class="box cc-stat"><div class="cc-l">عدم الحضور</div><div class="cc-n">${r.no_show_rate!=null?r.no_show_rate+"%":"—"}</div></div></div>
${hs.length?`<div class="box" style="margin-top:8px"><b>أوقات الزحمة (وصول العملاء)</b><div class="m">الأكتر زحمة: ${peak.join("، ")}${wd.length?" · أكتر الأيام: "+wd.slice(0,2).map(x=>WD[x[0]]).join("، "):""}</div>${hs.map(([h,n])=>`<div style="display:flex;align-items:center;gap:6px;margin:2px 0"><span class="m" style="width:44px">${h}:00</span><div style="height:8px;border-radius:4px;background:var(--gold,#c9a24a);width:${Math.round(n/mx*100)}%"></div><span class="m">${n}</span></div>`).join("")}</div>`:""}
${(r.barbers||[]).length?`<h2>أداء الحلاقين</h2>`+r.barbers.map(x=>`<div class="row"><div><b>${esc(x.name)}</b><div class="m">${x.done} زيارة · ماحضروش ${x.no_show} · انتظار ${x.wait!=null?x.wait+" د":"—"} · خدمة ${x.svc!=null?x.svc+" د":"—"}</div></div></div>`).join(""):""}`)}catch(e){}};
