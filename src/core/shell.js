/* core/shell.js — التشغيل والتنقل */

async function boot(){
await loadCfg();
const{data:{session}}=await sb.auth.getSession();
if(!session){let cr=null;try{cr=JSON.parse(localStorage.getItem("salon_cred"))}catch(e){}
if(cr&&APP_MODE=="customer"){const r=await sb.auth.signInWithPassword({email:cr.e,password:cr.p});if(!r.error)return boot()}
return authView()}
const{data:p}=await sb.from("profiles").select(PCOLS).eq("id",session.user.id).single();
me=p||{role:"customer",full_name:session.user.email,id:session.user.id};
const staff=["owner","manager","cashier","barber","assistant"].includes(me.role);
const whose=isAdm(me)?"admin":staff?"staff":"customer";if(whose!=APP_MODE)return wrongPage(whose);
const own=isAdm(me);
if(staff){const T=staffTabs(me);if(own||(me.role=="cashier"&&(can("use_pos")||can("manage_appts")))){T.unshift(["home","الرئيسية"]);const PRI=["home","pos","appts","cust"];T.sort((a,b)=>{const x=PRI.indexOf(a[0]),y=PRI.indexOf(b[0]);return(x<0?99:x)-(y<0?99:y)})}if(own){T.push(["svc","الخدمات"],["fin","المصروفات والرواتب"],["team","الموظفين"],["att","الحضور"]);if(me.role=="owner")T.push(["ctl","مركز التحكم"]);T.push(["set","الإعدادات"])}const HT=hubTabs(T);C.hubs=HT.hubs;HT.tabs.sort((a,b)=>{const x=TAB_ORDER.indexOf(a[0]),y=TAB_ORDER.indexOf(b[0]);return(x<0?99:x)-(y<0?99:y)});C.tabs=[...HT.tabs,["out","خروج"]];go(T[0]?T[0][0]:"none");annCount()}
else{const{data:cu}=await sb.from("customers").select("id").eq("user_id",session.user.id).maybeSingle();if(!cu)return authView("c");C.tabs=[["book","احجز"],["queue","دوري"],["mine","حجوزاتي"],["loy","حسابي"]];go("book")}}

function go(t){clearInterval(C.poll);if(t=="out"){C.hubBar="";try{localStorage.removeItem("salon_cred")}catch(e){}pushUnlink().finally(()=>sb.auth.signOut().then(()=>{$("nav").innerHTML="";authView()}));return}
let hb=null;if(C.hubs){if(C.hubs[t]){hb=t;t=(C.hubLast||{})[hb]||C.hubs[hb][0][0]}else for(const k in C.hubs)if(C.hubs[k].some(x=>x[0]==t)){hb=k;break}}
if(hb){(C.hubLast=C.hubLast||{})[hb]=t;C.hubBar=`<div class="hubbar" role="tablist">${C.hubs[hb].map(x=>`<button role="tab" aria-selected="${x[0]==t}" class="chip ${x[0]==t?"sel":""}" onclick="go(\'${x[0]}\')">${x[1]}</button>`).join("")}</div>`}else C.hubBar="";
tab=t;$("app").classList.remove("still");$("app").dataset.tab=t;drawNav(hb||t);put(SK);scrollTo(0,0);if(typeof annDot=="function")annDot();V[t]()}

// القائمة: شريط سفلي على الموبايل، وقائمة جانبية على الكمبيوتر (نفس العناصر ونفس الترتيب)
function drawNav(act){const T=C.tabs||[],isPin=x=>NAV_PINNED.includes(x[0]),main=T.filter(x=>!isPin(x)&&x[0]!="out"),pin=T.filter(isPin),out=T.filter(x=>x[0]=="out"),ord=[...main,...pin,...out],NV=ord.length>6?5:ord.length;
let h=(ord.length>NV?'<i class="brk"></i>':"")+`<div class="nav-brand"><span class="nav-logo">${ic("menu")}</span><div><b>${esc(C.cfg.salon_name)}</b><span>${APP_MODE=="admin"?"لوحة الإدارة":APP_MODE=="staff"?"تطبيق الموظفين":"احجز دورك"}</span></div></div>`;
ord.forEach((x,i)=>{if(i==main.length&&i>0)h+='<i class="navsp"></i>';
h+=`<button class="${(x[0]==act?"on":"")+(i>=NV?" x":"")+(isPin(x)||x[0]=="out"?" pin":"")}" data-v="${(x[3]||[x[0]]).join(" ")}" onclick="go('${x[0]}')">${ic(x[2]||x[0])}<span>${x[1]}</span></button>`});
if(ord.length>NV)h+=`<button class="more${ord.slice(NV).some(x=>x[0]==act)?" on":""}" aria-label="المزيد" onclick="event.stopPropagation();$('nav').classList.toggle('open')">${ic("dot3")}<span>المزيد</span></button>`;
h+=`<button class="themebtn" onclick="toggleTheme()" aria-label="تبديل الوضع الفاتح والداكن"><span class="ti-sun">${ic("sun")}</span><span class="ti-moon">${ic("moon")}</span><span>تبديل الوضع</span></button>`;
$("nav").className="";$("nav").innerHTML=h}

const put=h=>{$("app").innerHTML=(C.hubBar||"")+h;polish()};

function polish(){const A=$("app");A.querySelectorAll(".tag").forEach(t=>{const k=Object.keys(ST).find(x=>ST[x]==t.textContent.trim());if(k)t.classList.add("st-"+k)});A.querySelectorAll(":scope>p.m").forEach(p=>{if(/^(مفيش|لسه|لا يوجد|ما فيش)/.test(p.textContent.trim()))p.classList.add("empty")})}

// ===== الإعدادات =====

V.none=()=>put(`<h1>حسابك متسجل ✓</h1><p class="m">المالك لسه ما فعّلش صلاحيات لحسابك. كلّمه يفتحها لك.</p>`);
