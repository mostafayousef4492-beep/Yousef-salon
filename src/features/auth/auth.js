/* features/auth/auth.js — الدخول والتسجيل */

async function signup(){const{error}=await sb.auth.signUp({email:$("em").value.trim(),password:$("pw").value,options:{data:{full_name:$("nm").value.trim()}}});if(error)return toast(error.message);toast("تم إنشاء الحساب");boot()}

const MAIL="@staff.abu-yousef-salon.com";

async function login(){const x=$("em").value.trim(),email=x.includes("@")?x:x+MAIL;const{error}=await sb.auth.signInWithPassword({email,password:$("pw").value});error?toast("الكود أو كلمة السر غلط"):boot()}

// ===== دخول العميل =====
// كلمة سر الحساب سر عشوائي بيتولّد على الجهاز ويتخزّن فيه بس (salon_cred) — مش مشتقة من الرقم، فمعرفة الرقم لوحدها مش كفاية.
// جهاز جديد: الموبايل + كود من 6 أرقام يطلّعه الكاشير (صالح 15 دقيقة، 5 محاولات) → claim_login بيربط الحساب بجهاز جديد.
const CMAIL=ph=>ph+"@c.abu-yousef-salon.com",CDIG=v=>String(v||"").replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/\D/g,"");
const devSecret=()=>{const a=new Uint8Array(24);crypto.getRandomValues(a);return Array.from(a,b=>b.toString(16).padStart(2,"0")).join("")};
const saveCred=(e,p)=>{try{localStorage.setItem("salon_cred",JSON.stringify({e,p}))}catch(x){}};

// جهاز جديد: الموبايل + كود الكاشير
async function loginCustomer(){const ph=CDIG($("cp").value),code=CDIG($("cc").value),bt=document.querySelector('[onclick="loginCustomer()"]');
if(!/^01\d{9}$/.test(ph))return toast("الموبايل لازم 11 رقم ويبدأ بـ 01");
if(code.length!=6)return toast("الكود 6 أرقام");
if(bt)bt.disabled=true;
try{const pw=devSecret(),ok=await sb.rpc("claim_login",{p_phone:ph,p_code:code,p_new_pw:pw});
if(ok.error||ok.data!==true)return toast("الموبايل أو الكود غلط أو الكود خلص — اطلب كود جديد من الكاشير");
const email=CMAIL(ph),r=await sb.auth.signInWithPassword({email,password:pw});
if(r.error)return toast("تعذّر الدخول، جرّب تاني");
saveCred(email,pw);boot()}finally{if(bt)bt.disabled=false}}

// تسجيل أول مرة. لو الرقم متسجّل قبل كده بيتحوّل لشاشة الكود بدل ما يتسجّل تاني.
async function regCustomer(){const n=$("cn").value.trim(),ph=CDIG($("cp").value),bt=document.querySelector('[onclick="regCustomer()"]');
if(n.length<2)return toast("اكتب اسمك");
if(!/^01\d{9}$/.test(ph))return toast("الموبايل لازم 11 رقم ويبدأ بـ 01");
if(bt)bt.disabled=true;
const dup=()=>{toast("الرقم ده مسجّل قبل كده — ادخل بكود من الكاشير");authMode("login")};
try{const email=CMAIL(ph),pw=devSecret();
const sg=await sb.auth.signUp({email,password:pw,options:{data:{full_name:n}}});
if(sg.error)return /registered|exists/i.test(sg.error.message)?dup():toast(sg.error.message);
if(!sg.data.user||!(sg.data.user.identities||[]).length)return dup();
if(!sg.data.session){const r=await sb.auth.signInWithPassword({email,password:pw});if(r.error)return toast(r.error.message)}
saveCred(email,pw);
const e2=await sb.rpc("register_customer",{p_name:n,p_phone:ph});
if(e2.error){toast(e2.error.message);await sb.auth.signOut();try{localStorage.removeItem("salon_cred")}catch(x){}return}
if(e2.data===0)C.claimWait=1;
boot()}finally{if(bt)bt.disabled=false}}

// حسابات قديمة كانت كلمة سرها معادلة ثابتة من الرقم: أول ما صاحبها يفتح التطبيق على جهازه نبدّلها بسر عشوائي.
async function migrateLegacyCred(){let cr=null;try{cr=JSON.parse(localStorage.getItem("salon_cred"))}catch(e){}
if(!cr||!/^ay-\d+-c9f3a1$/.test(cr.p||""))return;
const pw=devSecret(),{error}=await sb.auth.updateUser({password:pw});if(!error)saveCred(cr.e,pw)}

function authMode(m){C.am=m;authView()}

function wrongPage(k){const M={staff:["تطبيق الموظفين","/staff"],admin:["تطبيق الإدارة","/admin"],customer:["تطبيق العملاء","/"]}[k];put(`<h1>الحساب ده مش لهنا</h1><p class="m">حسابك مخصص لـ${M[0]}.</p><div class="chips"><a class="btn" style="text-decoration:none" href="${M[1]}">${M[0]}</a><button class="btn g" onclick="sb.auth.signOut().then(()=>boot())">تسجيل خروج</button></div>`)}

function authView(){put((C.claimWait?`<div class="box"><b>الرقم ده ليه سجل عند الصالون</b><div class="m">طلب ربط حسابك اتبعت. اطلب من الكاشير يوافق عليه، أو يطلّعلك كود دخول — وبعدها ادخل هنا.</div></div>`:"")+`<div class="hero"><div class="emblem">${ic("menu")}</div><h1>${esc(C.cfg.salon_name)}</h1><div class="tagline">${APP_MODE=="staff"?"تطبيق الموظفين":APP_MODE=="admin"?"لوحة الإدارة الشاملة":"حجز بدون انتظار · نقاط ولاء · تجربة راقية"}</div></div>`+(APP_MODE!="customer"?`<div class="box"><input id="em" placeholder="${APP_MODE=="admin"?"البريد الإلكتروني":"كود الموظف"}" autocomplete="username"><input id="pw" type="password" placeholder="كلمة السر" autocomplete="current-password"><button class="btn" style="width:100%" onclick="login()">دخول</button></div>`:(()=>{const m=C.am||"login";return `<div class="hubbar" role="tablist" style="margin-inline:auto"><button role="tab" aria-selected="${m=="login"}" class="chip ${m=="login"?"sel":""}" onclick="authMode('login')">عندي حساب</button><button role="tab" aria-selected="${m=="reg"}" class="chip ${m=="reg"?"sel":""}" onclick="authMode('reg')">أول مرة</button></div>`+(m=="login"?`<div class="box"><input id="cp" type="tel" inputmode="numeric" autocomplete="tel" placeholder="رقم موبايلك (01xxxxxxxxx)"><input id="cc" type="tel" inputmode="numeric" maxlength="6" autocomplete="one-time-code" placeholder="كود الدخول من الكاشير (6 أرقام)"><button class="btn" style="width:100%" onclick="loginCustomer()">دخول</button><p class="m" style="text-align:center;margin:12px 0 0">على جهازك اللي سجّلت عليه بتدخل لوحدك. من جهاز جديد: اطلب من الكاشير كود دخول (صالح 15 دقيقة) وادخله هنا.</p></div>`:`<div class="box"><input id="cn" placeholder="اسمك"><input id="cp" type="tel" inputmode="numeric" autocomplete="tel" placeholder="رقم موبايلك (01xxxxxxxxx)"><button class="btn" style="width:100%" onclick="regCustomer()">تسجيل</button><p class="m" style="text-align:center;margin:12px 0 0">حسابك بيتربط بالجهاز ده. لو دخلت من جهاز تاني هتحتاج كود من الكاشير.</p></div>`)})()))}
