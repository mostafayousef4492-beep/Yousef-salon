/* ui/global.js — مستمعات عامة */

document.addEventListener("keydown",e=>{if(e.key=="Escape")svcClose()});

document.addEventListener("click",e=>{const n=$("nav");n&&n.classList.contains("open")&&!e.target.closest("nav")&&n.classList.remove("open")});
