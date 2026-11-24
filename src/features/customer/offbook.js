/* customer/offbook.js — حجز دور وإنت من غير إنترنت: الطلب بيتحفظ على موبايلك ويتبعت لما النت يرجع.
   الحجز مش مؤكد لحد ما يتبعت. بالباقات والخارج المحل والحجز لتابع لازم نت. السيرفر بيمنع التكرار بمعرّف عملية (patch_book_offline.sql). */
(()=>{if(window.SALON_MODE!=="customer")return;
const QK="salon_offbk_q",RK="salon_offbk_ref";
const rd=k=>{try{return JSON.parse(localStorage.getItem(k)||"null")}catch(e){return null}};
const wr=(k,v)=>{try{localStorage.setItem(k,JSON.stringify(v));return true}catch(e){return false}};
const Q=()=>(rd(QK)||[]).filter(r=>me&&r.user_id===me.id);
const isNet=e=>!e||/fetch|network|load failed|timeout/i.test(String(e.message||e))&&!e.code;
function save(rows){const others=(rd(QK)||[]).filter(r=>!me||r.user_id!==me.id);return wr(QK,others.concat(rows))}
// 1) شاشة الحجز: لما النت موجود بنحفظ الخدمات للمرة اللي بعدها، ولما مفيش نت بنفتح من المحفوظ
const v0=V.book;
V.book=async function(){
  if(navigator.onLine){const r=await v0.apply(this,arguments);try{if(C.sv&&C.sv.length)wr(RK,{sv:C.sv,cfg:C.cfg,at:Date.now()})}catch(e){}return r}
  const ref=rd(RK);if(!ref||!ref.sv||!ref.sv.length||!(C.cfg&&C.cfg.days_ahead)&&!(ref.cfg&&ref.cfg.days_ahead))return put(`<h1>احجز دورك</h1><p class="m">مفيش إنترنت. افتح الحجز مرة واحدة والنت شغّال علشان نحفظ الخدمات، وبعدها تقدر تحجز من غير نت.</p>`);
  C.cfg=Object.assign({},ref.cfg||{},C.cfg||{});C.sv=ref.sv;C.b=C.b||{s:[],bd:null,barber:null,day:0,period:null};C.b.barber=null;drawBk();
  setTimeout(()=>{const a=$("app");if(a&&!$("offbk_note")){const n=document.createElement("div");n.id="offbk_note";n.className="box";n.style.cssText="border:1px solid var(--gold,#c9a35a);margin:8px 0";n.innerHTML="📵 مفيش إنترنت. هنحفظ حجزك على موبايلك ونبعته أول ما النت يرجع. الحجز <b>مش مؤكد</b> لحد ما يتبعت، واختيار الحلاق مش متاح دلوقتي.";a.prepend(n)}},50)};
// 2) اختيار الحلاق: أوفلاين = أي حلاق
const lb0=window.loadBarbers;
window.loadBarbers=async function(){if(navigator.onLine)return lb0.apply(this,arguments);if(C.b)C.b.barber=null;const e=$("bl");if(e)e.innerHTML=`<h2>الحلاق</h2><p class="m">أي حلاق متاح (مش بنختار وإنت من غير نت)</p>`;const bt=$("cbtn");if(bt)bt.disabled=!(C.b&&C.b.s.length&&C.b.period)};
// 3) تأكيد الحجز
const bn0=window.bookNow;
window.bookNow=async function(){
  if(navigator.onLine)return bn0.apply(this,arguments);
  const b=C.b;if(!b||!b.s.length)return toast("اختار خدمة واحدة على الأقل");if(!b.period)return toast("اختار الفترة");
  if(b.bd||b.out||b.for||b.urgent)return toast("الباقات والخارج المحل والحجز لتابع بيحتاجوا إنترنت");
  const d=bkDays()[b.day];if(!d)return;if(Q().length>=2)return toast("عندك حجزين مستنيين النت. استنى لحد ما يتبعتوا");
  if(Q().some(r=>r.day===d.iso))return toast("عندك حجز مستني النت لنفس اليوم");
  const row={request_id:(crypto.randomUUID?crypto.randomUUID():"xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g,c=>{const r=Math.random()*16|0;return(c=="x"?r:r&3|8).toString(16)})),user_id:me.id,day:d.iso,day_label:d.l,period:b.period,services:b.s.slice(),created_at:new Date().toISOString()};
  if(!save(Q().concat([row])))return toast("مقدرناش نحفظ الحجز على الموبايل");
  C.b=null;toast("اتحفظ الحجز على موبايلك 📵 هيتبعت أول ما النت يرجع");try{go("hm")}catch(e){}};
// 4) الإرسال لما النت يرجع
let busy=false;
async function sync(){if(busy||!navigator.onLine||!me||!me.id)return;const rows=Q();if(!rows.length)return;busy=true;
  try{for(const r of rows){const{data,error}=await sb.rpc("book_ticket_offline",{p_request_id:r.request_id,p_barber:null,p_day:r.day,p_period:r.period,p_services:r.services});
    if(error){if(isNet(error))break;save(Q().filter(x=>x.request_id!==r.request_id));toast("الحجز اللي حفظته أوفلاين ماتأكدش ("+(r.day_label||r.day)+"): "+(error.message||"حاول تحجز تاني"));continue}
    save(Q().filter(x=>x.request_id!==r.request_id));toast("اتأكد حجزك ✓ ("+(r.day_label||r.day)+") شوف رقم دورك");try{if(typeof tab!="undefined"&&(tab=="hm"||tab=="queue"))go(tab)}catch(e){}}}
  catch(e){}finally{busy=false}}
addEventListener("online",()=>setTimeout(sync,1500));
// 5) بانر على الرئيسية + محاولة إرسال
const h0=V.hm;if(h0)V.hm=async function(){await h0.apply(this,arguments);sync();try{const L=Q();const sh=document.querySelector("#app .hm-shell");if(L.length&&sh&&!$("hmoffbk")){const el=document.createElement("div");el.id="hmoffbk";el.className="box";el.style.cssText="margin-top:10px;border:1px solid var(--gold,#c9a35a)";el.innerHTML=`📵 <b>عندك ${L.length} حجز مستني النت</b><div class="m">${L.map(r=>esc(r.day_label||r.day)).join(" · ")} — هيتبعت لوحده، وهتعرف لو الدور اتملى.</div>`;sh.prepend(el)}}catch(e){}};
})();
