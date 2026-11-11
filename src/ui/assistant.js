/* ui/assistant.js — مساعد صالون أبو يوسف الذكي (واجهة الشات)
   للعميل وللموظف وللإدارة (مالك/مدير بس — الزرار بيظهر بعد ما القاعدة تأكد الصلاحية). بيكلّم Edge Function اسمها assistant. */
(function(){
if(window.__ai)return;window.__ai=1;
const MODE=window.SALON_MODE||"customer";
const CUS=MODE=="customer",ADM=MODE=="admin";
const SUG_OWN=["إيراد الشهر ده كام؟","إيه أكتر الخدمات طلبًا الشهر ده؟","مين أعلى حلاق في المبيعات؟","المصروفات زادت عن الشهر اللي فات؟","قارن الشهر ده باللي فات"],SUG_MGR=["إزاي أضيف موظف؟","إزاي أقفل اليوم؟","محمود سحب كام الشهر ده؟","عايز أعرف عن عميل","إزاي أسجل مصروف؟"];
const SUG0=CUS?["مين الحلاقين الموجودين دلوقتي؟","عندي كام نقطة؟","دوري فاضل عليه كام؟","عايز أحجز حلاقة"]:["راتبي كام لحد دلوقتي؟","حضوري الشهر ده","آخر تقييماتي","السحوبات اللي عليا"];
const mgrMode=()=>ADM&&S.mode=="manager";const SUG=()=>ADM?(mgrMode()?SUG_MGR:SUG_OWN):SUG0;
const TITLE0=CUS?"مساعد أبو يوسف":"مساعد الفريق",SUB0=CUS?"اسألني عن دورك ونقاطك واحجز بسهولة":"اسألني عن راتبك وحضورك وتقييماتك";
const TITLE=()=>ADM?(mgrMode()?"مساعد المدير":"محلل الإدارة"):TITLE0,SUB=()=>ADM?(mgrMode()?"اسأل أو اطلب تنفيذ: موظفين، سلف، مصروفات، قفل اليوم، عملاء":"اسأل عن الأرقام وقارن الفترات، أو اطلب تنفيذ حاجة"):SUB0;
const S={open:false,busy:false,msgs:[],uid:null,dv:null,mode:null};
const E=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const $a=id=>document.getElementById(id);

const css=`
.ai-fab{position:fixed;z-index:9;inset-inline-end:14px;bottom:calc(86px + env(safe-area-inset-bottom,0px));width:54px;height:54px;border-radius:50%;border:0;cursor:pointer;display:none;align-items:center;justify-content:center;color:var(--on-gold,#1a1405);background:radial-gradient(circle at 30% 25%,#f5dca0,var(--gold,#d4af6a) 55%,#9c7a32);box-shadow:0 10px 26px -8px rgba(212,175,106,.7),0 0 0 1px rgba(255,255,255,.18) inset;transition:transform .18s ease}
.ai-fab.on{display:flex}.ai-fab:active{transform:scale(.93)}
.ai-fab svg{width:26px;height:26px}
.ai-fab::after{content:"";position:absolute;inset:-5px;border-radius:50%;border:1px solid var(--gold,#d4af6a);opacity:.45;animation:aipulse 2.8s ease-out infinite}
@keyframes aipulse{0%{transform:scale(.92);opacity:.55}100%{transform:scale(1.25);opacity:0}}
.ai-bg{position:fixed;inset:0;z-index:16;background:rgba(5,6,9,.6);backdrop-filter:blur(4px);display:flex;align-items:flex-end;justify-content:center;animation:fadein .18s ease}
.ai-sheet{width:100%;max-width:560px;height:min(86vh,720px);display:flex;flex-direction:column;background:linear-gradient(180deg,var(--card,#141821),var(--bg,#0b0d12));border:1px solid var(--line,rgba(255,255,255,.1));border-bottom:0;border-radius:26px 26px 0 0;overflow:hidden;animation:aiup .26s cubic-bezier(.2,.8,.2,1)}
@keyframes aiup{from{transform:translateY(40px);opacity:0}to{transform:none;opacity:1}}
.ai-h{display:flex;align-items:center;gap:12px;padding:14px 16px;border-bottom:1px solid var(--line,rgba(255,255,255,.1));background:linear-gradient(135deg,rgba(212,175,106,.16),transparent 70%)}
.ai-orb{width:42px;height:42px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;color:var(--on-gold,#1a1405);background:radial-gradient(circle at 30% 25%,#f5dca0,var(--gold,#d4af6a) 55%,#9c7a32);box-shadow:0 6px 18px -6px rgba(212,175,106,.8)}
.ai-orb svg{width:22px;height:22px}
.ai-h b{display:block;font-size:16px}.ai-h span{font-size:12px;color:var(--mute,#9aa0ab)}
.ai-x{margin-inline-start:auto;border:0;background:var(--card2,#1b2030);color:var(--ink,#f1ece2);width:34px;height:34px;border-radius:50%;font-size:16px;cursor:pointer}
.ai-body{flex:1;overflow-y:auto;padding:14px 14px 6px;display:flex;flex-direction:column;gap:10px;scroll-behavior:smooth}
.ai-m{max-width:86%;padding:10px 13px;border-radius:18px;line-height:1.75;font-size:14.5px;word-wrap:break-word;animation:aipop .22s ease}
@keyframes aipop{from{transform:translateY(6px);opacity:0}to{transform:none;opacity:1}}
.ai-m.u{align-self:flex-start;background:linear-gradient(135deg,var(--gold,#d4af6a),#b8923f);color:var(--on-gold,#1a1405);border-end-start-radius:6px;font-weight:600}
.ai-m.a{align-self:flex-end;background:var(--card2,#1b2030);border:1px solid var(--line,rgba(255,255,255,.1));border-end-end-radius:6px}
.ai-m ul{margin:6px 0;padding-inline-start:18px}.ai-m li{margin:2px 0}.ai-m p{margin:0 0 6px}.ai-m p:last-child{margin:0}
.ai-hello{align-self:center;text-align:center;padding:18px 10px 4px;color:var(--mute,#9aa0ab);font-size:13px}
.ai-hello .ai-orb{margin:0 auto 10px;width:56px;height:56px}.ai-hello .ai-orb svg{width:30px;height:30px}.ai-hello h3{margin:0 0 4px;color:var(--ink,#f1ece2);font-size:18px}
.ai-br{margin:12px 0 4px;padding:12px;border-radius:14px;border:1px solid var(--line,rgba(255,255,255,.14));text-align:start}.ai-br h4{margin:0 0 6px;font-size:13px;opacity:.8}.ai-br .l{font-size:13px;padding:3px 0;line-height:1.6}.ai-br .l.bad{color:#e57373}.ai-br .l.warn{color:#e0b251}.ai-chips{display:flex;flex-wrap:wrap;gap:8px;justify-content:center;margin-top:12px}
.ai-chip{border:1px solid var(--line,rgba(255,255,255,.14));background:transparent;color:var(--ink,#f1ece2);border-radius:999px;padding:8px 14px;font-size:13px;cursor:pointer;font-family:inherit}
.ai-chip:active{background:var(--card2,#1b2030)}
.ai-dots{align-self:flex-end;display:flex;gap:5px;padding:13px 16px;background:var(--card2,#1b2030);border-radius:18px;border-end-end-radius:6px;border:1px solid var(--line,rgba(255,255,255,.1))}
.ai-dots i{width:7px;height:7px;border-radius:50%;background:var(--gold,#d4af6a);animation:aidot 1.1s infinite ease-in-out}
.ai-dots i:nth-child(2){animation-delay:.16s}.ai-dots i:nth-child(3){animation-delay:.32s}
@keyframes aidot{0%,80%,100%{transform:scale(.55);opacity:.4}40%{transform:scale(1);opacity:1}}
.ai-card{align-self:flex-end;width:min(92%,380px);border:1px solid var(--gold,#d4af6a);border-radius:18px;padding:14px;background:linear-gradient(160deg,rgba(212,175,106,.14),var(--card2,#1b2030) 60%);animation:aipop .25s ease}
.ai-card h4{margin:0 0 8px;font-size:15px;display:flex;align-items:center;gap:6px}
.ai-card .r{display:flex;justify-content:space-between;gap:10px;padding:5px 0;border-bottom:1px dashed var(--line,rgba(255,255,255,.1));font-size:13.5px}
.ai-card .r:last-of-type{border:0}.ai-card .r span:first-child{color:var(--mute,#9aa0ab)}
.ai-card .t{font-weight:800;color:var(--gold,#d4af6a)}
.ai-card .bt{display:flex;gap:8px;margin-top:12px}
.ai-btn{flex:1;border:0;border-radius:12px;padding:11px;font-weight:700;font-size:14px;cursor:pointer;font-family:inherit;background:linear-gradient(135deg,var(--gold,#d4af6a),#b8923f);color:var(--on-gold,#1a1405)}
.ai-btn.g{background:var(--card,#141821);color:var(--ink,#f1ece2);border:1px solid var(--line,rgba(255,255,255,.14))}
.ai-cf{margin:6px 0;padding:12px;border-radius:14px;border:1px solid var(--gold,#d4af6a);background:var(--card,#141821)}.ai-cf h4{margin:0 0 8px;font-size:14px}.ai-cf .l{font-size:13px;padding:3px 0;line-height:1.6}.ai-cf input{width:100%;box-sizing:border-box;margin:8px 0 2px;padding:10px;border-radius:10px;border:1px solid var(--line,rgba(255,255,255,.14));background:transparent;color:inherit;font:inherit}.ai-cf .bt{display:flex;gap:8px;margin-top:10px}.ai-cf .ai-done{margin-top:8px}.ai-cf .ai-err{margin-top:8px;color:#e57373;font-size:13px}.ai-btn:disabled{opacity:.55;cursor:not-allowed}
.ai-done{color:#5fc88f;font-weight:700;text-align:center;padding:4px}
.ai-f{display:flex;gap:8px;padding:10px 12px calc(10px + env(safe-area-inset-bottom,0px));border-top:1px solid var(--line,rgba(255,255,255,.1));background:var(--bg,#0b0d12)}
.ai-f textarea{flex:1;resize:none;max-height:110px;min-height:44px;border-radius:22px;border:1px solid var(--line,rgba(255,255,255,.14));background:var(--card,#141821);color:var(--ink,#f1ece2);padding:11px 16px;font:inherit;font-size:15px;line-height:1.5;margin:0}
.ai-send{width:44px;height:44px;border-radius:50%;border:0;flex:none;cursor:pointer;color:var(--on-gold,#1a1405);background:linear-gradient(135deg,var(--gold,#d4af6a),#b8923f);display:flex;align-items:center;justify-content:center}
.ai-send:disabled{opacity:.5}.ai-send svg{width:20px;height:20px;transform:scaleX(-1)}
.ai-dr{align-self:flex-end;display:flex;flex-wrap:wrap;gap:6px;max-width:92%}
.ai-dr button{border:1px solid var(--gold,#d4af6a);background:transparent;color:var(--gold,#d4af6a);border-radius:999px;padding:6px 12px;font-size:12.5px;cursor:pointer;font-family:inherit}
.ai-dv{padding:12px 14px}.ai-dv .top{display:flex;align-items:center;gap:8px;margin-bottom:10px}.ai-dv .top button{border:1px solid var(--line,rgba(255,255,255,.14));background:var(--card,#141821);color:var(--ink,#f1ece2);border-radius:10px;padding:7px 12px;cursor:pointer;font-family:inherit}
.ai-dv .sum{font-size:13px;color:var(--mute,#9aa0ab);margin-bottom:8px}
.ai-inv{border:1px solid var(--line,rgba(255,255,255,.1));border-radius:14px;padding:10px 12px;margin-bottom:8px;background:var(--card2,#1b2030);font-size:13.5px}
.ai-inv .h{display:flex;justify-content:space-between;gap:8px;font-weight:700}.ai-inv .m{color:var(--mute,#9aa0ab);font-size:12.5px;margin-top:3px}
.ai-foot{text-align:center;font-size:11px;color:var(--mute,#9aa0ab);padding:0 12px 6px}
@media(prefers-reduced-motion:reduce){.ai-fab::after,.ai-dots i{animation:none}.ai-sheet,.ai-m,.ai-card{animation:none}}
`;
const ICON=`<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2l1.9 5.6L19.5 9.5l-5.6 1.9L12 17l-1.9-5.6L4.5 9.5l5.6-1.9L12 2zM19 14l.9 2.6 2.6.9-2.6.9L19 21l-.9-2.6-2.6-.9 2.6-.9L19 14zM5 15l.7 1.8L7.5 17.5l-1.8.7L5 20l-.7-1.8L2.5 17.5l1.8-.7L5 15z"/></svg>`;
const SEND=`<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M2 21l21-9L2 3v7l15 2-15 2v7z"/></svg>`;

function md(t){const L=String(t||"").split(/\n/);let h="",ul=false;for(let x of L){x=E(x.trim());x=x.replace(/\*\*(.+?)\*\*/g,"<b>$1</b>");const m=x.match(/^(?:[-•*]|\d+[.)])\s+(.*)$/);if(m){if(!ul){h+="<ul>";ul=true}h+=`<li>${m[1]}</li>`}else{if(ul){h+="</ul>";ul=false}if(x)h+=`<p>${x}</p>`}}if(ul)h+="</ul>";return h}
const key=()=>"ai_hist_"+(S.uid||"x");
function save(){try{sessionStorage.setItem(key(),JSON.stringify(S.msgs.slice(-30)))}catch(e){}}
function load(){try{S.msgs=JSON.parse(sessionStorage.getItem(key())||"[]")||[]}catch(e){S.msgs=[]}}

function card(p,i,done){const dl=new Date(p.day+"T12:00:00").toLocaleDateString("ar-EG",{weekday:"long",day:"numeric",month:"long"});
return `<div class="ai-card"><h4>🗓️ ملخص الحجز</h4>
<div class="r"><span>اليوم</span><b>${E(dl)}</b></div><div class="r"><span>الفترة</span><b>${E(p.period_label)}</b></div>
<div class="r"><span>الحلاق</span><b>${E(p.barber_name)}</b></div><div class="r"><span>الخدمات</span><b>${E((p.services||[]).join(" + "))}</b></div>
<div class="r"><span>الإجمالي</span><b class="t">${Math.round(p.total).toLocaleString("ar-EG")} جنيه</b></div>
${done?`<div class="ai-done">✓ تم الحجز — شوف دورك في «دوري»</div>`:`<div class="bt"><button class="ai-btn" data-ok="${i}">تأكيد الحجز ✓</button><button class="ai-btn g" data-no="${i}">إلغاء</button></div>`}</div>`}

function cfCard(c,i,k){const tail=c.s=="ok"?`<div class="ai-done">✓ ${E(c.msg||"تم")}</div>`:c.s=="x"?`<div class="ai-done" style="opacity:.7">اتلغت</div>`:`${c.needs_password?`<input type="password" id="ai-pw-${i}-${k}" placeholder="كلمة سر الموظف (6 حروف على الأقل)" autocomplete="new-password" maxlength="72">`:""}${c.err?`<div class="ai-err">⚠️ ${E(c.err)}</div>`:""}<div class="bt"><button class="ai-btn" data-cok="${i}:${k}" ${c.busy?"disabled":""}>${c.busy?"بنفّذ...":"تأكيد ✓"}</button><button class="ai-btn g" data-cno="${i}:${k}" ${c.busy?"disabled":""}>إلغاء</button></div>`;
return `<div class="ai-cf"><h4>⚠️ ${E(c.title)}</h4>${(c.lines||[]).map(l=>`<div class="l">${E(l)}</div>`).join("")}${tail}</div>`}
function draw(){const b=$a("ai-body");if(!b)return;let h="";
if(!S.msgs.length)h=`<div class="ai-hello"><div class="ai-orb">${ICON}</div><h3>أهلًا ${CUS?"بيك":ADM?"يا ريس":"يا بطل"} 👋</h3><div>${E(SUB())}</div>${ADM&&S.brief&&S.brief.lines&&S.brief.lines.length?`<div class="ai-br"><h4>ملخص دلوقتي</h4>${S.brief.lines.map(l=>`<div class="l ${l.level||""}">${E(l.icon||"")} ${E(l.text)}</div>`).join("")}</div>`:ADM&&S.brief===undefined?`<div class="ai-br"><div class="l" style="opacity:.6">بجهّز ملخص اليوم…</div></div>`:""}<div class="ai-chips">${((ADM&&S.brief&&S.brief.chips&&S.brief.chips.length?S.brief.chips:SUG())).map(s=>`<button class="ai-chip" data-q="${E(s)}">${E(s)}</button>`).join("")}</div></div>`;
S.msgs.forEach((m,i)=>{if(m.r=="u")h+=`<div class="ai-m u">${E(m.t)}</div>`;else{h+=`<div class="ai-m a">${md(m.t)}</div>`;if(m.p&&!m.x)h+=card(m.p,i,m.d);if(ADM&&m.cf)h+=m.cf.map((c,k)=>cfCard(c,i,k)).join("");if(ADM&&!mgrMode()&&m.dr&&m.dr.length)h+=`<div class="ai-dr">${m.dr.map((d,j)=>`<button data-dr="${i}:${j}">🔎 ${E(d.label)}</button>`).join("")}</div>`}});
if(S.busy)h+=`<div class="ai-dots" aria-label="بيكتب"><i></i><i></i><i></i></div>`;
b.innerHTML=h;b.scrollTop=b.scrollHeight}

async function send(t){t=String(t||"").trim();if(!t||S.busy)return;if(t.length>600)t=t.slice(0,600);
S.msgs.push({r:"u",t});S.busy=true;draw();save();const inp=$a("ai-in");if(inp){inp.value="";inp.style.height="auto"}$a("ai-snd")&&($a("ai-snd").disabled=true);
try{const h=S.msgs.slice(-10).map(m=>({role:m.r=="u"?"user":"assistant",content:m.t}));
const{data,error}=await sb.functions.invoke("assistant",{body:{messages:h}});
if(error||!data){S.msgs.push({r:"a",t:/not found|404|Failed to send|FunctionsFetch/i.test(String(error&&(error.message||error.name)))?"المساعد لسه مش متفعّل على السيرفر. قول لصاحب الصالون 🙏":"حصلت مشكلة في الاتصال، جرّب تاني 🙏"})}
else S.msgs.push({r:"a",t:data.reply||"معلش، مقدرتش أرد.",p:data.proposal||null,dr:Array.isArray(data.drills)?data.drills.slice(0,6):null,cf:ADM&&Array.isArray(data.confirms)&&data.confirms.length?data.confirms.slice(0,4).map(c=>({action:c.action,params:c.params,title:c.title,lines:c.lines,needs_password:!!c.needs_password})):null})}
catch(e){S.msgs.push({r:"a",t:"حصلت مشكلة في الاتصال، جرّب تاني 🙏"})}
S.busy=false;$a("ai-snd")&&($a("ai-snd").disabled=false);draw();save()}

const MONEY=n=>{n=Math.round(Number(n)||0);try{return n.toLocaleString("ar-EG")+" جنيه"}catch(e){return n+" جنيه"}};
async function showDrill(i,j){const m=S.msgs[i],d=m&&m.dr&&m.dr[j];const b=$a("ai-body");if(!d||!b)return;
b.innerHTML=`<div class="ai-dv"><div class="top"><button data-back="1">→ رجوع</button><b>${E(d.label)}</b></div><div class="sum">بحمّل الفواتير...</div></div>`;
const{data,error}=await sb.rpc("ai_invoices",{p_from:d.from,p_to:d.to,p_barber:d.barber_id||null,p_service:d.service||null,p_method:d.method||null,p_limit:50,p_names:true});
if(!$a("ai-body")||!$a("ai-body").querySelector(".ai-dv"))return;
if(error||!data){b.querySelector(".sum").textContent="مقدرتش أجيب الفواتير"+(error&&error.message?": "+error.message:"");return}
const L=data.invoices||[];
b.querySelector(".sum").innerHTML=`<b>${data.matching}</b> فاتورة · الإجمالي <b>${MONEY(data.matching_total)}</b>${data.matching>L.length?` · معروض آخر ${L.length}`:""}`;
b.querySelector(".ai-dv").insertAdjacentHTML("beforeend",L.length?L.map(x=>`<div class="ai-inv"><div class="h"><span>#${E(x.no)} · ${E(x.at)}</span><span>${MONEY(x.total)}</span></div><div class="m">${E(x.barber||"—")}${x.customer?" · "+E(x.customer):""} · ${E(x.method||"")}${Number(x.unpaid)>0?" · متبقي "+MONEY(x.unpaid):""}${Number(x.discount)>0?" · خصم "+MONEY(x.discount):""}</div><div class="m">${E((x.items||[]).join("، "))}</div></div>`).join(""):`<div class="ai-hello">مفيش فواتير مطابقة</div>`)}

async function confirmAct(i,k){const m=S.msgs[i],c=m&&m.cf&&m.cf[k];if(!c||c.s||c.busy)return;
let extra={};if(c.needs_password){const e=$a("ai-pw-"+i+"-"+k);const pw=e?e.value:"";if(pw.length<6){c.err="كلمة السر لازم 6 حروف على الأقل";draw();return}extra={password:pw}}
c.busy=true;c.err=null;draw();
try{const{data,error}=await sb.functions.invoke("assistant",{body:{execute:{action:c.action,params:c.params,extra}}});
if(error||!data){c.busy=false;c.err="الاتصال فشل — مش متأكد إن العملية اتنفّذت، راجع قبل ما تعيدها";draw();return}
c.busy=false;if(data.ok){c.s="ok";c.msg=data.message;c.needs_password=false}else c.err=data.message||"فشلت العملية"}
catch(e){c.busy=false;c.err="الاتصال فشل — مش متأكد إن العملية اتنفّذت، راجع قبل ما تعيدها"}
draw();save();try{if(c.s=="ok"&&typeof toast=="function")toast(c.msg)}catch(e){}}
async function confirmBook(i){const m=S.msgs[i];if(!m||!m.p||m.d)return;const bt=document.querySelector(`[data-ok="${i}"]`);if(bt){bt.disabled=true;bt.textContent="بحجزلك..."}
const p=m.p;const{error}=await sb.rpc("book_ticket",{p_barber:p.barber_id||null,p_day:p.day,p_period:p.period,p_services:p.service_ids});
if(error){if(bt){bt.disabled=false;bt.textContent="تأكيد الحجز ✓"}const msg=error.code=="23505"?"حد حجز قبلك، جرّب تاني":(error.message||"الحجز لم يتأكد");S.msgs.push({r:"a",t:"⚠️ الحجز ما اتأكدش: "+msg});draw();save();return}
m.d=1;S.msgs.push({r:"a",t:"تم حجزك ✓ هتلاقي رقم دورك والوقت المتوقع في «دوري». هبلّغك أول ما يقرب دورك."});draw();save();
try{if(typeof toast=="function")toast("تم الحجز ✓ ده رقم دورك")}catch(e){}}

async function loadBrief(){if(!ADM||S.briefBusy)return;S.briefBusy=true;try{const{data}=await sb.functions.invoke("assistant",{body:{brief:true}});S.brief=data&&data.ok&&data.brief?data.brief:null}catch(e){S.brief=null}S.briefBusy=false;if(S.open&&!S.msgs.length)draw()}
function open(){if(S.open)return;S.open=true;load();if(ADM&&S.brief===undefined)loadBrief();
const w=document.createElement("div");w.className="ai-bg";w.id="ai-bg";w.innerHTML=`<div class="ai-sheet" role="dialog" aria-modal="true" aria-label="${E(TITLE())}"><div class="ai-h"><div class="ai-orb">${ICON}</div><div><b>${E(TITLE())}</b><span>${E(SUB())}</span></div><button class="ai-x" aria-label="إغلاق" id="ai-x">✕</button></div><div class="ai-body" id="ai-body" aria-live="polite"></div><div class="ai-foot">${ADM?(mgrMode()?"بينفّذ بدالك وبيطلب تأكيدك على أي فلوس أو حاجة مش بترجع":"بيحلل وبينفّذ بدالك — الفلوس والحاجات الحساسة بتستنى تأكيدك"):"المساعد ممكن يغلط — راجع المهم مع الصالون"}</div><form class="ai-f" id="ai-f"><textarea id="ai-in" rows="1" maxlength="600" placeholder="اكتب سؤالك هنا..." aria-label="اكتب سؤالك"></textarea><button class="ai-send" id="ai-snd" type="submit" aria-label="إرسال">${SEND}</button></form></div>`;
document.body.appendChild(w);draw();
w.addEventListener("click",e=>{if(e.target===w)return close();const t=e.target.closest("button");if(!t)return;if(t.id=="ai-x")return close();if(t.dataset.q)return send(t.dataset.q);if(t.dataset.back)return draw();if(t.dataset.dr){const[a,c]=t.dataset.dr.split(":");return showDrill(+a,+c)}if(t.dataset.cok){const[a,c]=t.dataset.cok.split(":");return confirmAct(+a,+c)}if(t.dataset.cno){const[a,c]=t.dataset.cno.split(":"),q=S.msgs[+a]&&S.msgs[+a].cf&&S.msgs[+a].cf[+c];if(q&&!q.s&&!q.busy){q.s="x";draw();save()}return}if(t.dataset.ok!=null)return confirmBook(+t.dataset.ok);if(t.dataset.no!=null){const m=S.msgs[+t.dataset.no];if(m){m.x=1;S.msgs.push({r:"a",t:"تمام، لغيت الحجز ده. تحب نعدّل حاجة (اليوم أو الفترة أو الخدمات)؟"});draw();save()}}});
$a("ai-f").addEventListener("submit",e=>{e.preventDefault();send($a("ai-in").value)});
const inp=$a("ai-in");inp.addEventListener("input",()=>{inp.style.height="auto";inp.style.height=Math.min(inp.scrollHeight,110)+"px"});
inp.addEventListener("keydown",e=>{if(e.key=="Enter"&&!e.shiftKey&&!e.isComposing){e.preventDefault();send(inp.value)}});
document.addEventListener("keydown",esc);setTimeout(()=>inp.focus(),250)}
function esc(e){if(e.key=="Escape")close()}
function close(){const w=$a("ai-bg");if(w)w.remove();S.open=false;document.removeEventListener("keydown",esc)}

function fab(on){let b=$a("ai-fab");if(!b){const st=document.createElement("style");st.textContent=css;document.head.appendChild(st);b=document.createElement("button");b.id="ai-fab";b.className="ai-fab";b.setAttribute("aria-label",TITLE());b.innerHTML=ICON;b.onclick=open;document.body.appendChild(b)}b.classList.toggle("on",!!on)}
async function allowed(){if(!ADM)return true;try{const{data,error}=await sb.rpc("ai_mode");if(error&&/ai_mode|PGRST202|42883/.test(JSON.stringify(error))){const o=await sb.rpc("ai_admin_ok");S.mode=!o.error&&o.data===true?"owner":null;return !!S.mode}S.mode=(!error&&(data=="owner"||data=="manager"))?data:null;return !!S.mode}catch(e){S.mode=null;return false}}
async function init(){try{const{data:{session}}=await sb.auth.getSession();S.uid=session&&session.user&&session.user.id;fab(!!S.uid&&await allowed());
sb.auth.onAuthStateChange((ev,s)=>{const u=s&&s.user&&s.user.id;if(u!==S.uid){S.uid=u||null;S.msgs=[];if(!u)close()}if(!u)return fab(false);allowed().then(ok=>fab(ok))})}catch(e){}}
if(typeof sb!="undefined")init();else window.addEventListener("load",()=>{if(typeof sb!="undefined")init()});
window.salonAssistant={open,close};
})();
