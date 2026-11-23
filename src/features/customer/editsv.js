/* features/customer/editsv.js — العميل يعدّل خدمات تذكرته من «دوري»: يضيف أو يشيل خدمة أو يغيّر الباقة
   متاح طول ما التذكرة لسه مستنية (قبل ما الصنايعي يبدأ الخدمة). بيستخدم نفس دوال السيرفر الموجودة (set_ticket_services / set_ticket_bundle)
   والسيرفر هو اللي بيتحقق من الحالة والملكية. من غير أي تغيير في الحسابات: السعر بيتحسب زي ما هو من الخدمات والباقة. */

let ESV={id:null,b:null};

(()=>{if(typeof drawQ!="function")return;const q0=drawQ;drawQ=function(qs){q0(qs);try{
  if(!qs||!["upcoming","checked_in"].includes(qs.status)||(qs.urg&&qs.urg.state))return;
  const root=$("app");if(!root||$("esv_btn"))return;
  const b=document.createElement("button");b.id="esv_btn";b.className="btn g";b.style.cssText="width:100%;margin:10px 0";b.textContent="✏️ عدّل خدماتك";b.onclick=()=>esvOpen(qs.id);
  const first=root.querySelector(".box");first?first.after(b):root.appendChild(b)}catch(e){}}})();

async function esvOpen(id){ESV.id=id;ESV.b=null;
  const[sv,cur,bd]=await Promise.all([sb.from("services").select("*").eq("active",true).order("id"),sb.from("appointment_services").select("service_id").eq("appointment_id",id),sb.rpc("ticket_bundle",{p_id:id})]);
  if(sv.error)return toast(sv.error.message);
  C.sv=sv.data||[];await BN.load(sb);
  ESV.b={s:(cur.data||[]).map(x=>x.service_id),bd:bd&&bd.data&&bd.data.id?bd.data.id:null};
  if(!ESV.b.s.length)return toast("مش قادر أقرا خدمات تذكرتك دلوقتي، جرّب تاني");
  esvDraw()}

function esvDraw(){const b=ESV.b,sel=b.s,tot=BN.calc(b,C.sv).total;
  dsOpen("عدّل خدماتك",`<div class="box">${BN.html(b,"esvPb",fm)}<h2 style="margin-top:0">الخدمات ${sel.length?`<span class="m">✓ اخترت ${sel.length} · ${fm(tot)}</span>`:""}</h2>${SG.render(C.sv,sel,(x,s,sh)=>`<button class="chip ${s?"sel":""}" onclick="esvTog(${x.id})">${BN.star(b,x.id)}${esc(sh?SG.label(x):x.name)} · ${x.price}</button>`)}${BN.summary(b,C.sv,fm)}
<div class="m" style="margin-top:8px">التعديل متاح لحد ما الصنايعي يبدأ الخدمة. السعر بيتحسب عند الكاشير على الخدمات اللي تختارها.</div>
<button class="btn" style="width:100%;margin-top:12px" ${sel.length?"":"disabled"} onclick="esvSave()">حفظ التعديل</button><button class="btn g" style="width:100%;margin-top:8px" onclick="svcClose()">رجوع</button></div>`)}
function esvTog(id){const b=ESV.b;b.s=SG.tog(b.s,id,C.sv);BN.sync(b);esvDraw()}
function esvPb(id){BN.pick(ESV.b,id);esvDraw()}
async function esvSave(){const b=ESV.b;if(!b||!b.s.length)return;
  const{error}=await sb.rpc("set_ticket_services",{p_id:ESV.id,p_services:b.s});
  if(error)return toast(error.message);
  let ok=true;if(b.bd)ok=await BN.attach(sb,b,ESV.id);
  svcClose();toast(ok?"اتسجّل تعديل خدماتك ✓":"اتسجّلت الخدمات، بس الباقة ماتسجّلتش — قول للكاشير");V.queue()}
