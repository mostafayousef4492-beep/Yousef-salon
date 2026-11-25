/* customer/store.js — المتجر: العميل يحجز منتج ويستلمه ويدفع عند الكاشير */
const STS={pending:"في الانتظار",ready:"جاهز للاستلام",picked:"اتسلّم",cancelled:"ملغي"};
async function storeOpen(){dsOpen("🛍️ المتجر",`<p class="m">بنحمّل...</p>`);
  const[a,b]=await Promise.all([sb.rpc("store_list"),sb.rpc("store_my")]);
  if(a.error)return dsOpen("🛍️ المتجر",`<p class="m">${esc(a.error.message)}</p>`);
  const L=a.data||[],M=b.data||[];
  dsOpen("🛍️ المتجر",`<p class="m">احجز المنتج وهنجهزهولك. بتستلمه وبتدفع في الصالون.</p>
${L.length?L.map(p=>`<div class="row"><div><b>${esc(p.name)}</b><div class="m">${num(p.price)} جنيه · متاح ${p.stock}</div></div><button class="btn s" onclick="storeReserve(${p.id},${JSON.stringify(p.name).replace(/"/g,"&quot;")})">احجز</button></div>`).join(""):`<p class="m">مفيش منتجات متاحة دلوقتي.</p>`}
${M.length?`<h3 style="margin-top:14px">حجوزاتك</h3>${M.map(r=>`<div class="row"><div><b>${esc(r.name)} × ${r.qty}</b><div class="m">${STS[r.status]||r.status} · ${num(r.price*r.qty)} جنيه</div></div>${r.status=="pending"||r.status=="ready"?`<button class="btn g" onclick="storeCancel(${r.id})">إلغاء</button>`:""}</div>`).join("")}`:""}`)}
async function storeReserve(id,name){const q=await askInput("الكمية (من 1 لـ 5)","1");if(q==null)return;const n=parseInt(q);if(!(n>=1&&n<=5))return toast("الكمية من 1 لـ 5");
  const{error}=await sb.rpc("store_reserve",{p_product:id,p_qty:n});error?toast(error.message):(toast("اتحجز ✓ هنكلمك لما يجهز"),storeOpen())}
async function storeCancel(id){if(!await askConfirm("إلغاء الحجز؟"))return;const{error}=await sb.rpc("store_cancel",{p_id:id});error?toast(error.message):(toast("اتلغى"),storeOpen())}
async function storeCard(){try{const sh=document.querySelector("#app .hm-shell");if(!sh||$("hmstore"))return;
  const{data,error}=await sb.rpc("store_list");if(error||!data||!data.length)return;
  const s2=document.querySelector("#app .hm-shell");if(!s2||$("hmstore"))return;
  const el=document.createElement("div");el.id="hmstore";el.className="box";el.style.cssText="display:flex;align-items:center;gap:12px;cursor:pointer;margin-top:10px";el.setAttribute("role","button");el.tabIndex=0;el.onclick=()=>storeOpen();el.onkeydown=e=>{if(e.key=="Enter"||e.key==" ")storeOpen()};
  el.innerHTML=`<span style="font-size:30px;line-height:1" aria-hidden="true">🛍️</span><div style="flex:1"><b>المتجر</b><div class="m">احجز منتجات العناية واستلمها من الصالون</div></div>`;
  const anchor=$("hmmem")||s2.querySelector(".hm-live")||s2.querySelector(".hm-head");anchor?anchor.after(el):s2.prepend(el)}catch(e){}}
(()=>{if(window.SALON_MODE!=="customer")return;const q=typeof V!="undefined"&&V.hm;if(!q)return;V.hm=async()=>{await q();storeCard()}})();
