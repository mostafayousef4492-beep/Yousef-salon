/* money/gift.js — بيع كروت الهدايا (كاشير/مدير) + قايمة الكروت والالتزام (مدير) */
async function giftAdmin(){dsOpen("🎁 كروت الهدايا",`<p class="m">بنحمّل...</p>`);
  const adm=isAdm(me);let L=null;if(adm){const r=await sb.rpc("gift_card_list");if(!r.error)L=r.data}
  const ST={active:"متاح",redeemed:"اتستخدم",void:"ملغي"};
  dsOpen("🎁 كروت الهدايا",`<div class="box"><b>بيع كارت</b><input id="gf_a" type="number" inputmode="numeric" placeholder="المبلغ (50 – 10000)" style="margin-top:6px"><select id="gf_m" style="margin-top:6px"><option value="cash">كاش (يدخل الدرج)</option><option value="card">كارت</option><option value="wallet">محفظة</option></select><button class="btn s" style="margin-top:6px" onclick="giftSell()">بيع وطلّع الكود</button><div id="gf_res"></div></div>
${L?`<div class="box" style="margin-top:10px"><div class="row"><span>كروت متاحة</span><b>${L.count_active}</b></div><div class="row"><span>التزام قائم</span><b>${num(L.outstanding)}</b></div><div class="m">الكارت ده فلوس اتقبضت ولسه ماتخدمتش، مش إيراد لحد ما العميل يصرفها.</div></div>
<h3>آخر الكروت</h3>${(L.rows||[]).length?L.rows.map(g=>`<div class="row"><div><b>${esc(g.code.slice(0,2))}••••••${esc(g.code.slice(8))}</b> <span class="tag">${ST[g.status]||g.status}</span><div class="m">${new Date(g.created_at).toLocaleDateString("ar-EG",{day:"numeric",month:"short"})}${g.redeemed_by?" · "+esc(g.redeemed_by):""}</div></div><div style="text-align:left"><b>${num(g.amount)}</b>${g.status=="active"?`<div><button class="btn g" onclick="giftVoid(${g.id})">إلغاء</button></div>`:""}</div></div>`).join(""):`<p class="m">مفيش كروت.</p>`}`:""}`)}
async function giftSell(){const a=+$("gf_a").value,m=$("gf_m").value;if(!(a>=50))return toast("المبلغ من 50 جنيه");
  if(!await askConfirm(`بيع كارت هدية بـ ${num(a)} جنيه (${{cash:"كاش",card:"كارت",wallet:"محفظة"}[m]})؟`))return;
  const{data,error}=await sb.rpc("gift_card_sell",{p_amount:a,p_method:m});if(error)return toast(error.message);
  $("gf_res").innerHTML=`<div class="box" style="margin-top:8px;text-align:center"><div class="m">الكود (سلّمه للعميل، مش هيظهر تاني)</div><div style="font-size:26px;font-weight:700;letter-spacing:3px;direction:ltr;user-select:all">${esc(data.code)}</div><div class="m">${num(data.amount)} جنيه</div></div>`;
  try{await navigator.clipboard.writeText(data.code)}catch(e){}}
async function giftVoid(id){const r=await askInput("سبب إلغاء الكارت","");if(!r||String(r).trim().length<3)return;
  const{error}=await sb.rpc("gift_card_void",{p_id:id,p_reason:String(r)});error?toast(error.message):(toast("اتلغى ✓"),giftAdmin())}
