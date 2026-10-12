/* core/pwa.js — تثبيت التطبيق */

// ================= PWA: تثبيت التطبيق =================

if("serviceWorker" in navigator)addEventListener("load",()=>navigator.serviceWorker.register("/sw.js").catch(()=>{}));

let dip=null;

const standalone=()=>matchMedia("(display-mode: standalone)").matches||navigator.standalone;

function instBanner(msg,btn){if(standalone()||$("inst"))return;try{if(localStorage.getItem("inst_x"))return}catch(e){}
const d=document.createElement("div");d.id="inst";d.className="inst";
d.innerHTML=`<span style="flex:1">${msg}</span>${btn?`<button class="btn s" id="instb">تثبيت</button>`:""}<button aria-label="إغلاق" id="instx" style="background:none;border:0;color:inherit;font-size:22px;cursor:pointer">×</button>`;document.body.appendChild(d);
$("instx").onclick=()=>{d.remove();try{localStorage.setItem("inst_x","1")}catch(e){}};
if(btn)$("instb").onclick=async()=>{dip.prompt();await dip.userChoice;dip=null;d.remove()}}

addEventListener("beforeinstallprompt",e=>{e.preventDefault();dip=e;instBanner("ثبّت التطبيق على موبايلك للدخول السريع",true)});

addEventListener("appinstalled",()=>{$("inst")?.remove()});

if(/iphone|ipad|ipod/i.test(navigator.userAgent)&&!standalone())setTimeout(()=>instBanner("لتثبيت التطبيق: اضغط زر المشاركة ثم «إضافة إلى الشاشة الرئيسية»",false),2500);

addEventListener("offline",()=>toast("مفيش إنترنت"));

addEventListener("online",()=>toast("رجع الإنترنت ✓"));
