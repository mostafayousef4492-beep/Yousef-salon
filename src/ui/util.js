/* ui/util.js — أدوات مشتركة (جداول، أعمدة، كروت) */

async function copyLink(p){const u=location.origin+p;try{await navigator.clipboard.writeText(u);toast("تم نسخ الرابط ✓")}catch(e){prompt("انسخ الرابط:",u)}}

// ================= التقارير =================

const num=x=>Math.round(+x||0).toLocaleString("ar-EG"),ymd=d=>d.toLocaleDateString("en-CA");

// ===== يوم العمل: المالك/المدير هو اللي يفتح اليوم ويقفله (مش الساعة 12) =====
let _bizAt=0;
const bizToday=()=>(C.biz&&C.biz.open&&C.biz.day)||ymd(new Date());
const bizBase=()=>new Date(bizToday()+"T12:00:00");
const bizFrom=()=>{if(C.biz&&C.biz.open&&C.biz.window_from)return new Date(C.biz.window_from);const d=new Date();d.setHours(0,0,0,0);return d};
async function bizLoad(force){if(!force&&Date.now()-_bizAt<15000)return;try{const{data}=await sb.rpc("business_day_state");if(data){C.biz=data;_bizAt=Date.now()}}catch(e){}bizStrip()}
// شريط تنبيه ثابت لما اليوم المفتوح أقدم من النهارده: كل حاجة بتتسجل على اليوم ده
function bizStrip(){try{let el=document.getElementById("bzstrip");const b=C.biz;if(typeof me==="undefined"||!me||me.role==="customer"||!b||!b.open){if(el)el.remove();return}
  const hrs=b.opened_at?(Date.now()-new Date(b.opened_at).getTime())/36e5:0,old=!b.backdated&&hrs>18;
  if(!b.backdated&&!old){if(el)el.remove();return}
  if(!el){el=document.createElement("div");el.id="bzstrip";el.style.cssText="position:sticky;top:0;z-index:70;color:#fff;font:700 13px system-ui;padding:8px 12px;text-align:center";document.body.insertBefore(el,document.body.firstChild)}
  el.style.background=b.backdated?"#b45309":"#b91c1c";
  const msg=b.backdated?"⚠ شغّال على يوم "+b.day+" — النهارده الحقيقي "+(b.natural||b.calendar)+" · كل حاجة بتتسجل على يوم "+b.day:"⚠ يوم "+b.day+" مفتوح بقاله "+Math.floor(hrs)+" ساعة — اقفله بجرد الدرج وافتح يوم جديد";
  el.textContent=msg+" ";const bt=document.createElement("button");bt.textContent="قفل اليوم";bt.style.cssText="margin-inline-start:8px;border:0;border-radius:8px;padding:4px 10px;font:700 12px system-ui;cursor:pointer";bt.onclick=()=>bizClose();el.appendChild(bt)}catch(e){}}
async function bizKeyer(){const f=t=>ymd(new Date(t));try{const{data}=await sb.rpc("business_days_list");if(!Array.isArray(data)||!data.length)return f;const R=[];let lc=null;data.forEach(r=>{const st=lc||new Date(Math.min(new Date(r.opened_at),new Date(r.day+"T00:00")));const en=r.closed_at?new Date(r.closed_at):null;R.push({day:r.day,st,en});if(en&&(!lc||en>lc))lc=en});return t=>{const d=new Date(t);for(const r of R)if(d>=r.st&&(!r.en||d<r.en))return r.day;return f(t)}}catch(e){return f}}
async function bizOpen(){const cal=(C.biz&&C.biz.calendar)||ymd(new Date());let min="";
  try{const{data}=await sb.rpc("business_days_list");if(Array.isArray(data)&&data.length){const d=new Date(data[data.length-1].day+"T12:00:00");d.setDate(d.getDate()+1);min=ymd(d)}}catch(e){}
  dsOpen("فتح يوم عمل",`<div class="m" style="margin-bottom:8px">اختار تاريخ اليوم اللي هتشتغل عليه. لو اخترت يوم قديم، كل الفواتير والمصروفات والسحب والسلف هتتسجل على اليوم ده (مش النهارده)، والحضور والانصراف بيفضلوا بالوقت الحقيقي. اليوم بيفضل مفتوح لحد ما تقفله بجرد الدرج.</div><input type="date" id="bo_d" value="${cal}" max="${cal}"${min?` min="${min}"`:""} oninput="bizOpenHint()"><div id="bo_n" class="m" style="margin:8px 0"></div><button class="btn" onclick="bizOpenGo()">فتح اليوم</button>`);bizOpenHint()}
function bizOpenHint(){const v=$("bo_d")?.value,cal=(C.biz&&C.biz.calendar)||ymd(new Date()),n=$("bo_n");if(!n)return;n.innerHTML=v&&v<cal?`<b style="color:#b45309">⚠ هتشتغل على يوم ${esc(v)} والنهارده الحقيقي ${esc(cal)}</b>`:""}
async function bizOpenGo(){const v=$("bo_d")?.value,cal=(C.biz&&C.biz.calendar)||ymd(new Date());if(!v)return toast("اختار التاريخ");
  if(!confirm(v<cal?"تفتح يوم "+v+" والنهارده "+cal+"؟\nكل اللي هتسجله هيتحسب على يوم "+v+" لحد ما تقفل اليوم.":"تفتح يوم عمل جديد دلوقتي؟\nهيفضل مفتوح (حتى بعد 12) لحد ما تقفله بجرد الدرج."))return;
  const{error}=await sb.rpc("open_business_day",{p_day:v<cal?v:null});if(error)return toast(error.message);svcClose();await bizLoad(true);toast("اتفتح اليوم ✓");go("home")}
async function bizReopen(){if(!me||me.role!="owner")return;if(!confirm("تعيد فتح آخر يوم اتقفل؟\nجرد الدرج بتاعه هيتشال (بيتسجل في سجل المحذوفات) وتقدر تعدّل وتقفله تاني."))return;
  const{error}=await sb.rpc("reopen_business_day");if(error)return toast(error.message);await bizLoad(true);toast("اتعاد فتح اليوم ✓");go("home")}
function bizClose(){if(!C.biz||!C.biz.open)return;C.cd=C.biz.day;go("cash");toast("اكتب جرد الدرج (كاش / كارت / محفظة) واضغط قفل اليوم")}
const bizBox=()=>{const b=C.biz;if(!b)return"";const adm=isAdm(me),tm=t=>new Date(t).toLocaleString("ar-EG",{hourCycle:"h23",weekday:"short",hour:"2-digit",minute:"2-digit"});
  return b.open?`<div class="box" style="margin:8px 0;border-color:var(--ok)"><b>🟢 يوم العمل مفتوح: ${esc(b.day)}</b><div class="m">اتفتح ${tm(b.opened_at)} — بيفضل شغّال لحد ما تقفله</div>${adm?`<button class="btn" style="margin-top:8px" onclick="bizClose()">قفل اليوم (جرد الدرج)</button>`:""}</div>`
   :`<div class="box" style="margin:8px 0;border-color:var(--red)"><b>🔴 مفيش يوم عمل مفتوح</b><div class="m">الشغل شغّال عادي على تاريخ النهارده (${esc(b.day)}). افتح اليوم عشان الدور والدرج يتحسبوا عليه.</div>${adm?`<button class="btn" style="margin-top:8px" onclick="bizOpen()">فتح اليوم</button>`:""}${me&&me.role=="owner"?`<button class="btn" style="margin-top:8px;margin-inline-start:6px;background:transparent;border:1px solid var(--line);color:var(--ink,inherit)" onclick="bizReopen()">إعادة فتح آخر يوم</button>`:""}</div>`};

const tbl=(h,rows)=>rows.length?`<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse;font-size:13px"><tr>${h.map(x=>`<th style="text-align:right;padding:6px;border-bottom:1px solid var(--line);color:var(--mute);white-space:nowrap">${x}</th>`).join("")}</tr>${rows.map(r=>`<tr>${r.map(c=>`<td style="padding:6px;border-bottom:1px dashed var(--line)">${c}</td>`).join("")}</tr>`).join("")}</table></div>`:`<p class="m">مفيش بيانات في الفترة دي.</p>`;

const bars=(a,lab,val,clk)=>{const m=Math.max(1,...a.map(val));return a.length?a.map((x,i)=>`<div style="margin-bottom:7px${clk?";cursor:pointer":""}"${clk?` role="button" onclick="${clk(x,i)}"`:""}><div style="display:flex;justify-content:space-between;font-size:12px"><span>${lab(x)}</span><b>${fm(val(x))}</b></div><div style="height:8px;border-radius:6px;background:var(--line);overflow:hidden"><i style="display:block;height:100%;width:${val(x)/m*100}%;background:var(--blue)"></i></div></div>`).join(""):`<p class="m">مفيش بيانات.</p>`};

const kc=(l,v,c,a)=>`<div class="box kpi"${a?` role="button" tabindex="0" onclick="${a}" style="cursor:pointer"`:""}><div class="kpi-l">${l}</div><div class="kpi-v" style="color:${c||"inherit"}">${v}</div>${a?`<div class="m" style="font-size:11px">اضغط للتفاصيل</div>`:""}</div>`;

const netErr=e=>!!e&&!e.code&&!e.hint&&!e.details;

function t24(id,val,extra){const v=(val||"").slice(0,5),[h,m]=v?v.split(":"):["",""];
const H=`<option value="">--</option>`+Array.from({length:24},(_,i)=>{const x=String(i).padStart(2,"0");return `<option ${x==h?"selected":""}>${x}</option>`}).join("");
const mins=Array.from({length:12},(_,i)=>String(i*5).padStart(2,"0"));if(m&&!mins.includes(m)){mins.push(m);mins.sort()}
const M=mins.map(x=>`<option ${x==m?"selected":""}>${x}</option>`).join("");
return `<span dir="ltr" style="display:inline-flex;gap:4px;align-items:center"><input type="hidden" id="${id}" value="${v}" ${extra||""}><select onchange="t24c(this)" style="width:auto;margin:0">${H}</select><b>:</b><select onchange="t24c(this)" style="width:auto;margin:0">${M}</select></span>`}

function t24c(el){const w=el.parentNode,s=w.querySelectorAll("select"),h=w.querySelector("input"),nv=s[0].value?s[0].value+":"+s[1].value:"";if(h.value!==nv){h.value=nv;h.dispatchEvent(new Event("change",{bubbles:true}))}}

function t24v(id,v){const el=$(id);if(!el)return;const s=el.parentNode.querySelectorAll("select"),[h,m]=v?v.slice(0,5).split(":"):["",""];
if(m&&![...s[1].options].some(o=>o.value==m)){const o=new Option(m,m);s[1].add(o);[...s[1].options].sort((a,b)=>a.value-b.value).forEach(x=>s[1].add(x))}
s[0].value=h||"";s[1].value=m||"00";el.value=v?v.slice(0,5):""}
