/* features/team/staff-wheel.js — عجلة تحديات الموظفين (غير عجلة تحدي العملاء)
   V.swh: شاشة الموظف (تحدياته حسب دوره، لفّ العجلة، نقاطه وجوايزه) + قايمة التأكيد للمدير/الكاشير.
   swAdmin(): إدارة التحديات والجوايز والتقرير للمالك. التأكيد والجايزة والحدود كلها في السيرفر (patch_staff_wheel.sql). */

const SWH={rot:0,busy:false,me:null};
const swN=n=>Number(Math.round(+n||0)).toLocaleString("ar-EG");
const swNeed=e=>/staff_ch_|PGRST202|42883|42P01|PGRST205/.test((e.code||"")+" "+(e.message||""))?"الميزة لسه مش متفعّلة: شغّل patch_staff_wheel.sql في Supabase.":esc(e.message||"");
const SW_ST={claimed:["مستني التأكيد","tag"],confirmed:["اتأكّد ✓ — لفّ العجلة","ok"],rejected:["اترفض","tag"],spun:["اتلفّت","tag"]};

V.swh=async function(){put(`<h1>تحدياتي</h1><p class="m">بنحمّل...</p>`);
  const{data:d,error}=await sb.rpc("staff_ch_me");
  if(error)return put(`<h1>تحدياتي</h1><p class="m">${swNeed(error)}</p>`);
  if(!d||!d.on)return put(`<h1>تحدياتي</h1><p class="m">عجلة تحديات الموظفين مش شغّالة دلوقتي.</p>`);
  SWH.me=d;let pend=[];
  if(isAdm(me)||can("use_pos")){const r=await sb.rpc("staff_ch_pending");if(!r.error)pend=r.data||[]}
  const role=d.role=="assistant"?"المساعد":d.role=="barber"?"الصنايعي":"الموظف";
  put(`<h1>تحدياتي</h1><p class="m">تحديات النهارده لـ${role}. خلّص التحدي، وبعد ما المدير أو الكاشير يأكّده تلفّ العجلة.</p>
<div class="box"><div class="row"><div><b>نقاطي</b><div class="m">لفات النهارده المتاحة: ${swN(d.spins_left)}</div></div><b style="font-size:22px">${swN(d.points)}</b></div></div>
<h2>تحديات النهارده</h2>${(d.list||[]).length?d.list.map(x=>{const s=x.status?SW_ST[x.status]:null;
  return `<div class="row"><div><b>${esc(x.title)}</b>${x.status=="spun"&&x.prize?`<div class="m">الجايزة: ${esc(x.prize)}</div>`:""}</div>${!x.status?`<button class="btn s" onclick="swClaim(${x.def_id})">خلّصت ✅</button>`:x.status=="confirmed"?`<button class="btn s" onclick="swSpin(${x.log_id})" ${d.spins_left>0?"":"disabled"}>🎡 لفّ</button>`:`<span class="${s[1]}">${s[0]}</span>`}</div>`}).join(""):`<p class="m">مفيش تحديات ليك دلوقتي.</p>`}
${pend.length?`<h2>مستنية تأكيدك</h2>${pend.map(x=>`<div class="row"><div><b>${esc(x.staff)}</b><div class="m">${esc(x.title)}</div></div><div><button class="btn s" onclick="swDecide(${x.id},true)">أكّد</button> <button class="btn s g" onclick="swDecide(${x.id},false)">ارفض</button></div></div>`).join("")}`:""}
<h2>جوايز النقاط</h2>${(d.rewards||[]).length?d.rewards.map(x=>`<div class="row"><div><b>${esc(x.label)}</b><div class="m">${swN(x.cost)} نقطة</div></div><button class="btn s g" ${d.points>=x.cost?"":"disabled"} onclick="swRedeem(${x.id},'${esc(x.label).replace(/'/g,"")}')">استبدل</button></div>`).join(""):`<p class="m">مفيش جوايز متاحة دلوقتي.</p>`}
${(d.redeems||[]).length?`<div class="m" style="margin-top:8px">آخر طلباتك: ${d.redeems.map(r=>esc(r.label)+" ("+({pending:"مستني",done:"اتسلّم",rejected:"اترفض ورجعت نقاطك"}[r.status])+")").join(" · ")}</div>`:""}`)};

async function swClaim(id){const{error}=await sb.rpc("staff_ch_claim",{p_def:id});error?toast(error.message):(toast("اتسجّل، مستني تأكيد المدير أو الكاشير"),V.swh())}
async function swDecide(id,ok){const{error}=await sb.rpc("staff_ch_decide",{p_log:id,p_ok:ok});error?toast(error.message):(toast(ok?"اتأكّد ✓":"اترفض"),V.swh())}
async function swRedeem(id,l){if(!await askConfirm("تستبدل «"+l+"»؟ النقاط هتتخصم ولو اترفض بترجع."))return;const{error}=await sb.rpc("staff_reward_redeem",{p_reward:id});error?toast(error.message):(toast("اتبعت الطلب للمدير ✓"),V.swh())}

function swWheel(sl){const n=sl.length||1,R=120,cx=130,cy=130,col=["#2b3344","#2f5fb3","#c9a35a","#3a7d5c","#7a4a8c","#a85c3a"];
  const P=a=>{const r=(a-90)*Math.PI/180;return[cx+R*Math.cos(r),cy+R*Math.sin(r)]};
  const seg=sl.map((s,i)=>{const a0=i*360/n,a1=(i+1)*360/n,[x0,y0]=P(a0),[x1,y1]=P(a1),m=(a0+a1)/2,r=(m-90)*Math.PI/180,tx=cx+R*.62*Math.cos(r),ty=cy+R*.62*Math.sin(r);
    return `<path d="M${cx},${cy} L${x0.toFixed(1)},${y0.toFixed(1)} A${R},${R} 0 0 1 ${x1.toFixed(1)},${y1.toFixed(1)} Z" fill="${col[i%col.length]}" stroke="#0b0e14" stroke-width="2"/><text x="${tx.toFixed(1)}" y="${ty.toFixed(1)}" fill="#fff" font-size="11" font-weight="700" text-anchor="middle" dominant-baseline="middle" transform="rotate(${m} ${tx.toFixed(1)} ${ty.toFixed(1)})">${esc(String(s.label).slice(0,10))}</text>`}).join("");
  return `<div style="position:relative;width:min(280px,76vw);margin:10px auto"><svg viewBox="0 0 260 260" style="width:100%;display:block"><g id="sw_rot" style="transform-origin:130px 130px;transform:rotate(${SWH.rot}deg)">${seg}</g><circle cx="130" cy="130" r="12" fill="#0b0e14"/></svg><div style="position:absolute;top:-4px;left:50%;transform:translateX(-50%);font-size:26px;line-height:1;color:#e5b94e">▼</div></div>`}
function swShell(inner){let o=document.getElementById("sw_ov");if(!o){o=document.createElement("div");o.id="sw_ov";o.style.cssText="position:fixed;inset:0;z-index:99998;background:rgba(5,7,11,.96);color:#f4f1ea;overflow:auto;padding:16px;font-family:inherit";document.body.appendChild(o)}
  o.innerHTML=`<div style="max-width:440px;margin:0 auto;text-align:center">${inner}</div>`}
function swClose(){const o=document.getElementById("sw_ov");if(o)o.remove();V.swh()}
async function swSpin(id){if(SWH.busy)return;SWH.busy=true;const sl=(SWH.me&&SWH.me.slices)||[];
  swShell(`<h2>🎡 بنلفّ...</h2>${swWheel(sl)}`);
  const{data,error}=await sb.rpc("staff_ch_spin",{p_log:id});
  if(error){SWH.busy=false;swShell(`<p>${esc(error.message)}</p><button class="btn" onclick="swClose()">رجوع</button>`);return}
  const n=sl.length||1,i=Math.max(0,sl.findIndex(s=>s.id==data.slice_id)),red=!!(window.matchMedia&&matchMedia("(prefers-reduced-motion: reduce)").matches);
  const target=360*(red?0:5)+(360-(i+.5)*360/n);SWH.rot=target;const g=document.getElementById("sw_rot");
  if(g){g.style.transition=red?"none":"transform 4s cubic-bezier(.12,.7,.1,1)";g.style.transform=`rotate(${target}deg)`}
  setTimeout(()=>{SWH.busy=false;const none=data.kind=="none";swShell(`<h2>${none?"حظ أوفر":"🎉 كسبت"}</h2>${swWheel(sl)}<div style="font-size:24px;font-weight:700;margin:8px 0">${esc(data.label)}</div><div style="color:#9aa0ab">${data.kind=="cash"?"اتسجّلت مكافأة في حسابك وهتتصرف مع الراتب":data.kind=="points"?"نقاطك دلوقتي "+swN(data.points):data.kind=="gift"?"المدير هيسلّمك الهدية":"كمّل تحديات وجرّب تاني"}</div><button class="btn" style="margin-top:14px;width:100%" onclick="swClose()">تمام</button>`)},red?100:4300)}

/* ===== إدارة (للمالك) ===== */
async function swAdmin(){const T="🧑‍🔧 عجلة تحديات الموظفين";dsOpen(T,`<p class="m">بنحمّل...</p>`);
  const[a,b,c,r]=await Promise.all([sb.from("staff_ch_defs").select("*").order("sort").order("id"),sb.from("staff_wheel_slices").select("*").order("sort").order("id"),sb.from("staff_rewards").select("*").order("cost"),sb.rpc("staff_ch_report",{p_days:30})]);
  if(a.error)return dsOpen(T,`<p class="m">${swNeed(a.error)}</p>`);
  const D=a.data||[],S=b.data||[],W=c.data||[],rep=r.data||{},tw=S.filter(x=>x.active).reduce((t,x)=>t+(+x.weight||0),0);
  const opt=(L,v)=>L.map(x=>`<option value="${x[0]}" ${x[0]==v?"selected":""}>${x[1]}</option>`).join(""),RL=[["all","الكل"],["assistant","المساعد"],["barber","الصنايعي"]],KL=[["cash","فلوس"],["points","نقاط"],["gift","هدية عينية"],["none","حظ أوفر"]];
  dsOpen(T,`<p class="m">التشغيل والحدود (لفات اليوم، سقف الفلوس الشهري) من الإعدادات ← المكافآت والولاء. الفلوس بتتسجّل «مكافأة» في حساب الموظف وبتتصرف مع الراتب. مفيش أي خصم.</p>
<div class="m" style="margin:8px 0">آخر 30 يوم: <b>${swN(rep.done)}</b> تحدي اتأكّد · <b>${swN(rep.rejected)}</b> اترفض · <b>${swN(rep.cash)}</b> جنيه جوايز · <b>${swN(rep.points)}</b> نقطة</div>
${(rep.redeems||[]).length?`<h3>طلبات استبدال مستنية</h3>${rep.redeems.map(x=>`<div class="row"><div><b>${esc(x.staff)}</b><div class="m">${esc(x.label)} · ${swN(x.cost)} نقطة</div></div><div><button class="btn s" onclick="swRes(${x.id},true)">تم التسليم</button> <button class="btn s g" onclick="swRes(${x.id},false)">رفض</button></div></div>`).join("")}`:""}
<h3>التحديات</h3>${D.map(x=>`<div class="row" style="flex-wrap:wrap;gap:6px"><input id="sd_t${x.id}" value="${esc(x.title)}" style="flex:1;min-width:150px"><select id="sd_r${x.id}">${opt(RL,x.role)}</select><label class="m"><input type="checkbox" id="sd_a${x.id}" ${x.active?"checked":""}> شغّال</label><button class="btn s" onclick="sdSave(${x.id})">حفظ</button><button class="btn s g" onclick="swDel('staff_ch_defs',${x.id})">مسح</button></div>`).join("")}<button class="btn g s" onclick="swAdd('staff_ch_defs',{title:'تحدي جديد',role:'all',sort:999})">+ تحدي جديد</button>
<h3 style="margin-top:16px">قطاعات العجلة (نسبة الظهور = الوزن ÷ ${tw||0})</h3>${S.map(x=>`<div class="row" style="flex-wrap:wrap;gap:6px"><input id="ss_l${x.id}" value="${esc(x.label)}" style="flex:1;min-width:110px"><select id="ss_k${x.id}">${opt(KL,x.kind)}</select><input id="ss_v${x.id}" type="number" min="0" value="${x.value}" style="width:70px" title="القيمة"><input id="ss_w${x.id}" type="number" min="0" value="${x.weight}" style="width:60px" title="الوزن"><label class="m"><input type="checkbox" id="ss_a${x.id}" ${x.active?"checked":""}> شغّال</label><button class="btn s" onclick="ssSave(${x.id})">حفظ</button><button class="btn s g" onclick="swDel('staff_wheel_slices',${x.id})">مسح</button></div>`).join("")}<button class="btn g s" onclick="swAdd('staff_wheel_slices',{label:'جايزة جديدة',kind:'points',value:10,weight:1,sort:999})">+ قطاع جديد</button>
<h3 style="margin-top:16px">كتالوج جوايز النقاط</h3>${W.map(x=>`<div class="row" style="gap:6px"><input id="sw_l${x.id}" value="${esc(x.label)}" style="flex:1"><input id="sw_c${x.id}" type="number" min="1" value="${x.cost}" style="width:80px" title="النقاط"><label class="m"><input type="checkbox" id="sw_a${x.id}" ${x.active?"checked":""}> شغّال</label><button class="btn s" onclick="srSave(${x.id})">حفظ</button><button class="btn s g" onclick="swDel('staff_rewards',${x.id})">مسح</button></div>`).join("")}<button class="btn g s" onclick="swAdd('staff_rewards',{label:'جايزة جديدة',cost:100})">+ جايزة جديدة</button>`)}
const swDone=e=>e?toast(e.message):(toast("اتحفظ ✓"),swAdmin());
async function sdSave(id){const{error}=await sb.from("staff_ch_defs").update({title:$("sd_t"+id).value.trim()||"—",role:$("sd_r"+id).value,active:$("sd_a"+id).checked}).eq("id",id);swDone(error)}
async function ssSave(id){const{error}=await sb.from("staff_wheel_slices").update({label:$("ss_l"+id).value.trim()||"—",kind:$("ss_k"+id).value,value:Math.max(0,+$("ss_v"+id).value||0),weight:Math.max(0,parseInt($("ss_w"+id).value)||0),active:$("ss_a"+id).checked}).eq("id",id);swDone(error)}
async function srSave(id){const{error}=await sb.from("staff_rewards").update({label:$("sw_l"+id).value.trim()||"—",cost:Math.max(1,parseInt($("sw_c"+id).value)||1),active:$("sw_a"+id).checked}).eq("id",id);swDone(error)}
async function swAdd(t,row){const{error}=await sb.from(t).insert(row);error?toast(error.message):swAdmin()}
async function swDel(t,id){if(!await askConfirm("تمسح ده؟ (السجل القديم بيفضل)"))return;const{error}=await sb.from(t).delete().eq("id",id);error?toast(error.message):swAdmin()}
async function swRes(id,ok){const{error}=await sb.rpc("staff_redeem_resolve",{p_id:id,p_ok:ok});error?toast(error.message):(toast("تم ✓"),swAdmin())}
