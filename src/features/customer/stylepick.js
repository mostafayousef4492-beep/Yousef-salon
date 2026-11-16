/* features/customer/stylepick.js — اختار شكلك من كتالوج القصات (مجاني)
   الكتالوج (catalog.html) بيتفتح جوه التطبيق، وزرار «ده الشكل اللي عايزه» بيبعت الاختيار هنا، وبيتسجّل في ملف اللوك (wish_style) والحلاق بيشوفه. */

function styleOpen(){if($("sp_ov"))return;const d=document.createElement("div");d.id="sp_ov";d.style.cssText="position:fixed;inset:0;z-index:99999;background:#000;display:flex;flex-direction:column";
  d.innerHTML=`<div style="display:flex;justify-content:space-between;align-items:center;padding:10px 14px;color:#fff;font-weight:700"><span>اختار شكلك</span><button class="btn s g" onclick="styleClose()">✕ إغلاق</button></div><iframe src="/catalog.html" title="كتالوج القصات" style="flex:1;border:0;width:100%;background:#000"></iframe>`;
  document.body.appendChild(d)}
function styleClose(){const d=$("sp_ov");if(d)d.remove()}

window.addEventListener("message",async e=>{
  if(e.origin!==location.origin||!e.data||e.data.type!=="ay-pick")return;
  const ar=String(e.data.ar||"").slice(0,60),en=String(e.data.name||"").slice(0,60),label=ar&&en?ar+" ("+en+")":(ar||en);if(!label)return;
  const{error}=await sb.rpc("my_look_wish",{p_style:label});
  if(error)return toast(error.message);
  styleClose();toast("اتسجّل الشكل في ملف اللوك ✓ والحلاق هيشوفه")});
