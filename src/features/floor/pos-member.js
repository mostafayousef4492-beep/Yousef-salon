/* features/floor/pos-member.js — خيار «رصيد اشتراك» في الكاشير
   بيجيب رصيد العميل أول ما يتحدد، وبيظهر زرار الدفع من الرصيد لو عنده رصيد. الخصم نفسه في السيرفر (member_checkout). */
(()=>{if(typeof drawPos!="function")return;const d0=drawPos;
  drawPos=function(){const P=C.P;if(P&&P.cid&&P.memFor!==P.cid&&!P.memBusy){P.memBusy=1;P.memFor=P.cid;posMemLoad(P)}if(P&&!P.cid&&P.mem){P.mem=null;P.memFor=null;if(P.pay=="member")P.pay="cash"}return d0.apply(this,arguments)};
})();
async function posMemLoad(P){try{const{data,error}=await sb.rpc("member_get",{p_customer:+P.cid});
  P.mem=!error&&data&&["active","expired"].includes(data.status)&&(+data.paid+ +data.bonus)>0?data:null;
  if(!P.mem&&P.pay=="member")P.pay="cash"}catch(e){P.mem=null}
  P.memBusy=0;if(C.P===P)drawPos()}
