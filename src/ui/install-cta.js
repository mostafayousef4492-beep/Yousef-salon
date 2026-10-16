/* ui/install-cta.js — زرار "نزّل التطبيق" الواضح في صفحة الحجز (/book)
   أندرويد/كروم: بيفتح نافذة التثبيت مباشرة. آيفون وباقي المتصفحات: خطوات قصيرة. */
(()=>{
const standalone=()=>matchMedia("(display-mode: standalone)").matches||navigator.standalone===true;
if(standalone())return;
let dip=null;
const ua=navigator.userAgent,ios=/iphone|ipad|ipod/i.test(ua),inApp=/FBAN|FBAV|Instagram|Line\/|Snapchat|TikTok|; wv\)|WhatsApp/i.test(ua);
const css=document.createElement("style");
css.textContent=`.ic-bar{position:sticky;top:0;z-index:30;display:flex;align-items:center;gap:12px;margin:10px 14px 0;padding:12px 14px;border-radius:16px;background:linear-gradient(135deg,#C9A24B,#E8CB7C);color:#1a1405;box-shadow:0 6px 22px rgba(0,0,0,.35)}
.ic-bar b{display:block;font-size:15px}.ic-bar span{font-size:12px;opacity:.85}
.ic-bar .ic-t{flex:1}.ic-bar button.ic-go{border:0;border-radius:12px;padding:12px 18px;font:inherit;font-weight:800;font-size:15px;background:#1a1405;color:#F3EEE4;cursor:pointer;white-space:nowrap}
.ic-bar button.ic-x{border:0;background:none;color:#1a1405;font-size:22px;line-height:1;cursor:pointer;padding:0 2px}
.ic-sheet{position:fixed;inset:0;z-index:60;background:rgba(0,0,0,.6);display:flex;align-items:flex-end;justify-content:center}
.ic-sheet>div{width:100%;max-width:520px;background:var(--card,#141821);color:var(--ink,#F3EEE4);border-radius:20px 20px 0 0;padding:20px 18px 28px;line-height:1.9}
.ic-sheet h3{margin:0 0 8px}.ic-sheet ol{margin:8px 0 14px;padding-inline-start:22px}.ic-sheet button{width:100%;border:0;border-radius:12px;padding:12px;font:inherit;font-weight:700;background:#C9A24B;color:#1a1405;cursor:pointer}`;
document.head.appendChild(css);
const bar=document.createElement("div");bar.className="ic-bar";bar.id="icbar";
bar.innerHTML=`<div class="ic-t"><b>📲 نزّل تطبيق صالون أبو يوسف</b><span>حجز أسرع · نقاطك وعروضك · إشعار لما دورك يقرب</span></div><button class="ic-go" id="icgo">تنزيل التطبيق</button><button class="ic-x" id="icx" aria-label="إغلاق">×</button>`;
const mount=()=>{const h=document.querySelector("header.top");(h?h.insertAdjacentElement("afterend",bar):document.body.prepend(bar))};
const sheet=(title,steps)=>{const s=document.createElement("div");s.className="ic-sheet";s.innerHTML=`<div><h3>${title}</h3><ol>${steps.map(x=>`<li>${x}</li>`).join("")}</ol><button id="icok">تمام</button></div>`;s.onclick=e=>{if(e.target===s||e.target.id==="icok")s.remove()};document.body.appendChild(s)};
addEventListener("beforeinstallprompt",e=>{e.preventDefault();dip=e});
addEventListener("appinstalled",()=>bar.remove());
const go=async()=>{
  if(dip){dip.prompt();try{await dip.userChoice}catch(e){}dip=null;return}
  if(ios)return sheet("تنزيل التطبيق على آيفون",["افتح الصفحة دي في <b>Safari</b>","اضغط زرار المشاركة <b>⎋</b> تحت","اختار <b>«إضافة إلى الشاشة الرئيسية»</b>","اضغط <b>إضافة</b> — هتلاقي أيقونة التطبيق على الشاشة"]);
  if(inApp)return sheet("افتح الرابط في المتصفح الأول",["اضغط على النقط الثلاثة ⋮ أو أيقونة المشاركة","اختار <b>«فتح في المتصفح»</b> (Chrome / Safari)","وبعدها دوس <b>تنزيل التطبيق</b>"]);
  sheet("تنزيل التطبيق",["اضغط على القايمة <b>⋮</b> فوق في المتصفح","اختار <b>«تثبيت التطبيق»</b> أو <b>«إضافة إلى الشاشة الرئيسية»</b>","أكّد، وهتلاقي الأيقونة على شاشتك"]);
};
bar.querySelector("#icgo").onclick=go;
bar.querySelector("#icx").onclick=()=>bar.remove();
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",mount);else mount();
if("serviceWorker" in navigator)addEventListener("load",()=>navigator.serviceWorker.register("/sw.js").catch(()=>{}));
})();
