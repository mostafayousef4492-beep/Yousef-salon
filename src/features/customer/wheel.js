/* features/customer/wheel.js — عجلة الحظ: العميل بيلف (أول لفة مجانية بعدها بنقاط) والإدارة بتظبط القطاعات
   النتيجة بتتحدد في السيرفر (wheel_spin) والحركة بس هي اللي بتتعمل هنا. الجايزة كود بيطبّقه الكاشير زي أي كود استبدال. */

let WH={st:null,busy:false,rot:0};

function whSvg(sl){const n=sl.length||1,R=140,cx=150,cy=150,cols=["#c9a35a","#1d2330","#e2c27d","#2b3344"];
  const P=(a)=>{const r=(a-90)*Math.PI/180;return [cx+R*Math.cos(r),cy+R*Math.sin(r)]};
  const seg=sl.map((s,i)=>{const a0=i*360/n,a1=(i+1)*360/n,[x0,y0]=P(a0),[x1,y1]=P(a1),mid=(a0+a1)/2,[tx,ty]=[cx+R*0.62*Math.cos((mid-90)*Math.PI/180),cy+R*0.62*Math.sin((mid-90)*Math.PI/180)],dark=i%2==1,txt=dark?"#f3e7c9":"#1a1408";
    const path=n==1?`<circle cx="${cx}" cy="${cy}" r="${R}" fill="${cols[0]}"/>`:`<path d="M${cx},${cy} L${x0.toFixed(1)},${y0.toFixed(1)} A${R},${R} 0 ${a1-a0>180?1:0} 1 ${x1.toFixed(1)},${y1.toFixed(1)} Z" fill="${cols[i%2]}" stroke="#0b0e14" stroke-width="1.5"/>`;
    return path+`<text x="${tx.toFixed(1)}" y="${ty.toFixed(1)}" fill="${txt}" font-size="${n>6?10:12}" font-weight="700" text-anchor="middle" dominant-baseline="middle" transform="rotate(${mid} ${tx.toFixed(1)} ${ty.toFixed(1)})">${esc(String(s.label).slice(0,14))}</text>`}).join("");
  return `<div style="position:relative;width:min(300px,80vw);margin:6px auto"><svg viewBox="0 0 300 300" role="img" aria-label="عجلة الحظ" style="width:100%;display:block"><g id="wh_g" style="transform-origin:150px 150px;transform:rotate(${WH.rot}deg)">${seg}</g><circle cx="150" cy="150" r="16" fill="#0b0e14" stroke="#c9a35a" stroke-width="3"/></svg><div style="position:absolute;top:-6px;left:50%;transform:translateX(-50%);width:0;height:0;border-left:11px solid transparent;border-right:11px solid transparent;border-top:22px solid #e5484d;filter:drop-shadow(0 2px 2px rgba(0,0,0,.5))"></div></div>`}

async function wheelOpen(){dsOpen("🎡 عجلة الحظ",`<p class="m">بنحمّل...</p>`);const{data,error}=await sb.rpc("wheel_status");
  if(error)return dsOpen("🎡 عجلة الحظ",`<p class="m">${/wheel_status|PGRST202|42883/.test(error.code+" "+error.message)?"الميزة دي لسه مش متفعّلة":esc(error.message)}</p>`);
  WH.st=data;if(!data||!data.on)return dsOpen("🎡 عجلة الحظ",`<p class="m">عجلة الحظ مش شغّالة دلوقتي. تابعنا، قريب هتتفتح!</p>`);wheelDraw()}

function wheelDraw(res){const s=WH.st,can=!WH.busy&&s.left_today>0&&(s.free||+s.points>=+s.cost);
  const sub=s.free?`<b style="color:var(--gold,#c9a35a)">لفتك الأولى مجانية 🎁</b>`:`اللفة بـ <b>${num(s.cost)}</b> نقطة · رصيدك <b>${num(s.points)}</b>`;
  const why=s.left_today<=0?"خلّصت لفّات النهارده، جرّب بكرة":(!s.free&&+s.points<+s.cost?"نقاطك مش كفاية للفة دلوقتي":"");
  dsOpen("🎡 عجلة الحظ",`<div style="text-align:center">${whSvg(s.slices||[])}<div class="m" style="margin:8px 0">${sub}</div>
<button class="btn" style="width:100%" ${can?"":"disabled"} onclick="wheelGo()">${WH.busy?"بتلف...":(s.free?"لفّ مجانًا":"لفّ العجلة")}</button>${why?`<div class="m" style="margin-top:8px">${why}</div>`:""}
<div id="wh_res" style="margin-top:12px">${res||""}</div><div class="m" style="margin-top:10px">الجوايز أكواد بتطبّقها على فاتورتك في الصالون، وبتلاقيها في «استبدل نقاطك».</div></div>`)}

async function wheelGo(){if(WH.busy)return;WH.busy=true;wheelDraw();
  const{data,error}=await sb.rpc("wheel_spin");
  if(error){WH.busy=false;toast(error.message);return wheelOpen()}
  const n=(WH.st.slices||[]).length||1,step=360/n,target=360*5+(360-(data.index+0.5)*step),red=window.matchMedia&&matchMedia("(prefers-reduced-motion: reduce)").matches;
  const g=$("wh_g");if(g){g.style.transition=red?"none":"transform 4.2s cubic-bezier(.12,.7,.1,1)";WH.rot=(Math.floor(WH.rot/360)*360)+target;g.style.transform=`rotate(${WH.rot}deg)`}
  setTimeout(()=>{WH.busy=false;WH.st.free=false;WH.st.points=data.points;WH.st.left_today=Math.max(0,(WH.st.left_today||1)-1);
    const html=data.win?`<div class="box" style="border-color:var(--gold,#c9a35a)"><div style="font-size:18px;font-weight:700">🎉 كسبت: ${esc(data.label)}</div><div class="m" style="margin:6px 0">كودك — وريه للكاشير:</div><div dir="ltr" style="font-size:26px;font-weight:700;letter-spacing:3px">${esc(data.code)}</div></div>`:`<div class="box"><b>${esc(data.label)}</b><div class="m">جرّب تاني، الحظ جاي!</div></div>`;
    wheelDraw(html)},red?50:4300)}

/* ===== إدارة العجلة (للمدير/المالك) ===== */
async function wheelAdmin(){dsOpen("🎡 عجلة الحظ — الإدارة",`<p class="m">بنحمّل...</p>`);
  const[a,b,c]=await Promise.all([sb.from("wheel_slices").select("*").order("sort").order("id"),sb.from("loyalty_rewards").select("id,name,kind,value,active").eq("active",true).not("name","like","استبدال نقاط:%").order("cost"),sb.rpc("wheel_report",{p_days:30})]);
  if(a.error)return dsOpen("🎡 عجلة الحظ — الإدارة",`<p class="m">${/wheel_slices|42P01|PGRST205/.test(a.error.code+" "+a.error.message)?"الميزة لسه مش متفعّلة: شغّل patch_lucky_wheel.sql في Supabase الأول.":esc(a.error.message)}</p>`);
  const S=a.data||[],R=b.data||[],rep=c.data||{},tot=S.filter(x=>x.active).reduce((t,x)=>t+(+x.weight||0),0);
  C.whR=R;
  dsOpen("🎡 عجلة الحظ — الإدارة",`<p class="m">نسبة كل قطاع = وزنه ÷ مجموع الأوزان. القيم التانية (التكلفة، اللفة المجانية، الحدود، التشغيل) من الإعدادات ← الولاء.</p>
<div class="m" style="margin:8px 0">آخر 30 يوم: <b>${num(rep.spins||0)}</b> لفة · <b>${num(rep.prizes||0)}</b> جايزة · <b>${num(rep.points_collected||0)}</b> نقطة اتحصّلت</div>
${S.map(x=>{const pc=tot>0&&x.active?Math.round(100*x.weight/tot):0;return `<div class="row" style="flex-wrap:wrap;gap:6px"><input id="ws_l${x.id}" value="${esc(x.label)}" style="flex:1;min-width:110px"><select id="ws_r${x.id}"><option value="">بدون جايزة (حظ أوفر)</option>${R.map(r=>`<option value="${r.id}" ${r.id==x.reward_id?"selected":""}>${esc(r.name)}</option>`).join("")}</select><input id="ws_w${x.id}" type="number" min="0" value="${x.weight}" style="width:70px" title="الوزن"><span class="m" style="min-width:42px">${pc}%</span><label class="m"><input type="checkbox" id="ws_a${x.id}" ${x.active?"checked":""}> شغّال</label><button class="btn s" onclick="wheelSave(${x.id})">حفظ</button><button class="btn s g" onclick="wheelDel(${x.id})">مسح</button></div>`}).join("")||`<p class="m">مفيش قطاعات.</p>`}
<button class="btn g" style="margin-top:10px" onclick="wheelAdd()">+ قطاع جديد</button>`)}

async function wheelSave(id){const rid=$("ws_r"+id).value,{error}=await sb.from("wheel_slices").update({label:$("ws_l"+id).value.trim()||"—",reward_id:rid?+rid:null,weight:Math.max(0,parseInt($("ws_w"+id).value)||0),active:$("ws_a"+id).checked}).eq("id",id);error?toast(error.message):(toast("اتحفظ ✓"),wheelAdmin())}
async function wheelAdd(){const{error}=await sb.from("wheel_slices").insert({label:"قطاع جديد",weight:1,sort:99});error?toast(error.message):wheelAdmin()}
async function wheelDel(id){if(!await askConfirm("تمسح القطاع ده؟"))return;const{error}=await sb.from("wheel_slices").delete().eq("id",id);error?toast(/foreign|23503/.test(error.message)?"مينفعش تمسحه، وقّفه بدل المسح":error.message):wheelAdmin()}

/* ===== كارت العجلة في الصفحة الأولى للعميل ===== */
async function wheelCard(){
  try{
    const sh=document.querySelector("#app .hm-shell");if(!sh||$("hmwheel"))return;
    const{data:s,error}=await sb.rpc("wheel_status");if(error||!s||!s.on)return;
    const sh2=document.querySelector("#app .hm-shell");if(!sh2||$("hmwheel"))return;
    const can=s.left_today>0&&(s.free||+s.points>=+s.cost);
    const d=document.createElement("div");d.id="hmwheel";d.className="box";d.style.cssText="display:flex;align-items:center;gap:12px;cursor:pointer;margin-top:10px";d.setAttribute("role","button");d.tabIndex=0;d.onclick=()=>wheelOpen();d.onkeydown=e=>{if(e.key=="Enter"||e.key==" ")wheelOpen()};
    d.innerHTML=`<span style="font-size:34px;line-height:1" aria-hidden="true">🎡</span><div style="flex:1"><b>${s.free?"لفتك المجانية جاهزة!":"عجلة الحظ"}</b><div class="m">${s.free?"لفّ واكسب خصم أو خدمة":(can?"لفّ بـ "+num(s.cost)+" نقطة واكسب خصم أو خدمة":(s.left_today<=0?"خلّصت لفّات النهارده":"محتاج "+num(s.cost)+" نقطة للفة"))}</div></div><span class="btn s">${s.free?"لفّ مجانًا":"افتح"}</span>`;
    const h=sh2.querySelector(".hm-head"),live=sh2.querySelector(".hm-live");(live||h)?(live||h).after(d):sh2.prepend(d);
  }catch(e){}
}
(()=>{if(window.SALON_MODE!=="customer")return;const q=typeof V!="undefined"&&V.hm;if(!q)return;V.hm=async()=>{await q();wheelCard()}})();
