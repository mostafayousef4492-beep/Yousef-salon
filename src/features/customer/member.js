/* features/customer/member.js — ABO YOUSEF MEMBERSHIP: «رصيدي» في تطبيق العميل (عرض بس)
   الرصيد الأساسي والإضافي والزيارات الأسبوعية وسجل الحركات. كله من السيرفر (member_me). مفيش أي حركة فلوس من هنا. */

const MBK={topup:"شحن رصيد",bonus_grant:"هدية",spend:"دفع خدمة",weekly_penalty:"خصم من الهدية",expire:"انتهاء الهدية",adjust:"تصحيح من الإدارة"};
const mbF=n=>Number(+n||0).toLocaleString("ar-EG",{maximumFractionDigits:2});
const mbD=s=>{try{return new Date(s+"T12:00:00").toLocaleDateString("ar-EG",{day:"numeric",month:"long"})}catch(e){return s}};

async function memOpen(){dsOpen("💳 رصيدي",`<p class="m">بنحمّل...</p>`);const{data:d,error}=await sb.rpc("member_me");
  if(error||!d)return dsOpen("💳 رصيدي",`<p class="m">${error?esc(error.message):"مفيش اشتراك على حسابك لسه. اسأل الكاشير عن باقات الرصيد."}</p>`);
  const pct=Math.min(100,Math.round(100*d.visits/Math.max(1,d.required)));
  const st={frozen:"الاشتراك مجمّد",expired:"الاشتراك منتهي: الهدية اتصفّرت ورصيدك الأساسي محفوظ",closed:"الاشتراك مقفول"}[d.status];
  dsOpen("💳 رصيدي",`<div class="box"><div class="m">${esc(d.plan)}</div><div style="font-size:30px;font-weight:700;margin:4px 0">${mbF(d.total)} <span class="m">جنيه</span></div>
<div class="row"><span>الرصيد الأساسي</span><b>${mbF(d.paid)}</b></div><div class="row"><span>رصيد الهدية</span><b>${mbF(d.bonus)}</b></div>
<div class="m">صالح لحد ${mbD(d.expires_on)}</div>${st?`<div class="m" style="color:var(--red);margin-top:6px">${st}</div>`:""}</div>
${d.status=="active"?`<div class="box" style="margin-top:10px"><b>زياراتك الأسبوع ده</b><div class="m">المطلوب ${d.required} زيارة في الأسبوع للاحتفاظ بالهدية (من ${mbD(d.week_start)} لـ ${mbD(d.week_end)})</div>
<div style="height:10px;border-radius:6px;background:var(--line,#1d2330);margin:8px 0;overflow:hidden"><i style="display:block;height:100%;width:${pct}%;background:var(--gold,#c9a35a)"></i></div>
<div class="row"><span>نفّذت</span><b>${d.visits}</b></div><div class="row"><span>باقي</span><b>${d.remaining}</b></div></div>`:""}
${d.notice?`<div class="box" style="margin-top:10px;border:1px solid var(--gold,#c9a35a)"><b>تنبيه</b><div class="m">لو ماكمّلتش ${d.notice.missing} زيارة لحد ${mbD(d.notice.ends_on)}، هيتخصم ${mbF(d.notice.penalty)} جنيه (${mbF(d.penalty_pct)}%) من رصيد الهدية بس. رصيدك الأساسي مش بيتأثر أبداً.</div></div>`:""}
<h3 style="margin-top:14px">سجل الحركات</h3>${(d.ledger||[]).length?d.ledger.map(l=>`<div class="row"><div><b>${MBK[l.kind]||l.kind}</b> <span class="tag">${l.bucket=="paid"?"أساسي":"هدية"}</span><div class="m">${new Date(l.at).toLocaleDateString("ar-EG",{day:"numeric",month:"short"})}${l.note?" · "+esc(l.note):""}</div></div><b style="color:${+l.amount<0?"var(--red)":"var(--green,#2ea66b)"}">${+l.amount>0?"+":""}${mbF(l.amount)}</b></div>`).join(""):`<p class="m">مفيش حركات.</p>`}`)}

async function memCard(){try{
  const sh=document.querySelector("#app .hm-shell");if(!sh||$("hmmem"))return;
  const{data:d,error}=await sb.rpc("member_me");if(error||!d)return;
  const sh2=document.querySelector("#app .hm-shell");if(!sh2||$("hmmem"))return;
  const el=document.createElement("div");el.id="hmmem";el.className="box";el.style.cssText="display:flex;align-items:center;gap:12px;cursor:pointer;margin-top:10px";el.setAttribute("role","button");el.tabIndex=0;el.onclick=()=>memOpen();el.onkeydown=e=>{if(e.key=="Enter"||e.key==" ")memOpen()};
  el.innerHTML=`<span style="font-size:30px;line-height:1" aria-hidden="true">💳</span><div style="flex:1"><b>رصيدي: ${mbF(d.total)} جنيه</b><div class="m">${d.notice?"⚠️ ناقصك "+d.notice.missing+" زيارة قبل "+mbD(d.notice.ends_on):(d.status=="active"?"زياراتك الأسبوع ده "+d.visits+" من "+d.required:"اضغط للتفاصيل")}</div></div>`;
  const h=sh2.querySelector(".hm-head"),live=sh2.querySelector(".hm-live");(live||h)?(live||h).after(el):sh2.prepend(el)}catch(e){}}
(()=>{if(window.SALON_MODE!=="customer")return;const q=typeof V!="undefined"&&V.hm;if(!q)return;V.hm=async()=>{await q();memCard()}})();
