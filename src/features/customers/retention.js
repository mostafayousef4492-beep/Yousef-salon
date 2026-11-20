/* features/customers/retention.js — رجوع العملاء: مين بقاله فترة ماجاش + معدل الرجوع + رسالة استعادة بزرار واتساب */

const rtMissing=e=>e&&/retention_report|winback_mark/i.test(e.message||"")&&/(does not exist|schema cache|Could not find)/i.test(e.message||"");
const rtPct=(a,b)=>b>0?Math.round(a/b*100)+"%":"—";
const rtWa=p=>{let d=String(p||"").replace(/\D/g,"");if(d.startsWith("00"))d=d.slice(2);else if(d.startsWith("0"))d="2"+d;return d};
const rtMsg=(x)=>"أهلاً "+(x.name||"")+" 👋\nوحشتنا في صالون أبو يوسف ✂️ بقالك "+x.days_away+" يوم ماجيتش."+(x.top_service?"\nجاهزين لـ«"+x.top_service+"» بالشكل اللي تحبه.":"")+"\nاحجز دورك من التطبيق: "+location.origin+"/";

V.ret=async function(){
if(!(me.role=="owner"||me.role=="manager"||can("manage_appts")))return put(`<h1>رجوع العملاء</h1><p class="m">الشاشة دي للإدارة بس.</p>`);
const d=C.rtDays||30;C.rtDays=d;
const{data:r,error}=await sb.rpc("retention_report",{p_days:d});
if(error)return put(`<h1>رجوع العملاء</h1><p class="m">${rtMissing(error)?"الميزة لسه مش متفعّلة: شغّل ملف patch_retention.sql في Supabase الأول.":esc(error.message)}</p>`);
C.rt=r;const st=(l,v,s)=>`<div class="box cc-stat"><div class="cc-l">${l}</div><div class="cc-n">${v}</div>${s?`<div class="m">${s}</div>`:""}</div>`;
const L=r.list||[],nv=r.next_visit||{},wb=r.winback||{};
put(`<h1>رجوع العملاء</h1>
<div class="chips" style="align-items:center;margin:6px 0"><span class="m">بقالهم أكتر من</span>${[30,45,60,90].map(x=>`<button class="chip ${x==d?"sel":""}" onclick="C.rtDays=${x};V.ret()">${x} يوم</button>`).join("")}</div>
<div class="cc-grid">${st("عملاء بزيارات",r.customers)}${st("نشطين",r.active,"زاروا آخر "+d+" يوم")}${st("متوقفين",r.lapsed,r.lapsed_60+" منهم +60 يوم")}${st("متوسط الفترة بين الزيارات",(r.median_gap_days??"—")+" يوم","المتوسط "+(r.avg_gap_days??"—"))}</div>
<div class="box" style="margin-top:8px"><b>معدل الرجوع</b><div class="m">رجعوا خلال 30 يوم من أول زيارة: <b>${rtPct(r.return30.returned,r.return30.base)}</b> (${r.return30.returned} من ${r.return30.base}) · خلال 60 يوم: <b>${rtPct(r.return60.returned,r.return60.base)}</b> (${r.return60.returned} من ${r.return60.base})</div>
<div class="m">رسائل الاستعادة (آخر 90 يوم): اتبعت لـ ${wb.sent||0} · رجع منهم خلال 30 يوم ${wb.returned||0} (${rtPct(wb.returned||0,wb.sent||0)})</div>
<div class="m">تذكير الزيارة القادمة: اتطلب ${nv.created||0} · اتبعت ${nv.sent||0} · رجعوا ${nv.converted||0}</div>
<div class="m">البيانات المحسوبة من ${r.data_since?new Date(r.data_since).toLocaleDateString("ar-EG"):"—"} — الدقة بتزيد مع الوقت.</div></div>
<h2>المتوقفين (${L.length}${r.lapsed>L.length?" من "+r.lapsed:""})</h2>
${L.length?L.map((x,i)=>{const cd=x.last_contact?Math.floor((Date.now()-new Date(x.last_contact))/864e5):null,nobtn=!x.marketing_ok;
return `<div class="row"><div><b>${esc(x.name||"")}</b> <span class="m" dir="ltr">${esc(x.phone||"")}</span><div class="m">آخر زيارة من ${x.days_away} يوم · ${x.n} زيارة${x.top_service?" · بيحب «"+esc(x.top_service)+"»":""}</div>${cd!=null?`<div class="m">اتبعتله من ${cd} يوم</div>`:""}${x.has_reminder?`<div class="m">طالب تذكير</div>`:""}</div>
<div>${nobtn?`<span class="m">قفل العروض</span>`:`<button class="btn s" onclick="rtSend(${i})">📲 واتساب</button>`}</div></div>`}).join(""):`<p class="m">مفيش عملاء متوقفين بالمدة دي ✓</p>`}
<p class="m" style="margin-top:12px">الزرار بيفتح واتساب برسالة جاهزة ومحدش بيتبعتله تلقائي. اللي قفل العروض من التطبيق مش بيظهرله زرار.</p>`)};

async function rtSend(i){const x=((C.rt||{}).list||[])[i];if(!x)return;
if(x.last_contact&&Date.now()-new Date(x.last_contact)<14*864e5&&!await askConfirm("اتبعتله رسالة من أقل من 14 يوم. تبعت تاني؟"))return;
if(!/^\d{11,15}$/.test(rtWa(x.phone)))return toast("رقم العميل ناقص أو غلط");
const m=rtMsg(x);window.open("https://wa.me/"+rtWa(x.phone)+"?text="+encodeURIComponent(m),"_blank","noopener");
const{error}=await sb.rpc("winback_mark",{p_customer:x.id,p_days:x.days_away});error?toast("اتفتح واتساب بس التسجيل فشل: "+error.message):(toast("اتسجّل إنك بعتله ✓"),V.ret())}
