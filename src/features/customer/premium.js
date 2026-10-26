/* features/customer/premium.js — الرئيسية البريميوم لتطبيق العميل:
   صورة العميل · دورك لايف · كارت العضوية · كرّر آخر زيارة · هدية عيد الميلاد · الدعوات */

const initials=n=>{const w=String(n||"").trim().split(/\s+/).filter(Boolean);return(w[0]||"؟").slice(0,1)+(w[1]?" "+w[1].slice(0,1):"")};
const avatarHtml=(p,size,click)=>`<span class="av${click?" av-edit":""}" style="width:${size}px;height:${size}px;font-size:${Math.round(size/2.6)}px"${click?` role="button" tabindex="0" onclick="pickAvatar()"`:""}>${p&&p.avatar?`<img src="${esc(p.avatar)}" alt="${esc(p.name||"عميل")}">`:`<b>${esc(initials(p&&p.name))}</b>`}${click?`<span class="av-cam">＋</span>`:""}</span>`;

// تصغير الصورة 256×256 (قص من النص) وتحويلها JPEG صغيرة
function shrinkImage(file){return new Promise((res,rej)=>{const r=new FileReader();r.onerror=()=>rej(new Error("مقدرتش أقرأ الصورة"));r.onload=()=>{const im=new Image();im.onerror=()=>rej(new Error("صورة غير صالحة"));im.onload=()=>{const c=document.createElement("canvas");const max=256;c.width=max;c.height=max;const s=Math.min(im.width,im.height);const x=(im.width-s)/2,y=(im.height-s)/2;const ctx=c.getContext("2d");ctx.fillStyle="#000";ctx.fillRect(0,0,max,max);ctx.drawImage(im,x,y,s,s,0,0,max,max);c.toBlob(blob=>blob?res(blob):rej(new Error("فشل ضغط الصورة")),"image/jpeg",.82)};im.src=r.result}});}

function pickAvatar(){const i=document.createElement("input");i.type="file";i.accept="image/*";i.onchange=async()=>{const f=i.files&&i.files[0];if(!f)return;try{toast("بجهّز الصورة...");const b=await shrinkImage(f);const fr=new FileReader();fr.onload=async()=>{const{error}=await sb.rpc("set_my_profile",{p_avatar: String(fr.result).split(",")[1]||fr.result});if(error)return toast(error.message);C.myp=null;toast("تم تحديث صورتك");if(tab=="hm")V.hm();};fr.readAsDataURL(b);}catch(e){toast(e.message||"مقدرتش تحديث الصورة");}};i.click();}
async function rmAvatar(){if(!confirm("تشيل صورتك؟"))return;const{error}=await sb.rpc("set_my_profile",{p_remove_avatar:true});error?toast(error.message):(C.myp=null,toast("اتشالت الصورة"),V.hm&&V.hm());}

async function myProfile(force){if(C.myp&&!force)return C.myp;const{data}=await sb.rpc("my_profile");C.myp=data||{};return C.myp}

function editBday(){const e=$("bd_e");if(!e)return;e.innerHTML=`<div class="chips" style="margin-top:8px"><input id="bd_in" type="date" value="${esc((C.myp&&C.myp.birthday)||"")}" max="${ymd(new Date())}" /></div>`;}

async function saveBday(){const v=$("bd_in")?.value;if(!v)return toast("اختار تاريخ ميلادك");const{error}=await sb.rpc("set_my_profile",{p_birthday:v});error?toast(error.message):(C.myp=null,toast("تم تحديث تاريخ الميلاد"),V.hm&&V.hm());}
async function claimBday(){const{data,error}=await sb.rpc("claim_birthday_gift");if(error)return toast(error.message);C.myp=null;okFlash("كل سنة وانت طيب 🎂","اتضافلك "+data+" نقطة هدية");V.hm&&V.hm();}

// كرّر آخر زيارة: بنجهّز الحجز بنفس الحلاق والخدمات ونوديه يختار اليوم والفترة
function repeatVisit(){const v=C.lastVisit;if(!v)return;C.b={s:(v.service_ids||[]).slice(),barber:v.barber_id||undefined,day:0,period:null};toast("جهّزنا الحجز زي آخر مرة — اختار اليوم والفترة من فضلك");go("book");}

V.hm=async()=>{clearInterval(C.poll);
const{data:{user}}=await sb.auth.getUser();
const[{data:c},p,{data:h},{data:lv}]=await Promise.all([sb.from("customers").select("id,name,points,lifetime_points,visits").eq("user_id",user.id).maybeSingle(),myProfile(true),sb.rpc("my_history"),sb.rpc("last_visit")]);
if(!c)return put(`<p class="m">مفيش حساب عميل.</p>`);
const{data:tier}=await sb.rpc("loyalty_tier",{p_life:c.lifetime_points}),t=(tier&&tier[0])||{name:"",mult:1,next_at:null},g=C.cfg;
const L=h||[],act=L.find(x=>["upcoming","checked_in","in_service"].includes(x.status));
let live="";if(act){let q={};try{const{data:v2}=await sb.rpc("queue_status_v2",{p_id:act.id});q=v2||{}}catch(e){};
const code=q.ticket_code||("#"+act.ticket_no),ahead=q.ahead,eta=q.est_wait_min;
live=`<div class="hm-live" role="button" tabindex="0" onclick="go('queue')"><div><div class="m">دورك دلوقتي</div><div class="hm-code" dir="ltr">${esc(code)}</div></div><div class="hm-live-r"><span class="tag st-${act.status}">${act.status=='upcoming'?'مستني':act.status=='checked_in'?'وصل':'قيد الخدمة'}</span><b>${ahead===0||ahead==null?"أنت التالي":`قدامك ${num(ahead)} ${ahead==1?"زبون":"زبائن"}`}</b><div class="m">${eta?`متوقع ${num(eta)} دقيقة`:'لو عندك أي سؤال، اضغط هنا'}</div></div><div class="hm-go">الذهاب →</div></div>`;}
const first=String(c.name||"").trim().split(/\s+/)[0]||"";
const pct=t.next_at?Math.min(100,c.lifetime_points/t.next_at*100):100;
C.lastVisit=lv&&lv.id?lv:null;
const nextGoal=t.next_at?Math.max(0,t.next_at-c.lifetime_points):0;
const rep=C.lastVisit?`<div class="box hm-rep"><div class="m">زي آخر مرة؟</div><b>${esc(C.lastVisit.services||"—")}</b><div class="m">${C.lastVisit.barber_name?"مع "+esc(C.lastVisit.barber_name):"اختار بنفسك"}</div><button class="btn s g" style="margin-top:8px;width:100%" onclick="repeatVisit()">احجز نفس الزيارة</button></div>`:"";
const bday=!p.birthday_enabled?"":p.can_claim_birthday?`<div class="box hm-gift"><b>🎂 كل سنة وانت طيب!</b><div class="m">هديتك ${num(p.birthday_points)} نقطة</div><button class="btn s g" style="margin-top:8px;width:100%" onclick="claimBday()">استلام الهدية</button></div>`:`<div class="box hm-gift"><b>🎂 هدية الميلاد</b><div class="m">هيتفعّل بعد ${esc(p.next_birthday_label||"التاريخ التالي")}</div></div>`;
const perks=[
  {icon:'✨', label:'مناسب لك', value:'خدمات مختارة'},
  {icon:'🎯', label:'نقاطك', value:num(c.points)},
  {icon:'🚀', label:'المستوى', value:t.name||'عضو'},
  {icon:'👥', label:'الزيارات', value:num(c.visits||0)}
];
const quickBadges=[act?'دورك الآن':'مستعد للحجز',p.can_claim_birthday?'هدية الميلاد':'ولاء مستمر',c.points>0?`نقاط ${num(c.points)}`:'ابدأ التجمّع'];
put(`<div class="hm-shell"><div class="hm-head">${avatarHtml(p,58,true)}<div><div class="m">أهلًا بيك</div><h1 style="margin:0">${esc(first||c.name||"عميل")}</h1></div></div>
<div class="hm-badges">${quickBadges.map(x=>`<span class="hm-badge">${esc(x)}</span>`).join("")}</div>
${live||`<div class="box hm-ghost"><div class="m">ما عندك دور حالي.</div><b>إبدأ اليوم بحجز جديد</b></div>`}
<div class="vip" role="button" tabindex="0" onclick="go('loy')"><div class="vip-top"><span class="vip-brand">${esc(g.salon_name||"صالون أبو يوسف")}</span><span class="vip-tier">${esc(t.name||"عضو")}${t.mult>1?" · ×"+t.mult:""}</span></div><div class="vip-pts">${num(c.lifetime_points||0)}<small>نقطة</small></div><div class="vip-bar"><i style="width:${Math.min(100,pct)}%"></i></div><div class="vip-foot"><span>المرحلة الحالية</span><span>${t.next_at?`${num(Math.max(0,t.next_at-c.lifetime_points))} نقطة لغاية التالي`:`أعلى مستوى`}</span></div></div>
<div class="hm-grid">${perks.map(x=>`<div class="box hm-mini"><div class="hm-mini-ico">${x.icon}</div><div class="m">${esc(x.label)}</div><b>${esc(x.value)}</b></div>`).join("")}</div>
<div class="hm-cta"><button class="btn" onclick="C.b=null;go('book')">احجز دورك</button><button class="btn g" onclick="go('loy')">نقاطي</button><button class="btn g" onclick="go('menu')">الخدمات</button></div>
${bday}${rep}
<div class="box hm-note"><div class="m">مركز الولاء</div><b>تجمّع ${num(c.lifetime_points||0)} نقطة</b><div class="m">${nextGoal>0?`متبقي لك ${num(nextGoal)} نقطة للوصول للمستوى التالي.`:`أنت وصلت لأعلى مستوى الحالي.`}</div><div class="hm-note-actions"><button class="btn s g" onclick="go('loy')">تفاصيل المكافآت</button><button class="btn s g" onclick="drawRef&&drawRef()">دعوة صديق</button></div></div></div>`);

// Keep the original profile actions working for the customer account section as well.
if ($("bd_e")) {
  const p0 = p || {};
  $("bd_e").innerHTML = p0.birthday ? `<div class="m">تاريخ ميلادك</div><b>${esc(p0.birthday)}</b>` : `<div class="m">إضافة تاريخ ميلاد</div>`;
}
};

// بانر حالة الطلب المستعجل فوق صفحة الدور
const drawQ0=drawQ;drawQ=function(qs){drawQ0(qs);const u=qs&&qs.urg;if(!u||!u.state)return;const a=$("app");if(!a)return;
a.insertAdjacentHTML("afterbegin",`<div class="box" style="border-color:var(--red);margin-bottom:10px"><b>⚡ ${u.state=="requested"?"طلبك المستعجل في انتظار موافقة الصالون":"حالة الطلب المستعجل"}</b><div class="m">${u.state=="requested"?"تم إرسال الطلب، سنراجع المواعيد المتاحة لك قريبًا":"تم تحديث حالة الطلب"}</div></div>`)};

// كود العميل السري: بيظهر بضغطة زرار بس (مش مكشوف على الشاشة)

async function drawRef(){const o=$("refbox");if(!o)return;const{data:r,error}=await sb.rpc("my_referral");if(error||!r||r.enabled===false)return;
const msg="تعالى جرّب صالون أبو يوسف! سجّل من هنا "+location.origin+" واكتب كود الدعوة "+r.code+" — واحنا الاتنين هنكسب نقاط هدية.";
window._refMsg=msg;
o.innerHTML=`<h2>ادعي صاحبك واكسبوا نقاط 🎁</h2><div class="box"><div class="m">كودك — لما صاحبك يدفع أول فاتورة، هو ياخد ${r.points} نقطة، وأنت كمان هتاخد ${r.points} نقطة.</div><div class="code-big">${esc(r.code)}</div><button class="btn g" onclick="copyRef()">نسخ رسالة الدعوة</button></div>`;}
async function svcRedeem(){const{data,error}=await sb.rpc("redeem_service_options");if(error)return toast(error.message);window._svcOpts=data.items||[];
dsOpen("استبدال النقاط بخدمة",`<div class="m" style="margin-bottom:8px">نقاطك: <b>${num(data.points)}</b> — اختار الخدمة، النقاط بتتخصم من حسابك فورًا.</div><div class="svc-2">${(window._svcOpts||[]).map(x=>`<button class="row" onclick="svcRedeemGo(${x.id})"><div><b>${esc(x.name)}</b><div class="m">${num(x.use)} نقطة</div></div><span class="tag">${esc(x.discount)} خصم</span></button>`).join("")}</div>`)}
async function svcRedeemGo(id){const x=(window._svcOpts||[]).find(z=>z.id==id);if(!x||!confirm(`تستبدل ${x.use} نقطة بخصم ${x.discount} على «${x.name}»؟\nهتدفع ${x.pay} فقط.`))return;const{data,error}=await sb.rpc("redeem_service_option",{p_id:id});if(error)return toast(error.message);toast("تم استبدال الخدمة بنجاح ✅");svcClose();V.hm&&V.hm();}
function copyRef(){try{navigator.clipboard.writeText(window._refMsg).then(()=>toast("اتنسخت ✓"),()=>toast("مقدرتش أنسخ"))}catch(e){toast("مقدرتش أنسخ")}}
async function applyRef(){const v=($("refin")?.value||"").trim();if(!v)return toast("اكتب الكود أو الرقم");const{data,error}=await sb.rpc("apply_referral",{p_key:v});if(error)return toast(error.message);toast("تم تطبيق كود الدعوة ✅");V.hm&&V.hm();}

