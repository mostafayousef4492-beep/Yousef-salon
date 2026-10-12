/* ui/theme.js — الوضع الفاتح / الداكن (بيتحفظ على الجهاز) */
const THEME_KEY="salon_theme";
const curTheme=()=>document.documentElement.dataset.theme==="light"?"light":"dark";
function applyTheme(t){document.documentElement.dataset.theme=t;try{localStorage.setItem(THEME_KEY,t)}catch(e){}
  const m=document.querySelector('meta[name="theme-color"]');if(m)m.setAttribute("content",t==="light"?"#F5F2EA":"#0B0D12")}
function toggleTheme(){applyTheme(curTheme()==="light"?"dark":"light")}
// زرار الوضع في هيدر الموبايل (القائمة الجانبية فيها زرارها الخاص على الكمبيوتر)
(()=>{const h=document.querySelector("header.top");if(h&&!h.querySelector(".hdr-theme"))h.insertAdjacentHTML("beforeend",`<button class="hdr-theme" onclick="toggleTheme()" aria-label="تبديل الوضع الفاتح والداكن"><span class="ti-sun">${ic("sun")}</span><span class="ti-moon">${ic("moon")}</span></button>`)})();
(()=>{try{const t=localStorage.getItem(THEME_KEY);if(t==="light"||t==="dark")applyTheme(t)}catch(e){}})();
document.body.classList.add("m-"+(window.SALON_MODE||"customer"));
