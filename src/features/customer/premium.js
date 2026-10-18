/* features/customer/premium.js — الرئيسية البريميوم لتطبيق العميل:
   صورة العميل · دورك لايف · كارت العضوية · كرّر آخر زيارة · هدية عيد الميلاد · الدعوات */

const initials=n=>{const w=String(n||"").trim().split(/\s+/).filter(Boolean);return(w[0]||"؟").slice(0,1)+(w[1]?" "+w[1].slice(0,1):"")};
const avatarHtml=(p,size,click)=>`<span class="av${click?" av-edit":""}" style="width:${size}px;height:${size}px;font-size:${Math.round(size/2.6)}px"${click?` role="button" tabindex="0" onclick="pickAvatar()" aria-label="تغيير الصورة"`:""}>${p&&p.avatar?`<img src="${p.avatar}" alt="">`:`<b>${esc(initials(p&&p.name))}</b>`}${click?`<i class="av-cam" aria-hidden="true">+</i>`:""}</span>`;

// تصغير الصورة 256×256 (قص من النص) وتحويلها JPEG صغيرة
function shrinkImage(file){return new Promise((res,rej)=>{const r=new FileReader();r.onerror=()=>rej(new Error("مقدرتش أقرأ الصورة"));r.onload=()=>{const im=new Image();im.onerror=()=>rej(new Error("الصورة دي مش مدعومة"));im.onload=()=>{const S=256,c=document.createElement("canvas");c.width=c.height=S;const x=c.getContext("2d"),m=Math.min(im.width,im.height),sx=(im.width-m)/2,sy=(im.height-m)/2;x.drawImage(im,sx,sy,m,m,0,0,S,S);res(c.toDataURL("image/jpeg",.82))};im.src=r.result};r.readAsDataURL(file)})}

function pickAvatar(){const i=document.createElement("input");i.type="file";i.accept="image/*";i.onchange=async()=>{const f=i.files&&i.files[0];if(!f)return;try{toast("بجهّز الصورة...");const d=await shrinkImage(f);const{error}=await sb.rpc("set_my_profile",{p_avatar:d});if(error)return toast(error.message);C.myp=null;toast("اتغيّرت صورتك ✓");go(tab)}catch(e){toast(e.message||"فشل رفع الصورة")}};i.click()}
async function rmAvatar(){if(!confirm("تشيل صورتك؟"))return;const{error}=await sb.rpc("set_my_profile",{p_remove_avatar:true});error?toast(error.message):(C.myp=null,toast("اتشالت"),go(tab))}

async function myProfile(force){if(C.myp&&!force)return C.myp;const{data}=await sb.rpc("my_profile");C.myp=data||{};return C.myp}

function editBday(){const e=$("bd_e");if(!e)return;e.innerHTML=`<div class="chips" style="margin-top:8px"><input id="bd_in" type="date" value="${esc((C.myp&&C.myp.birthday)||"")}" max="${ymd(new Date())}" style="flex:1;margin:0"><button class="btn s" onclick="saveBday()">حفظ</button></div>`}

async function saveBday(){const v=$("bd_in")?.value;if(!v)return toast("اختار تاريخ ميلادك");const{error}=await sb.rpc("set_my_profile",{p_birthday:v});error?toast(error.message):(C.myp=null,toast("اتسجّل ✓"),V.hm())}
async function claimBday(){const{data,error}=await sb.rpc("claim_birthday_gift");if(error)return toast(error.message);C.myp=null;okFlash("كل سنة وانت طيب 🎂","اتضافلك "+data+" نقطة هدية");V.hm()}

// كرّر آخر زيارة: بنجهّز الحجز بنفس الحلاق والخدمات ونوديه يختار اليوم والفترة
function repeatVisit(){const v=C.lastVisit;if(!v)return;C.b={s:(v.service_ids||[]).slice(),barber:v.barber_id||undefined,day:0,period:null};toast("جهّزنا الحجز زي آخر مرة — اختار الفترة");go("book")}

V.hm=async()=>{clearInterval(C.poll);
const{data:{user}}=await sb.auth.getUser();
const[{data:c},p,{data:h},{data:lv}]=await Promise.all([sb.from("customers").select("id,name,points,lifetime_points,visits").eq("user_id",user.id).maybeSingle(),myProfile(true),sb.rpc("my_history"),sb.rpc("my_last_visit")]);
if(!c)return put(`<p class="m">مفيش حساب عميل.</p>`);
const{data:tier}=await sb.rpc("loyalty_tier",{p_life:c.lifetime_points}),t=(tier&&tier[0])||{name:"",mult:1,next_at:null},g=C.cfg;
const L=h||[],act=L.find(x=>["upcoming","checked_in","in_service"].includes(x.status));
let live="";if(act){let q={};try{const{data:v2}=await sb.rpc("queue_status_v2",{p_id:act.id});q=v2||{}}catch(e){}
const code=q.ticket_code||("#"+act.ticket_no),ahead=q.ahead,eta=q.est_wait_min;
live=`<div class="hm-live" role="button" tabindex="0" onclick="go('queue')"><div><div class="m">دورك دلوقتي</div><div class="hm-code" dir="ltr">${esc(code)}</div></div><div class="hm-live-r"><b>${act.status=="in_service"?"على الكرسي ✂️":ahead==null?"في الانتظار":ahead==0?"أنت اللي جاي!":"قدامك "+num(ahead)}</b><span class="m">${act.status!="in_service"&&eta?"حوالي "+num(eta)+" دقيقة":esc(act.barber_name||"")}</span></div><span class="hm-go">تابع ‹</span></div>`}
const first=String(c.name||"").trim().split(/\s+/)[0]||"";
const pct=t.next_at?Math.min(100,c.lifetime_points/t.next_at*100):100;
C.lastVisit=lv&&lv.id?lv:null;
const rep=C.lastVisit?`<div class="box hm-rep"><div class="m">زي آخر مرة؟</div><b>${esc(C.lastVisit.services||"—")}</b><div class="m">${C.lastVisit.barber_name?"مع "+esc(C.lastVisit.barber_name):""}</div><button class="btn" style="width:100%;margin-top:10px" onclick="repeatVisit()">كرّر آخر زيارة</button></div>`:"";
const bday=!p.birthday_enabled?"":p.can_claim_birthday?`<div class="box hm-gift"><b>🎂 كل سنة وانت طيب!</b><div class="m">هديتك ${num(p.birthday_points)} نقطة</div><button class="btn" style="width:100%;margin-top:8px" onclick="claimBday()">استلم هديتك</button></div>`:!p.birthday?`<div class="box"><b>🎂 ضيف تاريخ ميلادك</b><div class="m">وخد هدية نقاط في يوم ميلادك</div><div class="chips" style="margin-top:8px"><input id="bd_in" type="date" max="${ymd(new Date())}" style="flex:1;margin:0"><button class="btn s" onclick="saveBday()">حفظ</button></div></div>`:`<div class="box"><div class="m">🎂 ميلادك: <b>${new Date(p.birthday+"T00:00").toLocaleDateString("ar-EG",{day:"numeric",month:"long",year:"numeric"})}</b></div><div id="bd_e"><button class="btn s g" style="margin-top:6px" onclick="editBday()">كتبته غلط؟ عدّله</button></div></div>`;
put(`<div class="hm-head">${avatarHtml(p,58,true)}<div><div class="m">أهلًا بيك</div><h1 style="margin:0">${esc(first)}</h1></div></div>${live}
<div class="vip" role="button" tabindex="0" onclick="go('loy')"><div class="vip-top"><span class="vip-brand">${esc(g.salon_name)}</span><span class="vip-tier">${esc(t.name)}${t.mult>1?" · ×"+t.mult:""}</span></div><div class="vip-pts">${num(c.points)}<small>نقطة</small></div><div class="vip-bar"><i style="width:${pct}%"></i></div><div class="vip-foot"><span>${t.next_at?"باقي "+num(t.next_at-c.lifetime_points)+" نقطة للمستوى الجاي":"وصلت لأعلى مستوى"}</span><span>${num(c.visits||0)} زيارة</span></div></div>
${bday}${rep}
<div class="chips" style="margin-top:12px"><button class="btn" style="flex:1" onclick="C.b=null;go('book')">احجز دورك</button><button class="btn g" style="flex:1" onclick="go('loy')">ادعي صاحبك 🎁</button></div>`)};

// صورتي في صفحة الحساب
function myPhotoBox(p){return `<div class="box" style="display:flex;align-items:center;gap:14px">${avatarHtml(p,64,true)}<div style="flex:1"><b>${esc(p.name||"")}</b><div class="m">اضغط على الصورة لتغييرها</div></div>${p.avatar?`<button class="btn s g" onclick="rmAvatar()">شيل</button>`:""}</div>`}
