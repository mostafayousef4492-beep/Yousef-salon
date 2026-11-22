/* features/money/debts.js — الآجل والديون: ديون عملاء الصالون + آجل الكوفي + مستحقات الموردين في شاشة واحدة */

const dtAge=d=>Math.max(0,Math.floor((Date.now()-new Date(d).getTime())/864e5));
const dtTone=n=>n>30?"var(--red)":n>7?"var(--warn)":"var(--mute)";
const dtAgeTxt=n=>n==0?"النهارده":n==1?"من امبارح":"من "+num(n)+" يوم";

V.debt=async()=>{const adm=isAdm(me),pos=adm||can("use_pos"),cafe=typeof canCafe=="function"&&canCafe();
const[sd,cd,sp]=await Promise.all([pos?sb.rpc("debts_list"):{data:null},cafe?sb.rpc("cafe_debtors"):{data:null},adm?Promise.all([sb.from("suppliers").select("id,name,phone"),sb.from("purchases").select("supplier_id,total,paid"),sb.from("supplier_payments").select("supplier_id,amount")]):null]);
// ديون الصالون: بنجمّعها لكل عميل (أو لكل اسم مكتوب يدوي)
const G={};((sd&&sd.data)||[]).forEach(x=>{const k=x.customer_id?"c"+x.customer_id:"n"+x.name,g=G[k]=G[k]||{cid:x.customer_id,name:x.name,phone:x.phone,rem:0,oldest:x.created_at,n:0};g.rem+=+x.remaining;g.n++;if(new Date(x.created_at)<new Date(g.oldest))g.oldest=x.created_at});
const SL=Object.values(G).sort((a,b)=>new Date(a.oldest)-new Date(b.oldest)),sTot=SL.reduce((t,x)=>t+x.rem,0);
const CL=((cd&&cd.data)||[]).filter(x=>+x.balance>0).sort((a,b)=>+b.balance-+a.balance),cTot=CL.reduce((t,x)=>t+(+x.balance),0);
let PL=[],pTot=0;if(sp&&!sp[0].error){const bal={};(sp[1].data||[]).forEach(p=>{if(p.supplier_id)bal[p.supplier_id]=(bal[p.supplier_id]||0)+(+p.total)-(+p.paid)});(sp[2].data||[]).forEach(p=>{bal[p.supplier_id]=(bal[p.supplier_id]||0)-(+p.amount)});PL=(sp[0].data||[]).filter(s=>(bal[s.id]||0)>0.004).map(s=>({...s,bal:bal[s.id]})).sort((a,b)=>b.bal-a.bal);pTot=PL.reduce((t,x)=>t+x.bal,0)}
const oldD=SL.filter(x=>dtAge(x.oldest)>30),mid=SL.filter(x=>{const a=dtAge(x.oldest);return a>7&&a<=30});
const stat=(l,v,sub,on)=>`<button class="hm-stat" style="${on?"":"cursor:default"}" ${on?`onclick="${on}"`:""}><span class="hm-n" style="font-size:24px">${v}</span><span class="hm-l">${l}</span>${sub?`<span class="m" style="font-size:12px">${sub}</span>`:""}</button>`;
const msg=x=>`أهلاً ${x.name}، فاضل عليك ${fm(x.rem)} من زيارتك في ${C.cfg.salon_name||"الصالون"}. تقدر تسدد في أي وقت يناسبك. شكرًا ليك 🙏`;
put(`<h1>الآجل والديون</h1><p class="m">كل اللي ليك عند الناس واللي عليك للموردين في مكان واحد.</p>
<div class="hm-ops box" style="grid-template-columns:repeat(${1+(cafe?1:0)+(adm?1:0)},minmax(0,1fr))">${pos?stat("ديون عملاء الصالون",fm(sTot),num(SL.length)+" عميل"):""}${cafe?stat("آجل الكوفي",fm(cTot),num(CL.length)+" عميل","go('cafe_debt')"):""}${adm?stat("علينا للموردين",fm(pTot),num(PL.length)+" مورد","go('fin')"):""}</div>
${pos&&SL.length?`<div class="m" style="margin:10px 0 0">${oldD.length?`<span style="color:var(--red)">● ${num(oldD.length)} متأخر أكتر من 30 يوم</span> `:""}${mid.length?`<span style="color:var(--warn)">● ${num(mid.length)} من 8 لـ 30 يوم</span> `:""}<span>● ${num(SL.length-oldD.length-mid.length)} أقل من أسبوع</span></div>`:""}
${pos?`<h2>ديون عملاء الصالون</h2>`+(SL.length?SL.map(x=>{const a=dtAge(x.oldest);return `<div class="row"><div><b>${esc(x.name)}</b>${x.phone?` <span class="m" dir="ltr">${esc(x.phone)}</span>`:""}<div class="m"><span style="color:${dtTone(a)}">أقدم دين ${dtAgeTxt(a)}</span>${x.n>1?" · "+num(x.n)+" فواتير":""}${x.cid?"":" · مش مسجّل كعميل"}</div></div><div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;justify-content:flex-end"><b style="color:var(--red)">${fm(x.rem)}</b>${waBtn(x.phone,0,msg(x))}<button class="btn s" onclick="dbOpen(${x.cid||"null"})">سدّد</button></div></div>`}).join(""):`<p class="m">مفيش ديون على عملاء الصالون ✓</p>`):""}
${cafe?`<h2>آجل الكوفي</h2>`+(CL.length?CL.map(x=>{const a=x.last_at?dtAge(x.last_at):null;return `<div class="row"><div><b>${esc(x.name)}</b>${x.phone?` <span class="m" dir="ltr">${esc(x.phone)}</span>`:""}<div class="m">${a==null?"":`<span style="color:${dtTone(a)}">آخر حركة ${dtAgeTxt(a)}</span>`}</div></div><div style="display:flex;gap:6px;align-items:center"><b style="color:var(--red)">${fm(x.balance)}</b>${waBtn(x.phone,0,msg({name:x.name,rem:+x.balance}))}</div></div>`}).join("")+`<button class="btn g s" style="margin-top:6px" onclick="go('cafe_debt')">التحصيل وكشف الحساب</button>`:`<p class="m">مفيش آجل على عملاء الكوفي ✓</p>`):""}
${adm?`<h2>علينا للموردين</h2>`+(PL.length?PL.map(x=>`<div class="row"><div><b>${esc(x.name)}</b>${x.phone?` <span class="m" dir="ltr">${esc(x.phone)}</span>`:""}</div><b>${fm(x.bal)}</b></div>`).join("")+`<button class="btn g s" style="margin-top:6px" onclick="go('fin')">تسديد الموردين</button>`:`<p class="m">مفيش مستحقات للموردين ✓</p>`):""}`)};

// بعد أي سداد من نافذة الديون، الشاشة دي تتحدّث
(()=>{const p0=window.dbPay;if(typeof p0!="function")return;window.dbPay=async function(id){await p0(id);if(typeof tab!="undefined"&&tab=="debt")V.debt()}})();
