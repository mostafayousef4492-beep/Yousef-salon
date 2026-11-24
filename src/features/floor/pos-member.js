/* features/floor/pos-member.js — خيار «رصيد اشتراك» في الكاشير
   بيجيب رصيد العميل أول ما يتحدد، وبيظهر زرار الدفع من الرصيد لو عنده رصيد. الخصم نفسه في السيرفر (member_checkout). */
(()=>{if(typeof drawPos!="function")return;const d0=drawPos;
  drawPos=function(){const P=C.P;if(P&&P.cid&&P.memFor!==P.cid&&!P.memBusy){P.memBusy=1;P.memFor=P.cid;posMemLoad(P)}if(P&&!P.cid&&P.mem){P.mem=null;P.memFor=null;if(P.pay=="member")P.pay="cash"}return d0.apply(this,arguments)};
})();
async function posMemLoad(P){try{const{data,error}=await sb.rpc("member_get",{p_customer:+P.cid});
  P.mem=!error&&data&&["active","expired"].includes(data.status)&&(+data.paid+ +data.bonus)>0?data:null;
  if(!P.mem&&P.pay=="member")P.pay="cash"}catch(e){P.mem=null}
  P.memBusy=0;if(C.P===P)drawPos()}

/* اختيار طريقة دفع فرق الرصيد (كاش / كارت / محفظة) */
function memPickDiff(amt){return new Promise(res=>{const w=document.createElement("div");w.className="dlg-bg";
  w.innerHTML=`<div class="dlg" role="alertdialog" aria-modal="true"><p>الفرق <b>${fm(amt)}</b> بيتدفع إزاي؟</p><div class="dlg-b" style="flex-wrap:wrap"><button class="btn" data-m="cash">كاش</button><button class="btn" data-m="card">كارت</button><button class="btn" data-m="wallet">محفظة</button><button class="btn g" data-m="">إلغاء</button></div></div>`;
  document.body.appendChild(w);const done=v=>{w.remove();res(v||null)};
  w.querySelectorAll("button").forEach(b=>b.onclick=()=>done(b.dataset.m));w.onclick=e=>{if(e.target===w)done(null)}})}
