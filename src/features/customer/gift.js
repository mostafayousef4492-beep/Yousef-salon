/* customer/gift.js — العميل يدخل كود كارت الهدية فيتضاف لرصيده الأساسي */
async function giftRedeem(){const c=await askInput("اكتب كود كارت الهدية","");if(c==null||!String(c).trim())return;
  const{data,error}=await sb.rpc("gift_card_redeem",{p_code:String(c)});
  if(error)return toast(error.message);
  if(!data||!data.ok)return toast((data&&data.error)||"الكود غلط");
  toast("اتضاف "+num(data.amount)+" جنيه لرصيدك 🎁");try{memOpen()}catch(e){}}
