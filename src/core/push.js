/* core/push.js — الإشعارات والصوت */

// ================= الإشعارات (Web Push + صوت) =================

IC.bell='<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>';

const PUSH_OK=()=>"serviceWorker" in navigator&&"PushManager" in window&&"Notification" in window;

const isIOS=()=>/iphone|ipad|ipod/i.test(navigator.userAgent);

const b64u=s=>{const r=atob((s+"=".repeat((4-s.length%4)%4)).replace(/-/g,"+").replace(/_/g,"/"));return Uint8Array.from(r,c=>c.charCodeAt(0))};

const lsGet=k=>{try{return localStorage.getItem(k)}catch(e){return null}},lsSet=(k,v)=>{try{v==null?localStorage.removeItem(k):localStorage.setItem(k,v)}catch(e){}};

const pushSound=()=>lsGet("salon_sound")!="off",pushSetSound=v=>lsSet("salon_sound",v?null:"off");

// صوت التنبيه جوه التطبيق (بيتفتح بأول لمسة من المستخدم)

let _ac=null;

function unlockAudio(){try{_ac=_ac||new(window.AudioContext||window.webkitAudioContext)();if(_ac.state=="suspended")_ac.resume()}catch(e){}}

["pointerdown","keydown","touchstart"].forEach(ev=>addEventListener(ev,unlockAudio,{passive:true}));

function ding(urgent){if(!pushSound())return;try{unlockAudio();const t=_ac.currentTime,N=urgent?[[988,0],[1319,.16],[988,.34],[1319,.5]]:[[988,0],[1319,.15]];
N.forEach(([f,d])=>{const o=_ac.createOscillator(),g=_ac.createGain();o.type="sine";o.frequency.value=f;g.gain.setValueAtTime(0,t+d);g.gain.linearRampToValueAtTime(.35,t+d+.02);g.gain.exponentialRampToValueAtTime(.001,t+d+.5);o.connect(g);g.connect(_ac.destination);o.start(t+d);o.stop(t+d+.55)});
navigator.vibrate&&navigator.vibrate(urgent?[200,100,200,100,300]:[150])}catch(e){}}

function pushGo(t){if(!t||!me||!C.tabs)return;const ok=C.tabs.some(x=>x[0]==t)||Object.values(C.hubs||{}).some(h=>h.some(x=>x[0]==t));if(ok&&typeof V[t]=="function")go(t)}

if("serviceWorker" in navigator)navigator.serviceWorker.addEventListener("message",e=>{const m=e.data||{};
if(m.type=="push"){toast((m.title||"")+(m.body?" — "+m.body:""));ding(m.urgent);if(["home","appts","queue"].includes(tab)&&!C.chEdit)go(tab)}
else if(m.type=="goto")pushGo(m.tab)});

document.addEventListener("visibilitychange",()=>{if(document.visibilityState!="visible")return;try{navigator.clearAppBadge&&navigator.clearAppBadge();navigator.serviceWorker.ready.then(r=>r.getNotifications().then(l=>l.forEach(n=>n.close())))}catch(e){}});

// الاشتراك: ask=true بيطلب الإذن (لازم يتنادى من ضغطة زرار)، ask=false بيجدّد بصمت لو الإذن موجود

async function pushSync(ask){
if(!PUSH_OK()||typeof VAPID_PUBLIC_KEY=="undefined"||!VAPID_PUBLIC_KEY)return"unsupported";
if(Notification.permission=="denied")return"denied";
if(Notification.permission!="granted"){if(!ask)return"default";const p=await Notification.requestPermission();if(p!="granted")return p}
lsSet("push_off",null);
const reg=await navigator.serviceWorker.ready,key=b64u(VAPID_PUBLIC_KEY);let sub=await reg.pushManager.getSubscription();
if(sub){const cur=sub.options&&sub.options.applicationServerKey;if(cur){const a=new Uint8Array(cur);if(a.length!=key.length||a.some((v,i)=>v!=key[i])){await sub.unsubscribe();sub=null}}}
if(!sub)sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:key});
const j=sub.toJSON(),{error}=await sb.rpc("save_push_sub",{p_endpoint:j.endpoint,p_p256dh:j.keys.p256dh,p_auth:j.keys.auth,p_app:APP_MODE,p_ua:navigator.userAgent});
if(error)throw error;return"on"}

async function pushEnable(){try{const r=await pushSync(true);if(r=="on"){toast("تم تفعيل الإشعارات ✓");ding(false)}else if(r=="denied")toast("الإشعارات ممنوعة من إعدادات الموبايل أو المتصفح");else if(r=="unsupported")toast("الجهاز ده مش بيدعم الإشعارات");else toast("الإشعارات لسه مقفولة")}catch(e){toast("تعذر التفعيل: "+(e.message||e))}pushBellState();if($("sheet"))pushSheet()}

async function pushOff(){try{lsSet("push_off","1");const reg=await navigator.serviceWorker.ready,s=await reg.pushManager.getSubscription();if(s){await sb.rpc("remove_push_sub",{p_endpoint:s.endpoint});await s.unsubscribe()}toast("اتوقفت الإشعارات على الجهاز ده")}catch(e){toast(e.message||"تعذر الإيقاف")}pushBellState();pushSheet()}

async function pushUnlink(){try{if(!PUSH_OK())return;const reg=await navigator.serviceWorker.ready,s=await reg.pushManager.getSubscription();if(s)await sb.rpc("remove_push_sub",{p_endpoint:s.endpoint})}catch(e){}C.pb2=null;C.tabs=null;const b=$("pbell");b&&b.remove();const n=$("pbn");n&&n.remove()}

async function pushTest(){unlockAudio();toast("بنبعت إشعار تجربة...");const{data,error}=await sb.rpc("push_test");if(error)return toast(error.message);toast(data>0?"اتبعت لـ "+data+" جهاز. لو ما وصلش خلال ثواني راجع خطوات التفعيل":"مفيش جهاز مسجّل. فعّل الإشعارات الأول")}

async function pushStatus(){
if(typeof VAPID_PUBLIC_KEY=="undefined"||!VAPID_PUBLIC_KEY)return"nokey";
if(isIOS()&&!standalone())return"ios";
if(!PUSH_OK())return"unsup";
if(Notification.permission=="denied")return"denied";
if(Notification.permission!="granted")return"default";
try{const reg=await navigator.serviceWorker.ready;return(await reg.pushManager.getSubscription())?"on":"default"}catch(e){return"default"}}

const PMSG={nokey:"مفتاح الإشعارات (VAPID) ناقص في config.js.",ios:"على الآيفون لازم تثبّت التطبيق الأول: اضغط زر المشاركة ثم «إضافة إلى الشاشة الرئيسية»، وافتحه من الأيقونة، وبعدين فعّل الإشعارات من هنا.",unsup:"المتصفح ده مش بيدعم الإشعارات. جرّب Chrome، أو Safari على آيفون 16.4 أو أحدث.",denied:"الإشعارات ممنوعة لموقع الصالون. افتح إعدادات الموبايل أو المتصفح ← إعدادات الموقع ← الإشعارات وسمح بيها، وارجع هنا.",default:"الإشعارات مقفولة على الجهاز ده. فعّلها عشان توصلك حتى لو التطبيق مقفول.",on:"الإشعارات شغّالة على الجهاز ده ✓ هتوصلك حتى لو التطبيق مقفول."};

async function pushSheet(){const k=await pushStatus(),o=$("sheet");if(o)o.remove();const w=document.createElement("div");w.id="sheet";w.className="sheet-bg";w.onclick=e=>{if(e.target==w)svcClose()};
w.innerHTML=`<div class="sheet" role="dialog" aria-modal="true"><div class="sheet-h"><b>الإشعارات</b><button class="btn g s" onclick="svcClose()" aria-label="إغلاق">✕</button></div><p class="m" style="margin-top:0">${PMSG[k]}</p>${k=="default"?`<button class="btn" style="width:100%" onclick="pushEnable()">تفعيل الإشعارات</button>`:""}${k=="on"?`<button class="btn" style="width:100%" onclick="pushTest()">أبعت إشعار تجربة</button><button class="btn g" style="width:100%;margin-top:8px" onclick="pushOff()">إيقاف على الجهاز ده</button>`:""}<label class="row" style="cursor:pointer;margin-top:12px"><span>صوت التنبيه جوه التطبيق</span><input type="checkbox" ${pushSound()?"checked":""} onchange="pushSetSound(this.checked)" style="width:22px;height:22px;margin:0"></label><button class="btn g s" style="margin-top:8px" onclick="ding(true)">جرّب الصوت</button><p class="m">وهو التطبيق مقفول، صوت الإشعار بيطلع بصوت الموبايل الافتراضي للإشعارات، وتقدر تغيّره من إعدادات إشعارات الموبايل أو المتصفح.</p></div>`;document.body.appendChild(w)}

function pushBell(){if($("pbell"))return;const h=document.querySelector("header.top");if(!h)return;const b=document.createElement("button");b.id="pbell";b.className="bell";b.setAttribute("aria-label","الإشعارات");b.innerHTML=ic("bell");b.onclick=pushSheet;h.appendChild(b);pushBellState()}

async function pushBellState(){const b=$("pbell");if(!b)return;const on=(await pushStatus())=="on";if($("pbell"))$("pbell").className="bell"+(on?" on":"")}

function pushBanner(){if($("pbn")||!PUSH_OK()||typeof VAPID_PUBLIC_KEY=="undefined"||!VAPID_PUBLIC_KEY||Notification.permission!="default"||lsGet("push_x")||lsGet("push_off")||(isIOS()&&!standalone()))return;
const d=document.createElement("div");d.id="pbn";d.className="inst";d.innerHTML=`<span style="flex:1">فعّل الإشعارات عشان توصلك بصوت حتى لو التطبيق مقفول</span><button class="btn s" id="pbnb">تفعيل</button><button aria-label="إغلاق" id="pbnx" style="background:none;border:0;color:inherit;font-size:22px;cursor:pointer">×</button>`;document.body.appendChild(d);
$("pbnb").onclick=()=>{d.remove();pushEnable()};$("pbnx").onclick=()=>{d.remove();lsSet("push_x","1")}}

async function pushAfterBoot(){const{data:{session}}=await sb.auth.getSession();if(!session||!me||!C.tabs)return;pushBell();
const t=new URLSearchParams(location.search).get("tab");if(t){history.replaceState(null,"",location.pathname);pushGo(t)}
if(C.pb2==me.id)return;C.pb2=me.id;
if(PUSH_OK()&&Notification.permission=="granted"){if(!lsGet("push_off")){try{await pushSync(false)}catch(e){}}}else setTimeout(pushBanner,1800);
pushBellState()}
