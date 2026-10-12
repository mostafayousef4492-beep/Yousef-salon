/* features/auth/auth.js — الدخول والتسجيل */

async function signup(){const{error}=await sb.auth.signUp({email:$("em").value.trim(),password:$("pw").value,options:{data:{full_name:$("nm").value.trim()}}});if(error)return toast(error.message);toast("تم إنشاء الحساب");boot()}

const MAIL="@staff.abu-yousef-salon.com";

async function login(){const x=$("em").value.trim(),email=x.includes("@")?x:x+MAIL;const{error}=await sb.auth.signInWithPassword({email,password:$("pw").value});error?toast("الكود أو كلمة السر غلط"):boot()}

// كلمة سر العميل مشتقة من رقمه (لازم تطابق patch_customer_login.sql) — الرقم هو الهوية: مسجل قبل كده يدخل علطول، جديد يتسجل.

// كلمة سر حساب العميل = رقمه + الكود السري بتاعه (الكود بيتولّد مرة واحدة وبيتخزّن في السيرفر، والموظفين يقدروا يشوفوه أو يجدّدوه)
const CPW=(ph,code)=>"ay-"+ph+"-"+code,CMAIL=ph=>ph+"@c.abu-yousef-salon.com",CDIG=v=>String(v||"").replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/\D/g,"");
const genCode=()=>{const a=new Uint32Array(1);crypto.getRandomValues(a);return String(a[0]%1000000).padStart(6,"0")};

// دخول العميل: الموبايل + الكود (على جهاز جديد). على نفس الجهاز بيدخل لوحده.
async function loginCustomer(){const ph=CDIG($("cp").value),code=CDIG($("cc").value),bt=document.querySelector('[onclick="loginCustomer()"]');
if(!/^01\d{9}$/.test(ph))return toast("الموبايل لازم 11 رقم ويبدأ بـ 01");
if(code.length!=6)return toast("الكود 6 أرقام");
if(bt)bt.disabled=true;
try{const email=CMAIL(ph),pw=CPW(ph,code),r=await sb.auth.signInWithPassword({email,password:pw});
if(r.error)return toast("الموبايل أو الكود غلط — لو نسيت الكود كلّم الصالون");
try{localStorage.setItem("salon_cred",JSON.stringify({e:email,p:pw}))}catch(e){}
boot()}finally{if(bt)bt.disabled=false}}

// تسجيل أول مرة: النظام بيديله كود سري يظهر مرة واحدة ويتحفظ عند الصالون
async function regCustomer(){const n=$("cn").value.trim(),ph=CDIG($("cp").value),bt=document.querySelector('[onclick="regCustomer()"]');
if(n.length<2)return toast("اكتب اسمك");
if(!/^01\d{9}$/.test(ph))return toast("الموبايل لازم 11 رقم ويبدأ بـ 01");
if(bt)bt.disabled=true;
try{const email=CMAIL(ph),code=genCode(),pw=CPW(ph,code);
const sg=await sb.auth.signUp({email,password:pw,options:{data:{full_name:n}}});
if(sg.error)return toast(/registered|exists/i.test(sg.error.message)?"الرقم ده مسجّل قبل كده — اضغط «عندي حساب» وادخل كودك":sg.error.message);
if(!sg.data.user||!(sg.data.user.identities||[]).length)return toast("الرقم ده مسجّل قبل كده — اضغط «عندي حساب» وادخل كودك. لو نسيته كلّم الصالون");
if(!sg.data.session){const r=await sb.auth.signInWithPassword({email,password:pw});if(r.error)return toast(r.error.message)}
const e1=await sb.rpc("customer_code_save",{p_code:code});if(e1.error)return toast(e1.error.message);
const e2=await sb.rpc("register_customer",{p_name:n,p_phone:ph});if(e2.error)return toast(e2.error.message);
try{localStorage.setItem("salon_cred",JSON.stringify({e:email,p:pw}))}catch(e){}
codeScreen(code,ph,n)}finally{if(bt)bt.disabled=false}}

function codeScreen(code,ph,n){put(`<div class="hero"><div class="emblem">${ic("check")}</div><h1>أهلاً ${esc(n||"بيك")}</h1><div class="tagline">تم تسجيلك</div></div>
<div class="box" style="text-align:center"><div class="m">كودك السري للدخول من أي جهاز تاني</div><div class="code-big" dir="ltr">${esc(code)}</div><p class="m">احتفظ بيه، هتحتاجه مع رقم موبايلك لو دخلت من جهاز جديد. على الجهاز ده هتدخل علطول.</p>${waBtn(ph,1,"كودك للدخول على تطبيق "+C.cfg.salon_name+": "+code)}<button class="btn" style="width:100%;margin-top:10px" onclick="boot()">تمام، كمّل</button></div>`)}

function authMode(m){C.am=m;authView()}

function wrongPage(k){const M={staff:["تطبيق الموظفين","/staff"],admin:["تطبيق الإدارة","/admin"],customer:["تطبيق العملاء","/"]}[k];put(`<h1>الحساب ده مش لهنا</h1><p class="m">حسابك مخصص لـ${M[0]}.</p><div class="chips"><a class="btn" style="text-decoration:none" href="${M[1]}">${M[0]}</a><button class="btn g" onclick="sb.auth.signOut().then(()=>boot())">تسجيل خروج</button></div>`)}

function authView(){put(`<div class="hero"><div class="emblem">${ic("menu")}</div><h1>${esc(C.cfg.salon_name)}</h1><div class="tagline">${APP_MODE=="staff"?"تطبيق الموظفين":APP_MODE=="admin"?"لوحة الإدارة الشاملة":"حجز بدون انتظار · نقاط ولاء · تجربة راقية"}</div></div>`+(APP_MODE!="customer"?`<div class="box"><input id="em" placeholder="${APP_MODE=="admin"?"البريد الإلكتروني":"كود الموظف"}" autocomplete="username"><input id="pw" type="password" placeholder="كلمة السر" autocomplete="current-password"><button class="btn" style="width:100%" onclick="login()">دخول</button></div>`:(()=>{const m=C.am||"login";return `<div class="hubbar" role="tablist" style="margin-inline:auto"><button role="tab" aria-selected="${m=="login"}" class="chip ${m=="login"?"sel":""}" onclick="authMode('login')">عندي حساب</button><button role="tab" aria-selected="${m=="reg"}" class="chip ${m=="reg"?"sel":""}" onclick="authMode('reg')">أول مرة</button></div>`+(m=="login"?`<div class="box"><input id="cp" type="tel" inputmode="numeric" autocomplete="tel" placeholder="رقم موبايلك (01xxxxxxxxx)"><input id="cc" type="tel" inputmode="numeric" maxlength="6" autocomplete="one-time-code" placeholder="الكود السري (6 أرقام)"><button class="btn" style="width:100%" onclick="loginCustomer()">دخول</button><p class="m" style="text-align:center;margin:12px 0 0">الكود اتبعتلك أول مرة سجّلت. على جهازك اللي سجّلت عليه بتدخل لوحدك. نسيت الكود؟ كلّم الصالون.</p></div>`:`<div class="box"><input id="cn" placeholder="اسمك"><input id="cp" type="tel" inputmode="numeric" autocomplete="tel" placeholder="رقم موبايلك (01xxxxxxxxx)"><button class="btn" style="width:100%" onclick="regCustomer()">تسجيل</button><p class="m" style="text-align:center;margin:12px 0 0">هيظهرلك كود سري مرة واحدة، احتفظ بيه عشان تدخل من أي جهاز تاني.</p></div>`)})()))}
