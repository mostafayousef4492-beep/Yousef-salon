/* ui/global.js — مستمعات عامة */

document.addEventListener("keydown",e=>{if(e.key=="Escape")svcClose()});

document.addEventListener("click",e=>{const n=$("nav");n&&n.classList.contains("open")&&!e.target.closest("nav")&&n.classList.remove("open")});

// إغلاق أي نافذة منبثقة (مشترك بين التطبيقات التلاتة)
function svcClose(){C.dsL=null;const w=$("sheet");if(w){w.classList.add("out");setTimeout(()=>w.remove(),160)}}
