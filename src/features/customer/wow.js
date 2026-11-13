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
const MSG=[
 ["أهلًا يا {n}! 👋 أنا «يوسف»، مساعدك في الصالون. نورتنا!",1],
 ["هعرّفك على التطبيق في دقيقة، وبعدها كل حاجة هتبقى في إيدك ✂️",0],
 ["من «احجز دورك» بتختار الخدمة والحلاق والفترة، ومن غير زحمة ولا وقفة طويلة.",0],
 ["وبعد ما تحجز، «دوري» بيوريك كام واحد قدامك وهييجي دورك إمتى، وهنبلّغك أول ما الحلاق يناديك 📍",0],
 ["كل زيارة بتجمّعلك نقاط في «نقاطي»، والنقاط دي بتتحوّل لمكافآت وخصومات، وكل ما تزيد مستواك بيعلى 👑",0],
 ["وتقدر تدعو صحابك، إنت وهو هتاخدوا نقاط لما يدفع أول فاتورة 🎁",0],
 ["ولو عندك أي سؤال عن الحجز أو نقاطك، أو حتى مشكلة في الشعر أو البشرة، اسأل المساعد في أي وقت. أنا هنا ✨",0]];
let VOICE=null;const hasTTS=()=>"speechSynthesis"in window&&typeof SpeechSynthesisUtterance!="undefined";
const pickVoice=()=>{try{const v=speechSynthesis.getVoices();return v.find(x=>/ar[-_]EG/i.test(x.lang))||v.find(x=>/^ar/i.test(x.lang))||null}catch(e){return null}};
window.wobOpen=async function(force){
  if(!force&&ls.get(OB))return;if($("wob"))return;
  let nm="";try{nm=String((await myProfile()).name||"").trim().split(/\s+/)[0]||""}catch(e){}
  const T=MSG.map(m=>[m[0].replace("{n}",nm||"يا غالي").replace("يا يا","يا"),m[1]]);
  let i=0,timer=null,snd=false,mc=null;const d=document.createElement("div");d.id="wob";d.setAttribute("role","dialog");d.setAttribute("aria-label","ترحيب");
  d.innerHTML=`<div class="wb-top"><button class="wb-sk" onclick="wobClose()">تخطّي</button>${hasTTS()?`<button class="wb-snd" id="wb_s" aria-label="تشغيل الصوت">🔇</button>`:""}</div><div class="wb-stage" id="wb_m"></div><div class="wb-bub" id="wb_b" aria-live="polite"></div><div class="wb-ft"><div class="wb-dots">${T.map(()=>"<i></i>").join("")}</div><button class="btn" id="wb_n"></button></div>`;
  document.body.appendChild(d);
  try{mc=MASCOT.mount($("wb_m"))}catch(e){$("wb_m").innerHTML=`<div class="wb-ic">✂️</div>`}
  const bub=$("wb_b"),nb=$("wb_n"),dots=[...d.querySelectorAll(".wb-dots i")];
  const stop=()=>{if(timer){clearInterval(timer);timer=null}if(mc)mc.talk(false);try{speechSynthesis.cancel()}catch(e){}};
  const say=()=>{stop();const[t,w]=T[i];bub.textContent="";dots.forEach((x,k)=>x.classList.toggle("on",k==i));nb.textContent=i==T.length-1?"يلا نبدأ":"التالي";
    if(mc){mc.wave(!!w);if(w)setTimeout(()=>mc&&mc.wave(false),2600);mc.talk(true)}
    if(rm()){bub.textContent=t;if(mc)mc.talk(false)}else{let k=0;timer=setInterval(()=>{k+=1;bub.textContent=t.slice(0,k);if(k>=t.length)stop()},34)}
    if(snd&&hasTTS()){try{const u=new SpeechSynthesisUtterance(t.replace(/[\u{1F300}-\u{1FAFF}☀-➿✂«»]/gu,""));u.lang="ar-EG";VOICE=VOICE||pickVoice();if(VOICE)u.voice=VOICE;u.rate=1;speechSynthesis.speak(u)}catch(e){}}};
  nb.onclick=()=>{if(i<T.length-1){i++;say()}else wobClose()};
  bub.onclick=()=>{if(timer){stop();bub.textContent=T[i][0]}};
  const sb2=$("wb_s");if(sb2)sb2.onclick=()=>{snd=!snd;sb2.textContent=snd?"🔊":"🔇";sb2.setAttribute("aria-label",snd?"إيقاف الصوت":"تشغيل الصوت");if(snd)say();else{try{speechSynthesis.cancel()}catch(e){}}};
  d._stop=()=>{stop();if(mc)mc.destroy()};
  setTimeout(say,350);
};
window.wobClose=function(){ls.set(OB,"1");const d=$("wob");if(d){try{d._stop&&d._stop()}catch(e){}d.style.animation="fadeout .25s both";setTimeout(()=>d.remove(),250)}};
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
