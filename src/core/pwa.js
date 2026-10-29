/* core/pwa.js — تثبيت التطبيق */

// ================= PWA: تثبيت التطبيق =================

if("serviceWorker" in navigator)addEventListener("load",()=>navigator.serviceWorker.register("/sw.js").catch(()=>{}));

let dip=null;

const standalone=()=>matchMedia("(display-mode: standalone)").matches||navigator.standalone;

function instBanner(msg,btn){if(standalone()||$("inst"))return;try{if(localStorage.getItem("inst_x_"+APP_MODE))return}catch(e){}
const d=document.createElement("div");d.id="inst";d.className="inst";
d.innerHTML=`<span style="flex:1">${msg}</span>${btn?`<button class="btn s" id="instb">تثبيت</button>`:""}<button aria-label="إغلاق" id="instx" style="background:none;border:0;color:inherit;font-size:22px;cursor:pointer">×</button>`;document.body.appendChild(d);
$("instx").onclick=()=>{d.remove();try{localStorage.setItem("inst_x_"+APP_MODE,"1")}catch(e){}};
if(btn)$("instb").onclick=async()=>{dip.prompt();await dip.userChoice;dip=null;d.remove()}}

addEventListener("beforeinstallprompt",e=>{e.preventDefault();dip=e;instBanner("ثبّت التطبيق على موبايلك للدخول السريع",true)});

addEventListener("appinstalled",()=>{$("inst")?.remove()});

if(/iphone|ipad|ipod/i.test(navigator.userAgent)&&!standalone())setTimeout(()=>instBanner("لتثبيت التطبيق: اضغط زر المشاركة ثم «إضافة إلى الشاشة الرئيسية»",false),2500);

addEventListener("offline",()=>toast("مفيش إنترنت"));

addEventListener("online",()=>toast("رجع الإنترنت ✓"));

// مؤشر الاتصال (متصل / غير متصل / السيرفر مش متاح)
(function(){const el=document.createElement("div");el.id="netpill";el.setAttribute("role","status");
  el.style.cssText="position:fixed;top:calc(env(safe-area-inset-top,0px) + 6px);left:8px;z-index:9999;font:600 11px/1 system-ui,sans-serif;padding:5px 9px;border-radius:99px;color:#fff;pointer-events:none;opacity:.95";
  const set=(t,c)=>{el.textContent=t;el.style.background=c};set("جارٍ فحص الاتصال…","#6b7280");
  const add=()=>document.body&&document.body.appendChild(el);document.body?add():addEventListener("DOMContentLoaded",add);
  let last=null;async function probe(){
    if(navigator.onLine===false){last=false;return set("غير متصل","#b91c1c")}
    const c=new AbortController(),t=setTimeout(()=>c.abort(),5000);
    try{const r=await fetch(SUPABASE_URL+"/rest/v1/",{method:"HEAD",headers:{apikey:SUPABASE_KEY},cache:"no-store",signal:c.signal});clearTimeout(t);
      if(r.status>=500)throw 0;last=true;set("متصل","#15803d")}
    catch(e){clearTimeout(t);last=false;set("السيرفر مش متاح — العمليات الجديدة هتفشل ومش هتتأكد","#b91c1c")}}
  addEventListener("online",probe);addEventListener("offline",probe);setInterval(probe,15000);probe();
  window.netOk=()=>last!==false})();
