/* features/customer/challenge.js — ABO YOUSEF CHALLENGE: عجلة التحدي (مستقلة عن عجلة الحظ)
   العميل بيلف ويشوف التحدي ونقاطه قبل ما يوافق. التنفيذ جوه الصالون، وصنايعي العميل بيأكّد من تابلت الصنايعية، وبعدها بس النقاط بتتضاف.
   النتيجة بتتحدد في السيرفر (challenge_spin) والحركة بس هنا. التحديات اختيارية وبموافقة العميل. */

let CH={st:null,busy:false,rot:0,res:null};
const CH_RAR={common:["عادي","#8a94a6"],rare:["نادر","#4c8dff"],legend:["أسطوري","#e5b94e"]};
const CH_SEG=["common","rare","common","legend","common","rare","common","rare"]; // شكل العجلة: القطاعات بلون الندرة من غير أسماء (سر)
const CH_COL={common:"#2b3344",rare:"#2f5fb3",legend:"#c9a35a"};

function chTick(){try{if(window.matchMedia&&matchMedia("(prefers-reduced-motion: reduce)").matches)return;const A=CH.ac||(CH.ac=new (window.AudioContext||window.webkitAudioContext)()),o=A.createOscillator(),g=A.createGain();o.type="square";o.frequency.value=520;g.gain.value=0.02;o.connect(g);g.connect(A.destination);o.start();o.stop(A.currentTime+0.025)}catch(e){}}

function chSvg(){const n=CH_SEG.length,R=140,cx=150,cy=150,P=a=>{const r=(a-90)*Math.PI/180;return[cx+R*Math.cos(r),cy+R*Math.sin(r)]};
  const seg=CH_SEG.map((r,i)=>{const a0=i*360/n,a1=(i+1)*360/n,[x0,y0]=P(a0),[x1,y1]=P(a1),mid=(a0+a1)/2,tx=cx+R*0.64*Math.cos((mid-90)*Math.PI/180),ty=cy+R*0.64*Math.sin((mid-90)*Math.PI/180);
    return `<path d="M${cx},${cy} L${x0.toFixed(1)},${y0.toFixed(1)} A${R},${R} 0 0 1 ${x1.toFixed(1)},${y1.toFixed(1)} Z" fill="${CH_COL[r]}" stroke="#05070b" stroke-width="2"/><text x="${tx.toFixed(1)}" y="${ty.toFixed(1)}" fill="${r=="legend"?"#1a1408":"#f3e7c9"}" font-size="26" font-weight="700" text-anchor="middle" dominant-baseline="middle">؟</text>`}).join("");
  return `<div style="position:relative;width:min(300px,78vw);margin:10px auto"><svg viewBox="0 0 300 300" role="img" aria-label="عجلة التحدي" style="width:100%;display:block;filter:drop-shadow(0 0 18px rgba(201,163,90,.35))"><circle cx="150" cy="150" r="146" fill="none" stroke="#c9a35a" stroke-width="4"/><g id="ch_g" style="transform-origin:150px 150px;transform:rotate(${CH.rot}deg)">${seg}</g><circle cx="150" cy="150" r="18" fill="#05070b" stroke="#c9a35a" stroke-width="3"/></svg><div style="position:absolute;top:-6px;left:50%;transform:translateX(-50%);width:0;height:0;border-left:11px solid transparent;border-right:11px solid transparent;border-top:22px solid #e5484d"></div></div>`}

function chShell(inner){let o=$("ch_ov");if(!o){o=document.createElement("div");o.id="ch_ov";o.style.cssText="position:fixed;inset:0;z-index:99998;background:#05070b;color:#f4f1ea;overflow:auto;padding:14px 16px calc(24px + env(safe-area-inset-bottom))";o.setAttribute("role","dialog");o.setAttribute("aria-modal","true");document.body.appendChild(o)}
  o.innerHTML=`<div style="max-width:460px;margin:0 auto;text-align:center"><div style="display:flex;justify-content:space-between;align-items:center"><b style="color:#c9a35a;font-size:20px">ABO YOUSEF CHALLENGE</b><button class="btn s g" onclick="chClose()">✕ إغلاق</button></div>${inner}</div>`}
function chClose(){const o=$("ch_ov");if(o)o.remove();if(typeof V!="undefined"&&tab=="hm"&&typeof go=="function")try{V.hm()}catch(e){}}

async function chOpen(){chShell(`<p style="color:#9aa0ab;margin-top:40px">بنحمّل...</p>`);const{data,error}=await sb.rpc("challenge_status");
  if(error)return chShell(`<p style="margin-top:40px">${/challenge_status|PGRST202|42883/.test(error.code+" "+error.message)?"الميزة دي لسه مش متفعّلة":esc(error.message)}</p>`);
  CH.st=data;CH.res=null;if(!data||!data.on)return chShell(`<p style="margin-top:40px;color:#9aa0ab">عجلة التحدي مش شغّالة دلوقتي. قريب هتتفتح!</p>`);chDraw()}

function chLevel(){const L=CH.st.level||{},e=+CH.st.earned||0;let bar="";if(L.next_at){const pct=Math.min(100,Math.round(100*e/L.next_at));bar=`<div style="height:8px;border-radius:6px;background:#1d2330;margin:8px 0;overflow:hidden"><i style="display:block;height:100%;width:${pct}%;background:#c9a35a"></i></div><div style="font-size:13px;color:#9aa0ab">${num(e)} / ${num(L.next_at)} للمستوى «${esc(L.next_name)}»</div>`}else bar=`<div style="font-size:13px;color:#9aa0ab">وصلت لأعلى مستوى 👑</div>`;
  return `<div style="margin:10px 0"><div style="font-size:15px;color:#9aa0ab">مستواك</div><b style="font-size:22px;color:#e5b94e">${esc(L.name||"مبتدئ")}</b>${bar}</div>`}

function chCard(c,extra){const r=CH_RAR[c.rarity]||CH_RAR.common;return `<div style="border:2px solid ${r[1]};border-radius:18px;padding:16px;margin:12px 0;background:#0d1117"><div style="display:inline-block;padding:2px 12px;border-radius:12px;background:${r[1]};color:#05070b;font-weight:700;font-size:14px">${r[0]}</div><div style="font-size:21px;font-weight:700;margin:10px 0">${esc(c.title)}</div><div style="font-size:16px;color:#e5b94e">مكافأتك: <b>${num(c.points)} نقطة</b></div>${extra||""}</div>`}

function chDraw(){const s=CH.st,c=s.current;let body="";
  if(c&&c.status=="offered")body=chCard(c,`<div style="font-size:13px;color:#9aa0ab;margin-top:8px">التحدي اختياري، ومفيش إحراج: تقدر ترفض.</div>`)+`<button class="btn" style="width:100%" onclick="chAccept(${c.id})">أوافق على التحدي</button><button class="btn g" style="width:100%;margin-top:8px" onclick="chDecline(${c.id})">مش دلوقتي</button>`;
  else if(c&&c.status=="accepted")body=chCard(c,`<div style="margin-top:8px;color:#9aa0ab">نفّذ التحدي قدام الحلاق بتاعك، وهو هيأكّد من تابلت الصنايعية وتتضاف نقاطك. صالح لعدد ساعات محدد.</div>`);
  else{const blocked=s.need_visit&&!s.here,noLeft=s.left_today<=0,lowPts=+s.cost>0&&+s.points<+s.cost,can=!CH.busy&&!blocked&&!noLeft&&!lowPts;
    const why=blocked?"اللعبة بتتفتح لما توصل الصالون ويتسجّل حضورك":noLeft?"خلّصت لفّات النهارده، جرّب بكرة":lowPts?"نقاطك مش كفاية للفة (محتاج "+num(s.cost)+" نقطة)":"";
    body=chSvg()+`<button class="btn" style="width:100%;font-size:20px;padding:16px" ${can?"":"disabled"} onclick="chSpin()">${CH.busy?"بتلف...":"أنا قد التحدي 🔥"}</button>${why?`<div style="margin-top:8px;color:#9aa0ab;font-size:14px">${why}</div>`:""}${+s.cost>0?`<div style="margin-top:6px;color:#9aa0ab;font-size:13px">اللفة بـ ${num(s.cost)} نقطة</div>`:""}`}
  chShell(chLevel()+body+`<div style="margin-top:14px;font-size:12px;color:#6f7787">التحديات خفيفة وبموافقتك، ومفيش تصوير أو نشر من غير إذنك، ومفيش حاجة مؤذية أو دايمة.</div>`)}

async function chSpin(){if(CH.busy)return;CH.busy=true;chDraw();
  const{data,error}=await sb.rpc("challenge_spin");
  if(error){CH.busy=false;toast(error.message);return chOpen()}
  const idx=[];CH_SEG.forEach((r,i)=>{if(r==data.rarity)idx.push(i)});const pick=idx.length?idx[Math.floor(Math.random()*idx.length)]:0,n=CH_SEG.length,step=360/n,target=360*5+(360-(pick+0.5)*step),red=window.matchMedia&&matchMedia("(prefers-reduced-motion: reduce)").matches,D=red?0:4200;
  const g=$("ch_g");if(g){g.style.transition=red?"none":"transform 4.2s cubic-bezier(.12,.7,.1,1)";CH.rot=(Math.floor(CH.rot/360)*360)+target;g.style.transform=`rotate(${CH.rot}deg)`}
  if(!red){const N=26;for(let k=1;k<=N;k++)setTimeout(chTick,D*(1-Math.pow(1-k/N,2)))}
  setTimeout(()=>{CH.busy=false;CH.st.current={id:data.id,title:data.title,rarity:data.rarity,points:data.points,status:"offered"};CH.st.left_today=Math.max(0,(CH.st.left_today||1)-1);try{navigator.vibrate&&navigator.vibrate(data.rarity=="legend"?[80,40,80,40,160]:40)}catch(e){}chDraw()},D+150)}

async function chAccept(id){const{error}=await sb.rpc("challenge_accept",{p_id:id});if(error)return toast(error.message);CH.st.current.status="accepted";toast("اتسجّل ✓ وريه للحلاق");chDraw()}
async function chDecline(id){const{error}=await sb.rpc("challenge_decline",{p_id:id});if(error)return toast(error.message);CH.st.current=null;chOpen()}

/* ===== كارت في الصفحة الأولى ===== */
async function chCard2(){
  try{const sh=document.querySelector("#app .hm-shell");if(!sh||$("hmch"))return;
    const{data:s,error}=await sb.rpc("challenge_status");if(error||!s||!s.on)return;
    const sh2=document.querySelector("#app .hm-shell");if(!sh2||$("hmch"))return;
    const c=s.current,L=s.level||{};
    const d=document.createElement("div");d.id="hmch";d.className="box";d.style.cssText="display:flex;align-items:center;gap:12px;cursor:pointer;margin-top:10px;background:#05070b;border:1px solid #c9a35a";d.setAttribute("role","button");d.tabIndex=0;d.onclick=()=>chOpen();d.onkeydown=e=>{if(e.key=="Enter"||e.key==" ")chOpen()};
    d.innerHTML=`<span style="font-size:32px;line-height:1" aria-hidden="true">🎯</span><div style="flex:1;color:#f4f1ea"><b>ABO YOUSEF CHALLENGE</b><div style="font-size:13px;color:#9aa0ab">${c?(c.status=="accepted"?"عندك تحدي مقبول — نفّذه قدام الحلاق":"عندك تحدي مستنيك"):"مستواك: "+esc(L.name||"مبتدئ")+" · لفّ واكسب نقاط"}</div></div><span class="btn s">${c?"افتح":"أنا قد التحدي"}</span>`;
    const h=sh2.querySelector(".hm-head"),live=sh2.querySelector(".hm-live"),w=$("hmwheel");const a=w||live||h;a?a.after(d):sh2.prepend(d)}catch(e){}}
(()=>{if(window.SALON_MODE!=="customer")return;const q=typeof V!="undefined"&&V.hm;if(!q)return;V.hm=async()=>{await q();chCard2()}})();

/* ===== إدارة التحديات (للمدير/المالك) ===== */
async function challengeAdmin(){dsOpen("🎯 عجلة التحدي — الإدارة",`<p class="m">بنحمّل...</p>`);
  const[a,b,r]=await Promise.all([sb.from("challenge_defs").select("*").order("sort").order("id"),sb.from("challenge_levels").select("*").order("min_points"),sb.rpc("challenge_report",{p_days:30})]);
  if(a.error)return dsOpen("🎯 عجلة التحدي — الإدارة",`<p class="m">${/challenge_defs|42P01|PGRST205/.test(a.error.code+" "+a.error.message)?"الميزة لسه مش متفعّلة: شغّل patch_challenge_wheel.sql في Supabase الأول.":esc(a.error.message)}</p>`);
  const D=a.data||[],Lv=b.data||[],rep=r.data||{},tot=D.filter(x=>x.active).reduce((t,x)=>t+(+x.weight||0),0);
  const K=[["fun","ترفيهي"],["barber","حلاقة"],["surprise","مفاجأة"]],RR=[["common","عادي"],["rare","نادر"],["legend","أسطوري"]];
  const opt=(L,v)=>L.map(x=>`<option value="${x[0]}" ${x[0]==v?"selected":""}>${x[1]}</option>`).join("");
  dsOpen("🎯 عجلة التحدي — الإدارة",`<p class="m">التشغيل والحدود (لفات اليوم، سقف النقاط الشهري، الصلاحية) من الإعدادات ← المكافآت والولاء. النقاط نقاط ولاء عادية بتتضاف بعد تأكيد الحلاق من التابلت.</p>
<div class="m" style="margin:8px 0">آخر 30 يوم: <b>${num(rep.spins||0)}</b> لفة · <b>${num(rep.done||0)}</b> اتنفّذ · <b>${num(rep.points_given||0)}</b> نقطة اتوزّعت · <b>${num(rep.pending||0)}</b> مستني تأكيد</div>
<h3>التحديات (نسبة الظهور = وزن التحدي ÷ مجموع الأوزان)</h3>
${D.map(x=>`<div class="row" style="flex-wrap:wrap;gap:6px"><input id="cd_t${x.id}" value="${esc(x.title)}" style="flex:1;min-width:150px"><select id="cd_k${x.id}">${opt(K,x.kind)}</select><select id="cd_r${x.id}">${opt(RR,x.rarity)}</select><input id="cd_p${x.id}" type="number" min="0" value="${x.points}" style="width:70px" title="النقاط"><input id="cd_w${x.id}" type="number" min="0" value="${x.weight}" style="width:60px" title="الوزن"><span class="m" style="min-width:40px">${tot>0&&x.active?(100*x.weight/tot).toFixed(1):0}%</span><label class="m"><input type="checkbox" id="cd_a${x.id}" ${x.active?"checked":""}> شغّال</label><button class="btn s" onclick="chdSave(${x.id})">حفظ</button><button class="btn s g" onclick="chdDel(${x.id})">مسح</button></div>`).join("")||`<p class="m">مفيش تحديات.</p>`}
<button class="btn g s" style="margin-top:8px" onclick="chdAdd()">+ تحدي جديد</button>
<h3 style="margin-top:16px">المستويات (حسب نقاط التحديات المؤكّدة)</h3>
${Lv.map(x=>`<div class="row" style="gap:6px"><input id="cl_n${x.id}" value="${esc(x.name)}" style="flex:1"><input id="cl_m${x.id}" type="number" min="0" value="${x.min_points}" style="width:90px"><button class="btn s" onclick="chlSave(${x.id})">حفظ</button><button class="btn s g" onclick="chlDel(${x.id})">مسح</button></div>`).join("")}
<button class="btn g s" style="margin-top:8px" onclick="chlAdd()">+ مستوى جديد</button>`)}
async function chdSave(id){const{error}=await sb.from("challenge_defs").update({title:$("cd_t"+id).value.trim()||"—",kind:$("cd_k"+id).value,rarity:$("cd_r"+id).value,points:Math.max(0,parseInt($("cd_p"+id).value)||0),weight:Math.max(0,parseInt($("cd_w"+id).value)||0),active:$("cd_a"+id).checked}).eq("id",id);error?toast(error.message):(toast("اتحفظ ✓"),challengeAdmin())}
async function chdAdd(){const{error}=await sb.from("challenge_defs").insert({title:"تحدي جديد",kind:"fun",rarity:"common",points:10,weight:1,sort:999});error?toast(error.message):challengeAdmin()}
async function chdDel(id){if(!await askConfirm("تمسح التحدي ده؟ (السجل القديم بيفضل)"))return;const{error}=await sb.from("challenge_defs").delete().eq("id",id);error?toast(error.message):challengeAdmin()}
async function chlSave(id){const{error}=await sb.from("challenge_levels").update({name:$("cl_n"+id).value.trim()||"—",min_points:Math.max(0,parseInt($("cl_m"+id).value)||0)}).eq("id",id);error?toast(error.message):(toast("اتحفظ ✓"),challengeAdmin())}
async function chlAdd(){const{error}=await sb.from("challenge_levels").insert({name:"مستوى جديد",min_points:1000,sort:99});error?toast(error.message):challengeAdmin()}
async function chlDel(id){if(!await askConfirm("تمسح المستوى ده؟"))return;const{error}=await sb.from("challenge_levels").delete().eq("id",id);error?toast(error.message):challengeAdmin()}
