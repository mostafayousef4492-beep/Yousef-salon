/* features/customer/nextvisit.js — تذكير الزيارة القادمة + تحكم العميل في الرسائل التسويقية (حجوزاتي / حسابي) */

const nvMine0=V.mine;
V.mine=async()=>{await nvMine0();if(tab!="mine")return;
try{const{data,error}=await sb.rpc("my_next_visit");if(error||!data||tab!="mine")return;const el=$("app");if(!el)return;
const d=[...new Set([14,21,30,45,+data.suggested])].sort((a,b)=>a-b);
const body=data.pending?`<p class="m">هنفكّرك يوم <b>${esc(data.pending.on)}</b> إن شاء الله ✂️</p><button class="btn s g" onclick="nvCancel()">إلغاء التذكير</button>`
:`<p class="m">اختار بعد كام يوم تحب نفكّرك بحلاقتك الجاية (غالبًا بتحلق كل ${+data.suggested} يوم تقريبًا).</p><div class="chips">${d.map(x=>`<button class="chip ${x==+data.suggested?"sel":""}" onclick="nvSet(${x})">بعد ${x} يوم${x==+data.suggested?" ⭐":""}</button>`).join("")}</div>`;
el.insertAdjacentHTML("afterbegin",`<div class="box" id="nvBox" style="margin-bottom:10px"><b>🔔 ذكّرني بميعادي الجاي</b>${body}</div>`)}catch(e){}};

async function nvSet(days){const{data,error}=await sb.rpc("my_next_visit_set",{p_days:days});error?toast(error.message):(toast("تمام، هنفكّرك يوم "+data+" ✓"),V.mine())}
async function nvCancel(){const{error}=await sb.rpc("my_next_visit_cancel");error?toast(error.message):(toast("اتلغى التذكير"),V.mine())}

const nvLoy0=V.loy;
V.loy=async()=>{await nvLoy0();if(tab!="loy")return;
try{const{data,error}=await sb.rpc("my_prefs");if(error||!data||tab!="loy")return;const el=$("app");if(!el)return;
el.insertAdjacentHTML("beforeend",`<h2>الإشعارات</h2><div class="box"><div class="row"><div><b>عروض ورسائل من الصالون</b><div class="m">تقدر تقفلها في أي وقت. تأكيدات الحجز وتذكيراتك اللي طلبتها بتوصلك دايمًا.</div></div><button class="btn s ${data.marketing_ok?"":"g"}" onclick="nvMkt(${!data.marketing_ok})">${data.marketing_ok?"شغّالة":"مقفولة"}</button></div></div>`);
const{data:ds}=await sb.rpc("my_delete_status");el.insertAdjacentHTML("beforeend",`<h2>بياناتي وخصوصيتي</h2><div class="box">${ds=="pending"?`<p class="m">طلب حذف حسابك وبياناتك بيتراجع من الإدارة.</p><button class="btn s g" onclick="nvDelCancel()">سحب الطلب</button>`:`<p class="m">تقدر تطلب حذف حسابك وبياناتك الشخصية (الاسم والموبايل والصور والرسائل). الفواتير بتفضل في سجلات الصالون من غير ما تدل عليك.</p><button class="btn s g" onclick="nvDelAsk()">طلب حذف حسابي</button>`}</div>`)}catch(e){}};
async function nvDelAsk(){if(!await askConfirm("متأكد إنك عايز تطلب حذف حسابك وبياناتك؟ بعد موافقة الإدارة مش هتقدر تدخل بالحساب ده ولا ترجّع نقاطك."))return;const{error}=await sb.rpc("my_delete_request");error?toast(error.message):(toast("اتبعت طلب الحذف للإدارة ✓"),V.loy())}
async function nvDelCancel(){const{error}=await sb.rpc("my_delete_cancel");error?toast(error.message):(toast("اتسحب الطلب"),V.loy())}
async function nvMkt(on){const{error}=await sb.rpc("my_prefs_set",{p_marketing:on});error?toast(error.message):(toast(on?"هتوصلك عروض الصالون":"وقفنا العروض ✓"),V.loy())}
