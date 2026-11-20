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
