/* ui/dialogs.js — نوافذ التأكيد والإدخال الموحّدة بدل confirm()/prompt() + زر الرجوع (يشتغل مع رجوع الموبايل) + حماية الضغط المزدوج. */
(()=>{
const E=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
let ovl=0,ign=0,fromPop=0;
// ---------- نافذة موحّدة ----------
function modal(html,{onKey}={}){return new Promise(res=>{
  const w=document.createElement("div");w.className="dlg-bg";w.innerHTML=`<div class="dlg" role="alertdialog" aria-modal="true">${html}</div>`;document.body.appendChild(w);
  const prev=document.activeElement;let done=false;
  const kd=e=>{if(e.key=="Escape"){e.stopPropagation();close(null)}else if(onKey&&w.contains(e.target))onKey(e,close)};document.addEventListener("keydown",kd,true);const close=v=>{if(done)return;done=true;document.removeEventListener("keydown",kd,true);w.classList.add("out");setTimeout(()=>{w.remove();try{prev&&prev.focus&&prev.focus()}catch(e){}},140);popOverlay(h);res(v)};
  const h=()=>close(null);pushOverlay(h);w._close=close;
  w.addEventListener("click",e=>{if(e.target===w)close(null)});
  const f=w.querySelector("input,textarea,.dlg-ok");f&&setTimeout(()=>f.focus(),30);
  w.querySelector(".dlg-ok").onclick=()=>close(w.querySelector("input,textarea")?w.querySelector("input,textarea").value:true);
  w.querySelector(".dlg-no").onclick=()=>close(null)})}
window.askConfirm=async(msg,o)=>{o=o||{};const v=await modal(`<p>${E(msg).replace(/\n/g,"<br>")}</p><div class="dlg-b"><button class="btn ${o.danger?"danger":""} dlg-ok">${E(o.ok||"تأكيد")}</button><button class="btn g dlg-no">إلغاء</button></div>`);return v===true};
window.askInput=async(msg,def,o)=>{o=o||{};const v=await modal(`<p>${E(msg).replace(/\n/g,"<br>")}</p><${o.multi?"textarea":"input"} class="dlg-in" ${o.multi?"":`type="${o.type||"text"}" inputmode="${o.mode||"text"}"`} value="${E(def)}">${o.multi?E(def)+"</textarea>":""}<div class="dlg-b"><button class="btn dlg-ok">${E(o.ok||"حفظ")}</button><button class="btn g dlg-no">إلغاء</button></div>`,{onKey:(e,c)=>{if(e.key=="Enter"&&!o.multi){e.preventDefault();c(e.target.value)}}});return v==null||v===true?null:String(v)};

// ---------- الرجوع: كل نافذة/شاشة بتاخد خطوة في الـ history ----------
const stack=[];
function pushOverlay(h){stack.push(h);history.pushState({ovl:stack.length},"")}
function popOverlay(h){const i=stack.lastIndexOf(h);if(i<0)return;stack.splice(i,1);ign++;history.back()}
window.addEventListener("popstate",e=>{
  if(ign>0){ign--;return}
  if(stack.length){const h=stack.pop();try{h()}catch(x){}return}
  const s=e.state;if(s&&s.tab&&typeof go=="function"&&s.tab!=window.tab){fromPop=1;go(s.tab)}
});
// الشيتات (dsOpen) بتتقفل بالرجوع كمان
(()=>{const o=window.dsOpen,c=window.svcClose;if(!o||!c)return;let pushed=0,hh=null;
  window.dsOpen=function(){const r=o.apply(this,arguments);if(!pushed){pushed=1;hh=()=>{pushed=0;hh=null;try{c.__orig?c.__orig():0}catch(e){}};stack.push(hh);history.pushState({ovl:stack.length},"")}return r};
  const sc=function(){const r=c.apply(this,arguments);if(pushed){pushed=0;const i=stack.indexOf(hh);if(i>=0){stack.splice(i,1);ign++;history.back()}hh=null}return r};
  sc.__orig=c;window.svcClose=sc;
})();
// go() بتسجّل الشاشة في الـ history + زر رجوع ثابت في الهيدر
(()=>{const g=window.go;if(typeof g!="function")return;const hd=document.querySelector("header.top");let bk=null;
  if(hd){bk=document.createElement("button");bk.id="bk";bk.type="button";bk.setAttribute("aria-label","رجوع");bk.innerHTML="›";bk.hidden=true;bk.onclick=()=>history.back();hd.prepend(bk)}
  let first=1,depth=0;
  window.go=function(t){const r=g.apply(this,arguments);
    try{if(t&&t!="out"){const cur=window.tab||t;if(first){first=0;history.replaceState({tab:cur,d:0},"")}else if(fromPop){fromPop=0}else if(!(history.state&&history.state.tab==cur)){depth++;history.pushState({tab:cur,d:depth},"")}
      if(bk){const h=!!(history.state&&history.state.d>0);bk.hidden=!h}}}catch(e){}
    return r};
  addEventListener("popstate",()=>{if(bk)bk.hidden=!(history.state&&history.state.d>0)});
})();
// ---------- حماية الضغط المزدوج: الزر الأساسي مايتنفذش مرتين في أقل من ١.٢ ثانية ----------
document.addEventListener("click",e=>{const b=e.target.closest&&e.target.closest("button.btn[onclick]:not(.s):not([data-multi])");if(!b)return;const n=Date.now();if(b._t&&n-b._t<1200){e.preventDefault();e.stopImmediatePropagation();return}b._t=n},true);
})();
