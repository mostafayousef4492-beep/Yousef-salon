/* features/catalog/companies.js — الشركات والتعاقدات (خصومات الشركات) */

const coN=v=>{if(v===null)return null;const s=String(v).trim().replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace("٫",".");if(s==="")return"";const n=Number(s);return Number.isFinite(n)?n:NaN};
const coMissing=e=>e&&/company_|companies|my_company/i.test(e.message||"")&&/(does not exist|schema cache|Could not find)/i.test(e.message||"");
const coDate=v=>{const s=String(v||"").trim();return /^\d{4}-\d{2}-\d{2}$/.test(s)?s:(s===""?"":null)};

V.co=async function(){
const mgr=me.role=="owner"||me.role=="manager";
if(!mgr)return put(`<h1>الشركات والتعاقدات</h1><p class="m">الشاشة دي للإدارة بس.</p>`);
const d0=new Date(),f=C.coFrom||new Date(d0.getFullYear(),d0.getMonth(),1).toLocaleDateString("en-CA"),t=C.coTo||d0.toLocaleDateString("en-CA");C.coFrom=f;C.coTo=t;
const[L,R,S]=await Promise.all([sb.rpc("company_list"),sb.rpc("company_report",{p_from:f,p_to:t}),sb.from("services").select("id,name,active").order("name")]);
if(L.error)return put(`<h1>الشركات والتعاقدات</h1><button class="btn s g" onclick="go('stock')">← الخدمات والمخزون</button><p class="m" style="margin-top:10px">${coMissing(L.error)?"الشركات لسه مش متفعّلة: شغّل ملف patch_companies.sql في Supabase الأول.":esc(L.error.message)}</p>`);
C.cos=L.data||[];C.coSv=S.data||[];const rep={};(R.data||[]).forEach(x=>rep[x.id]=x);
put(`<h1>الشركات والتعاقدات</h1>
<div style="display:flex;gap:6px;flex-wrap:wrap;margin:6px 0"><button class="btn s g" onclick="go('stock')">← الخدمات والمخزون</button><button class="btn s" onclick="coEdit(null)">+ شركة جديدة</button></div>
<p class="m">أي موظف في الشركة يستفيد بالخصم. بيتحسب بعد خصم الباقة، وبيتسجّل على الفاتورة باسم الشركة واسم اللي طبّقه، من غير موافقة مدير.</p>
<div class="chips" style="align-items:center;margin:8px 0"><span class="m">التقرير من</span><input type="date" value="${f}" onchange="C.coFrom=this.value;V.co()" style="margin:0"><span class="m">إلى</span><input type="date" value="${t}" onchange="C.coTo=this.value;V.co()" style="margin:0"></div>`
+(C.cos.length?C.cos.map(c=>{const r=rep[c.id]||{};const st=!c.active?"موقوفة":(c.valid?"شغّالة":"خارج مدة الاتفاق");
return `<div class="box" style="margin-top:10px"><div class="row"><div><b>${esc(c.name)}</b> <span class="tag">${+c.pct}%</span> <span class="m">${st}</span>
<div class="m">الكود: <b dir="ltr">${esc(c.code||"")}</b> · من ${esc(c.start||"")}${c.end?" إلى "+esc(c.end):" (مفتوح)"}${c.max?" · أقصى خصم للفاتورة "+fm(c.max):""}${c.limit?" · "+c.limit+" مرات شهريًا للعميل":""}${c.bundles?"":" · مش على الباقات"}${(c.excluded||[]).length?" · "+c.excluded.length+" خدمة مستثناة":""}</div></div>
<div style="text-align:left"><button class="btn s g" onclick="coEdit(${c.id})">تعديل</button> <button class="btn s g" onclick="coToggle(${c.id})">${c.active?"إيقاف مؤقت":"تشغيل"}</button></div></div>
<div class="m" style="margin-top:6px">👥 ${c.members} مربوط بالحساب · مستفيدين ${r.beneficiaries||0} · استخدام ${r.uses||0} مرة</div>
<div class="m">مبيعات قبل الخصم <b>${fm(r.gross||0)}</b> · إجمالي الخصم <b>${fm(r.discounts||0)}</b> · الصافي <b>${fm(r.net||0)}</b></div>
${(r.top||[]).length?`<div class="m">أكتر خدمات: ${r.top.map(x=>esc(x.name)+" ("+x.qty+")").join("، ")}</div>`:""}
${c.notes?`<div class="m">ملاحظة: ${esc(c.notes)}</div>`:""}</div>`}).join(""):`<p class="m" style="margin-top:10px">مفيش شركات لسه. دوس «+ شركة جديدة».</p>`))};

async function coToggle(id){const c=(C.cos||[]).find(x=>x.id==id);if(!c)return;
if(!await askConfirm(c.active?"إيقاف خصم «"+c.name+"» مؤقتًا؟ الكاشير مش هيقدر يطبّقه لحد ما تشغّله تاني.":"تشغيل خصم «"+c.name+"»؟"))return;
const{error}=await sb.rpc("company_save",coArgs(c,{p_active:!c.active}));error?toast(error.message):(toast("تم ✓"),V.co())}

function coArgs(c,o){return{p_id:c.id,p_name:c.name,p_code:c.code,p_pct:c.pct,p_max:c.max,p_start:c.start,p_end:c.end,p_active:c.active,p_bundles:c.bundles,p_limit:c.limit,p_notes:c.notes,p_excluded:c.excluded||[],...(o||{})}}

async function coEdit(id){if(C.coBusy)return;const c=id?(C.cos||[]).find(x=>x.id==id):null;if(id&&!c)return;
const n=(await askInput("اسم الشركة",c?c.name:"")||"").trim();if(!n)return;
const pc=coN(await askInput("نسبة الخصم % (من الاتفاق)",c?String(+c.pct):"10"));if(pc===null)return;if(!(pc>0&&pc<=100))return toast("النسبة لازم تبقى أكبر من صفر ومش أكتر من 100");
const code=await askInput("كود الشركة (سيبه فاضي لو عايز البرنامج يولّد كود)",c?c.code:"");if(code===null)return;
const st=coDate(await askInput("بداية الاتفاق (YYYY-MM-DD) — فاضي = النهارده",c?c.start:""));if(st===null)return toast("التاريخ غلط");
const en=coDate(await askInput("نهاية الاتفاق (YYYY-MM-DD) — فاضي = مفتوح",c&&c.end?c.end:""));if(en===null)return toast("التاريخ غلط");
if(st&&en&&en<st)return toast("النهاية قبل البداية");
const mx=coN(await askInput("أقصى مبلغ خصم في الفاتورة الواحدة (فاضي = من غير حد)",c&&c.max?String(+c.max):""));if(mx===null)return;if(mx!==""&&!(mx>0))return toast("المبلغ غلط");
const lm=coN(await askInput("أقصى عدد مرات استفادة للعميل في الشهر (فاضي = من غير حد)",c&&c.limit?String(c.limit):""));if(lm===null)return;if(lm!==""&&!(lm>=1&&Number.isInteger(lm)))return toast("العدد غلط");
const bn=await askConfirm("الخصم متاح مع الباقات (يتجمّع مع خصم الباقة)؟\nإلغاء = لأ، مش على الباقات",{ok:"أيوه"});
const nt=await askInput("ملاحظات (اختياري)",c&&c.notes?c.notes:"");if(nt===null)return;
const ex=await coPickExcl(c?c.excluded||[]:[]);if(ex===null)return;
C.coBusy=1;const{error}=await sb.rpc("company_save",{p_id:c?c.id:null,p_name:n,p_code:code||null,p_pct:pc,p_max:mx===""?null:mx,p_start:st||null,p_end:en||null,p_active:c?c.active:true,p_bundles:bn,p_limit:lm===""?null:lm,p_notes:nt||null,p_excluded:ex});C.coBusy=0;
error?toast(/duplicate|unique/i.test(error.message)?"الاسم أو الكود مكرر":error.message):(toast("اتحفظ ✓"),V.co())}

// قائمة اختيار الخدمات المستثناة (نافذة بسيطة)
function coPickExcl(sel){return new Promise(res=>{const S=(C.coSv||[]).filter(s=>s.active||sel.includes(s.id)),o=document.createElement("div");
o.style.cssText="position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:9999;display:flex;align-items:center;justify-content:center;padding:16px";
o.innerHTML=`<div class="box" style="max-width:420px;width:100%;max-height:80vh;overflow:auto;background:var(--card,#fff)"><h3 class="sec">خدمات مش داخلة في الخصم</h3><p class="m">علّم على الخدمات اللي الخصم مايتطبّقش عليها (اختياري).</p>${S.map(s=>`<label class="row" style="cursor:pointer"><span>${esc(s.name)}</span><input type="checkbox" value="${s.id}" ${sel.includes(s.id)?"checked":""}></label>`).join("")}<div style="display:flex;gap:8px;margin-top:10px"><button class="btn" id="coOk" style="flex:1">تمام</button><button class="btn g" id="coNo" style="flex:1">إلغاء</button></div></div>`;
document.body.appendChild(o);const done=v=>{o.remove();res(v)};
o.querySelector("#coOk").onclick=()=>done([...o.querySelectorAll("input:checked")].map(i=>+i.value));o.querySelector("#coNo").onclick=()=>done(null)})}
