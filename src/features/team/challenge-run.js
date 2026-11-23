/* features/team/challenge-run.js — عجلة التحدي (ABO YOUSEF CHALLENGE) من تابلت الصنايعي أو حساب الموظف
   الموظف بيلف على عميل حاضر عنده تذكرة، بيعرض عليه التحدي ونقاطه، وبيسجّل موافقة العميل، وبعد التنفيذ بيأكّد وتتضاف النقاط.
   النتيجة بتتحدد في السيرفر (challenge_spin). الملف ده مستقل (محتاج sb و $ و esc و toast بس). */

const CHR={ac:null,rot:0,busy:false,appt:null,name:"",row:null,cur:null,big:false};
const CHR_RAR={common:["عادي","#8a94a6"],rare:["نادر","#4c8dff"],legend:["أسطوري","#e5b94e"]};
const CHR_SEG=["common","rare","common","legend","common","rare","common","rare"];
const CHR_COL={common:"#2b3344",rare:"#2f5fb3",legend:"#c9a35a"};
const chrN=n=>Number(Math.round(+n||0)).toLocaleString("ar-EG");
const chrRed=()=>!!(window.matchMedia&&matchMedia("(prefers-reduced-motion: reduce)").matches);

function chrTick(){try{if(chrRed())return;const A=CHR.ac||(CHR.ac=new (window.AudioContext||window.webkitAudioContext)()),o=A.createOscillator(),g=A.createGain();o.type="square";o.frequency.value=520;g.gain.value=0.02;o.connect(g);g.connect(A.destination);o.start();o.stop(A.currentTime+0.025)}catch(e){}}

function chrSvg(){const n=CHR_SEG.length,R=140,cx=150,cy=150,P=a=>{const r=(a-90)*Math.PI/180;return[cx+R*Math.cos(r),cy+R*Math.sin(r)]};
  const seg=CHR_SEG.map((r,i)=>{const a0=i*360/n,a1=(i+1)*360/n,[x0,y0]=P(a0),[x1,y1]=P(a1),mid=(a0+a1)/2,tx=cx+R*0.64*Math.cos((mid-90)*Math.PI/180),ty=cy+R*0.64*Math.sin((mid-90)*Math.PI/180);
    return `<path d="M${cx},${cy} L${x0.toFixed(1)},${y0.toFixed(1)} A${R},${R} 0 0 1 ${x1.toFixed(1)},${y1.toFixed(1)} Z" fill="${CHR_COL[r]}" stroke="#05070b" stroke-width="2"/><text x="${tx.toFixed(1)}" y="${ty.toFixed(1)}" fill="${r=="legend"?"#1a1408":"#f3e7c9"}" font-size="26" font-weight="700" text-anchor="middle" dominant-baseline="middle">؟</text>`}).join("");
  const w=CHR.big?"min(420px,60vh)":"min(300px,78vw)";
  return `<div style="position:relative;width:${w};margin:10px auto"><svg viewBox="0 0 300 300" role="img" aria-label="عجلة التحدي" style="width:100%;display:block;filter:drop-shadow(0 0 18px rgba(201,163,90,.35))"><circle cx="150" cy="150" r="146" fill="none" stroke="#c9a35a" stroke-width="4"/><g id="chr_g" style="transform-origin:150px 150px;transform:rotate(${CHR.rot}deg)">${seg}</g><circle cx="150" cy="150" r="18" fill="#05070b" stroke="#c9a35a" stroke-width="3"/></svg><div style="position:absolute;top:-6px;left:50%;transform:translateX(-50%);width:0;height:0;border-left:11px solid transparent;border-right:11px solid transparent;border-top:22px solid #e5484d"></div></div>`}

function chrBtn(label,fn,kind){const bg=kind=="g"?"#2a2f3a":kind=="ok"?"#2ea66b":"#c9a35a",fg=kind=="g"||kind=="ok"?"#f4f1ea":"#1b1710",fs=CHR.big?26:18;
  return `<button onclick="${fn}" style="display:block;width:100%;margin-top:10px;font:700 ${fs}px 'IBM Plex Sans Arabic',system-ui;padding:${CHR.big?18:14}px;border:0;border-radius:16px;background:${bg};color:${fg};cursor:pointer">${label}</button>`}

function chrShell(inner){let o=document.getElementById("chr_ov");if(!o){o=document.createElement("div");o.id="chr_ov";o.style.cssText="position:fixed;inset:0;z-index:99998;background:#05070b;color:#f4f1ea;overflow:auto;padding:14px 16px calc(24px + env(safe-area-inset-bottom));font-family:'IBM Plex Sans Arabic',system-ui,sans-serif";o.setAttribute("role","dialog");o.setAttribute("aria-modal","true");document.body.appendChild(o)}
  o.innerHTML=`<div style="max-width:${CHR.big?640:460}px;margin:0 auto;text-align:center"><div style="display:flex;justify-content:space-between;align-items:center"><b style="color:#c9a35a;font-size:${CHR.big?24:18}px">ABO YOUSEF CHALLENGE</b><button onclick="chrClose()" style="font:700 ${CHR.big?20:15}px inherit;padding:8px 14px;border:1px solid #2a2f3a;border-radius:12px;background:transparent;color:#f4f1ea;cursor:pointer">✕ إغلاق</button></div><div style="font-size:${CHR.big?30:22}px;font-weight:700;margin:10px 0 2px">${esc(CHR.name||"العميل")}</div>${inner}</div>`}
function chrClose(){const o=document.getElementById("chr_ov");if(o)o.remove();CHR.cur=null;try{window.chrOnClose&&window.chrOnClose()}catch(e){}}

function chrLevel(){const r=CHR.row||{},L=r.level||{},e=+r.earned||0;if(!L.name)return"";const bar=L.next_at?`<div style="height:8px;border-radius:6px;background:#1d2330;margin:6px auto;max-width:320px;overflow:hidden"><i style="display:block;height:100%;width:${Math.min(100,Math.round(100*e/L.next_at))}%;background:#c9a35a"></i></div><div style="font-size:13px;color:#9aa0ab">${chrN(e)} / ${chrN(L.next_at)} للمستوى «${esc(L.next_name)}»</div>`:`<div style="font-size:13px;color:#9aa0ab">أعلى مستوى 👑</div>`;
  return `<div style="margin:4px 0 8px"><span style="color:#9aa0ab;font-size:14px">مستواه: </span><b style="color:#e5b94e">${esc(L.name)}</b>${bar}</div>`}

function chrCard(c,note){const r=CHR_RAR[c.rarity]||CHR_RAR.common;return `<div style="border:2px solid ${r[1]};border-radius:18px;padding:16px;margin:12px 0;background:#0d1117"><span style="display:inline-block;padding:2px 12px;border-radius:12px;background:${r[1]};color:#05070b;font-weight:700;font-size:14px">${r[0]}</span><div style="font-size:${CHR.big?30:21}px;font-weight:700;margin:10px 0">${esc(c.title)}</div><div style="font-size:${CHR.big?22:16}px;color:#e5b94e">مكافأة العميل: <b>${chrN(c.points)} نقطة</b></div>${note?`<div style="margin-top:8px;color:#9aa0ab;font-size:${CHR.big?18:14}px">${note}</div>`:""}</div>`}

function chrDraw(msg){const c=CHR.cur;let b="";
  if(msg)b=`<div style="margin:18px 0;font-size:${CHR.big?26:19}px">${msg}</div>`+chrBtn("تمام","chrClose()");
  else if(c&&c.status=="offered")b=chrCard(c,"اعرض التحدي على العميل واسأله: موافق؟ (اختياري ومن غير إحراج)")+chrBtn("العميل موافق ✅","chrAnswer(true)","ok")+chrBtn("مش موافق","chrAnswer(false)","g");
  else if(c&&c.status=="accepted")b=chrCard(c,"نفّذوا التحدي دلوقتي، وبعد ما يخلص اضغط اتنفّذ")+chrBtn("اتنفّذ ✅","chrFinish(true)","ok")+chrBtn("ما اتنفّذش","chrFinish(false)","g");
  else b=chrSvg()+chrBtn(CHR.busy?"بتلف...":"لفّ العجلة 🔥","chrSpin()")+`<div style="margin-top:8px;color:#6f7787;font-size:12px">التحديات خفيفة وبموافقة العميل، ومفيش تصوير أو نشر من غير إذنه.</div>`;
  chrShell(chrLevel()+b)}

async function chrOpen(appt,name,big){CHR.appt=appt;CHR.name=name||"";CHR.big=!!big;CHR.cur=null;CHR.row=null;chrShell(`<p style="color:#9aa0ab;margin-top:30px">بنحمّل...</p>`);
  const{data,error}=await sb.rpc("challenge_present");if(error){chrClose();return toast(error.message)}
  if(!data||!data.on){chrClose();return toast("عجلة التحدي مش شغّالة دلوقتي")}
  const row=(data.list||[]).find(x=>x.appt==appt);if(!row){chrClose();return toast("العميل ده مش حاضر على تذكرتك")}
  CHR.row=row;CHR.cur=row.current||null;
  if(!CHR.cur&&row.left_today<=0){return chrDraw("العميل ده خلّص لفّات التحدي النهارده")}
  chrDraw()}

async function chrSpin(){if(CHR.busy)return;CHR.busy=true;chrDraw();
  const{data,error}=await sb.rpc("challenge_spin",{p_appt:CHR.appt});
  if(error){CHR.busy=false;toast(error.message);return chrDraw()}
  const idx=[];CHR_SEG.forEach((r,i)=>{if(r==data.rarity)idx.push(i)});const pick=idx.length?idx[Math.floor(Math.random()*idx.length)]:0,n=CHR_SEG.length,step=360/n,target=360*5+(360-(pick+0.5)*step),red=chrRed(),D=red?0:4200;
  const g=document.getElementById("chr_g");if(g){g.style.transition=red?"none":"transform 4.2s cubic-bezier(.12,.7,.1,1)";CHR.rot=(Math.floor(CHR.rot/360)*360)+target;g.style.transform=`rotate(${CHR.rot}deg)`}
  if(!red){const N=26;for(let k=1;k<=N;k++)setTimeout(chrTick,D*(1-Math.pow(1-k/N,2)))}
  setTimeout(()=>{CHR.busy=false;CHR.cur={id:data.id,title:data.title,rarity:data.rarity,points:data.points,status:"offered"};try{navigator.vibrate&&navigator.vibrate(data.rarity=="legend"?[80,40,80,40,160]:40)}catch(e){}chrDraw()},D+150)}

async function chrAnswer(ok){const{error}=await sb.rpc("challenge_answer",{p_id:CHR.cur.id,p_accept:!!ok});if(error)return toast(error.message);
  if(ok){CHR.cur.status="accepted";chrDraw()}else{CHR.cur=null;chrDraw("اتسجّل إن العميل مش موافق. مفيش مشكلة 👍")}}
async function chrFinish(ok){const id=CHR.cur.id;const{data,error}=await sb.rpc(ok?"challenge_confirm":"challenge_cancel",{p_id:id});if(error)return toast(error.message);
  CHR.cur=null;chrDraw(ok?`🎉 اتضافت ${chrN(data&&data.points)} نقطة لحساب ${esc(CHR.name||"العميل")}`:"اتلغى التحدي ومفيش نقاط")}
