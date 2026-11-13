/* features/customer/wow.js — لمسات الإبهار: ترحيب أول دخول · عدّاد النقاط · ميل كارت الولاء · هيكل تحميل · اهتزاز خفيف
   كله تحسين شكلي؛ أي خطأ هنا مايكسرش التطبيق. */
(()=>{
const OB="salon_ob1",rm=()=>matchMedia("(prefers-reduced-motion:reduce)").matches;
const ls={get:k=>{try{return localStorage.getItem(k)}catch(e){return null}},set:(k,v)=>{try{localStorage.setItem(k,v)}catch(e){}}};
const buzz=n=>{try{navigator.vibrate&&navigator.vibrate(n)}catch(e){}};

// 1) عدّاد النقاط + لمعة + ميل خفيف لكارت الولاء
function dress(){
  try{
    const v=document.querySelector(".vip");if(!v||v.dataset.w)return;v.dataset.w=1;
    if(rm())return;
    const sh=document.createElement("i");sh.className="sheen";sh.setAttribute("aria-hidden","true");v.appendChild(sh);
    const p=v.querySelector(".vip-pts"),sm=p&&p.querySelector("small"),raw=p&&parseInt(String(p.firstChild&&p.firstChild.textContent||"").replace(/[^\d]/g,""),10);
    if(p&&raw>0&&p.firstChild&&p.firstChild.nodeType==3){const n=p.firstChild,t0=performance.now(),D=900,f=t=>{const k=Math.min(1,(t-t0)/D),e=1-Math.pow(1-k,3);n.textContent=Math.round(raw*e).toLocaleString("ar-EG");if(k<1)requestAnimationFrame(f);else n.textContent=raw.toLocaleString("ar-EG")};requestAnimationFrame(f)}
    v.addEventListener("pointermove",e=>{const r=v.getBoundingClientRect(),x=(e.clientX-r.left)/r.width-.5,y=(e.clientY-r.top)/r.height-.5;v.style.setProperty("--ty",(x*8).toFixed(1)+"deg");v.style.setProperty("--tx",(-y*8).toFixed(1)+"deg")},{passive:true});
    v.addEventListener("pointerleave",()=>{v.style.setProperty("--tx","0deg");v.style.setProperty("--ty","0deg")});
  }catch(e){}
}
new MutationObserver(()=>{if(document.querySelector(".vip:not([data-w])"))dress()}).observe(document.documentElement,{childList:true,subtree:true});

// 2) هيكل تحميل للرئيسية بدل الفراغ
(()=>{const q=V.hm;if(!q)return;V.hm=async()=>{try{if(!$("app").querySelector(".hm-shell"))$("app").innerHTML=`<div class="wsk"><div class="sk s"></div><div class="sk"></div><div class="sk h"></div><div class="sk"></div></div>`}catch(e){}return q()}})();

// 3) اهتزاز خفيف على الأزرار الأساسية
document.addEventListener("click",e=>{const b=e.target.closest&&e.target.closest(".btn:not(.g),.hm-mini,.hm-live,nav button");if(b)buzz(8)},true);

// 4) ترحيب أول دخول (مرة واحدة)
const SL=[["✂️","أهلًا بيك في الصالون","احجز دورك من موبايلك في ثواني، من غير زحمة ولا انتظار طويل."],["📍","تابع دورك لحظة بلحظة","شوف كام واحد قدامك ومتى هييجي دورك، وهنبلغك لما الحلاق يناديك."],["👑","نقاطك بتتحول لمكافآت","كل زيارة بتجمّعلك نقاط، وكل ما تزيد مستواك بيعلى وتكسب مميزات أكتر."],["✨","اسأل مساعد الصالون","اسأله عن الحجز، نقاطك، ونصايح للعناية بالشعر والبشرة."]];
window.wobOpen=function(force){
  if(!force&&ls.get(OB))return;if($("wob"))return;
  let i=0;const d=document.createElement("div");d.id="wob";d.setAttribute("role","dialog");d.setAttribute("aria-label","ترحيب");
  d.innerHTML=`<button class="wb-sk" onclick="wobClose()">تخطّي</button><div class="wb-track">${SL.map(s=>`<div class="wb-sl"><div class="wb-ic">${s[0]}</div><h2>${s[1]}</h2><p>${s[2]}</p></div>`).join("")}</div><div class="wb-ft"><div class="wb-dots">${SL.map(()=>"<i></i>").join("")}</div><button class="btn" id="wb_n"></button></div>`;
  document.body.appendChild(d);
  const sl=[...d.querySelectorAll(".wb-sl")],dots=[...d.querySelectorAll(".wb-dots i")],nb=d.querySelector("#wb_n");
  const show=()=>{sl.forEach((s,k)=>{s.style.transform=`translateX(${-i*100}%)`;s.style.opacity=k==i?1:0});dots.forEach((x,k)=>x.classList.toggle("on",k==i));nb.textContent=i==SL.length-1?"يلا نبدأ":"التالي"};
  nb.onclick=()=>{if(i<SL.length-1){i++;show()}else wobClose()};
  let sx=null;d.addEventListener("touchstart",e=>{sx=e.touches[0].clientX},{passive:true});d.addEventListener("touchend",e=>{if(sx==null)return;const dx=e.changedTouches[0].clientX-sx;sx=null;if(Math.abs(dx)<50)return;if(dx>0&&i<SL.length-1)i++;else if(dx<0&&i>0)i--;show()});
  show();
};
window.wobClose=function(){ls.set(OB,"1");const d=$("wob");if(d){d.style.animation="fadeout .25s both";setTimeout(()=>d.remove(),250)}};
// يظهر بعد ما الرئيسية تتحمّل لأول مرة بعد تسجيل الدخول
(()=>{const q=V.hm;if(!q)return;V.hm=async()=>{await q();try{if(!ls.get(OB)&&$("app")&&$("app").querySelector(".hm-shell"))setTimeout(()=>wobOpen(),500)}catch(e){}}})();
// 5) رابط الدعوة ?ref=CODE: يتحفظ ويتطبّق تلقائي لما العميل الجديد يسجّل
try{const u=new URLSearchParams(location.search).get("ref");if(u&&/^[A-Za-z0-9]{3,16}$/.test(u))ls.set("salon_ref",u.toUpperCase())}catch(e){}
async function refAuto(){
  const k=ls.get("salon_ref");if(!k)return;
  try{const{data:r}=await sb.rpc("my_referral");if(!r||r.enabled===false)return;
    if(!r.can_apply){try{localStorage.removeItem("salon_ref")}catch(e){}return}
    if(r.code&&String(r.code).toUpperCase()==k){try{localStorage.removeItem("salon_ref")}catch(e){}return}
    const{data,error}=await sb.rpc("apply_referral",{p_key:k});try{localStorage.removeItem("salon_ref")}catch(e){}
    if(!error&&data)toast("اتسجّلت دعوة "+data+" ✓ هتاخد نقاطك بعد أول فاتورة")}catch(e){}
}
// 6) كارت الدعوة في الرئيسية
async function refCard(){
  try{
    const A=$("app"),sh=A&&A.querySelector(".hm-shell");if(!sh||$("hmref"))return;
    const{data:r,error}=await sb.rpc("my_referral");if(error||!r||r.enabled===false||!r.code)return;
    if(!$("app").querySelector(".hm-shell")||$("hmref"))return;
    let nm="";try{nm=String((await myProfile()).name||"").trim().split(/\s+/)[0]||""}catch(e){}
    window._refMsg=refMsg(r,nm);
    const d=document.createElement("div");d.id="hmref";d.className="box hm-refc";
    d.innerHTML=`<div class="hm-refc-t"><span class="hm-refc-i">🎁</span><div><b>ادعي صاحبك واكسبوا نقاط</b><div class="m">هو ياخد ${r.points} وانت تاخد ${r.referrer_points} بعد أول فاتورة</div></div></div><div class="chips" style="margin-top:10px"><a class="btn s" target="_blank" rel="noopener" href="https://wa.me/?text=${encodeURIComponent(window._refMsg)}">ابعت دعوة على واتساب</a><button class="btn s g" onclick="copyRef()">نسخ</button></div>${r.invited?`<div class="m" style="margin-top:8px">دعيت ${r.invited} · اتكافأوا ${r.rewarded} · كسبت ${r.earned} نقطة</div>`:""}`;
    const cta=sh.querySelector(".hm-cta");cta?cta.after(d):sh.appendChild(d);
  }catch(e){}
}
(()=>{const q=V.hm;if(!q)return;V.hm=async()=>{await q();refAuto().then(refCard)}})();
})();
