/* features/team/hr.js — لائحة العمل والحوافز والجزاءات: تقييم أسبوعي، حافز 5% على الزيادة، مخالفات بسماع الحلاق، ومتابعة التأخير. أي خصم مالي بتأكيد الإدارة. */
const HR={tab:"eval",week:null,data:null};
const hrDays=(d,n)=>{const x=new Date(d+"T12:00:00Z");x.setUTCDate(x.getUTCDate()+n);return x.toISOString().slice(0,10)};
const hrSt={paid:"اتصرف",no_baseline:"لسه مفيش متوسط",cancelled:"ملغي (مخالفة مؤكدة)",no_eval:"مستني التقييم",no_increase:"مفيش زيادة",zero:"درجة التقييم أقل من 70",ready:"جاهز للصرف"};
const hrKind={major:"مخالفة جسيمة",absence:"غياب بدون إذن",conduct:"سلوك"};
const hrAct={none:"بدون إجراء",warning:"إنذار",final_warning:"إنذار نهائي",penalty:"جزاء مالي"};
const hrStep={warning:"إنذار",final_warning:"إنذار نهائي",penalty:"جزاء مالي بقرارك"};
const hrErr=e=>/hr_/i.test(e.message||"")&&/(does not exist|schema cache|Could not find)/i.test(e.message||"")?"اللائحة لسه مش متفعّلة: شغّل ملف patch_hr_policy.sql في Supabase.":esc(e.message||"حصل خطأ");
const hrNum=v=>{const s=String(v??"").trim().replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d));const n=Number(s);return s!==""&&Number.isFinite(n)?n:NaN};

V.hr=async function(){
if(!(me.role=="owner"||me.role=="manager"))return put(`<h1>اللائحة</h1><p class="m">الشاشة دي للإدارة بس.</p>`);
const{data:g,error}=await sb.rpc("hr_get");
if(error)return put(`<h1>اللائحة</h1><p class="m">${hrErr(error)}</p>`);
HR.data=g;if(!HR.week)HR.week=g.week;
const T=[["eval","التقييم"],["inc","الحوافز"],["vio","المخالفات"],["late","التأخير"],["rule","اللائحة"]];
const own=me.role=="owner";
let body="";
try{body=await hrBody(g,own)}catch(e){body=`<p class="m">${hrErr(e)}</p>`}
put(`<h1>لائحة الحوافز والجزاءات</h1>
<div class="tabs">${T.map(t=>`<button class="btn s ${HR.tab==t[0]?"":"g"}" onclick="hrTab('${t[0]}')">${t[1]}</button>`).join(" ")}</div>
${["eval","inc"].includes(HR.tab)?`<div class="row"><button class="btn s g" onclick="hrWeek(-7)">الأسبوع اللي قبله</button><b>أسبوع ${HR.week} ← ${hrDays(HR.week,6)}</b><button class="btn s g" onclick="hrWeek(7)">الأسبوع اللي بعده</button></div>`:""}
${body}`)};

async function hrBody(g,own){
const w=HR.week;
if(HR.tab=="eval"){
const{data,error}=await sb.rpc("hr_eval_list",{p_week:w});if(error)throw error;
return `<p class="m">التقييم من 100: الجودة 30، الالتزام بالمواعيد 25، النظافة 15، التعامل 20، التعاون 10. بيحدد نسبة الحافز: 90 فأكتر 100%، 80 لـ 89 تدي 75%، 70 لـ 79 تدي 50%، أقل من 70 مفيش حافز.</p>`+
(data.length?data.map(r=>{const e=r.eval;return `<div class="row"><div><b>${esc(r.name)}</b><div class="m">${e?`الجودة ${e.quality} · المواعيد ${e.punctuality} · النظافة ${e.hygiene} · التعامل ${e.manner} · التعاون ${e.coop}${e.note?" · "+esc(e.note):""}`:"لسه متقيّمش"}</div></div><div style="text-align:left">${e?`<b>${e.total}/100</b> `:""}<button class="btn s" onclick="hrEval('${r.staff_id}')">${e?"تعديل":"قيّم"}</button></div></div>`}).join(""):`<p class="m">مفيش حلاقين.</p>`)}
if(HR.tab=="inc"){
const{data,error}=await sb.rpc("hr_incentives",{p_week:w});if(error)throw error;
const p=g.policy;
return `<p class="m">الحافز = ${p.incentive_pct}% من الزيادة في عمولة الأسبوع عن متوسط آخر ${p.avg_weeks} أسابيع (من غير أسبوع فيه غياب بدون إذن)، × نسبة التقييم. لو فيه مخالفة جسيمة مؤكدة في الأسبوع الحافز بيتلغي.</p>`+
data.map(r=>`<div class="row"><div><b>${esc(r.name)}</b><div class="m">${hrSt[r.status]||r.status}${r.avg!=null?` · عمولة الأسبوع ${fm(r.week_commission)} · المتوسط ${fm(r.avg)} (${r.weeks_used} أسابيع)`:""}${r.eval_total!=null?` · تقييم ${r.eval_total} (${r.factor}%)`:""}</div></div><div style="text-align:left">${r.status=="ready"||r.status=="paid"?`<b>${fm(r.final)}</b> `:""}${r.status=="ready"?`<button class="btn s" onclick="hrPay('${r.staff_id}','${esc(r.name)}',${r.final})">صرف</button>`:""}</div></div>`).join("")}
if(HR.tab=="vio"){
const f=hrDays(g.week,-60),t=hrDays(g.week,7);
const{data,error}=await sb.rpc("hr_violation_list",{p_from:f,p_to:t});if(error)throw error;
return `<p class="m">اللائحة: مفيش جزاء على شكوى غير مثبتة. سجّل الواقعة، اسمع أقوال الحلاق، وبعدين أكّد أو الغي. جزاء واحد بس لكل مخالفة وبما يتناسب معها.</p>
<button class="btn" onclick="hrVioAdd()">تسجيل مخالفة</button>`+
(data.length?data.map(v=>`<div class="row"><div><b>${esc(v.name||"")} · ${hrKind[v.kind]||v.kind}</b><div class="m">${v.day} · ${esc(v.details)}${v.reply?`<br>أقواله: ${esc(v.reply)}`:""}<br>${v.status=="open"?"مستني قرارك":v.status=="dismissed"?"اتلغت":"اتأكدت: "+hrAct[v.action]+(v.action=="penalty"?" "+fm(v.amount):"")}</div></div><div style="text-align:left">${v.status=="open"?`<button class="btn s" onclick="hrVioDecide(${v.id},true)">تأكيد</button> <button class="btn s g" onclick="hrVioDecide(${v.id},false)">إلغاء</button>`:""}</div></div>`).join(""):`<p class="m">مفيش مخالفات مسجّلة.</p>`)}
if(HR.tab=="late"){
const{data,error}=await sb.rpc("hr_late_status",{p_month:null});if(error)throw error;
return `<p class="m">سماح ${g.policy.grace_min} دقيقة. أول تأخير في الشهر إنذار، تاني مرة إنذار نهائي، تالت مرة جزاء مالي بقرارك. بيبدأ من جديد كل شهر.</p>
${g.late_fine_on?`<p class="m" style="color:var(--warn,#c60)">تنبيه: الغرامة التلقائية للتأخير شغّالة في الإعدادات. لو هتمشي بتدرّج اللائحة اقفلها من الإعدادات، عشان ماتتحسبش مرتين.</p>`:""}`+
(data.length?data.map(r=>`<div class="row"><div><b>${esc(r.name)} · ${r.count} مرة</b><div class="m">${r.days.map(d=>d.day.slice(5)+" ("+d.min+" د)").join("، ")}</div></div><div style="text-align:left"><b>${hrStep[r.step]}</b>${r.step=="penalty"?` <button class="btn s" onclick="hrVioAdd('${r.staff_id}','conduct','تأخير متكرر ${r.count} مرات هذا الشهر')">سجّل مخالفة</button>`:""}</div></div>`).join(""):`<p class="m">مفيش تأخير فوق السماح الشهر ده.</p>`)}
const p=g.policy;
return `<p class="m">اللائحة بتتحكم في 3 حاجات هنا: الحافز الأسبوعي، المخالفات، التأخير. الأرقام دي بتاعتك:</p>
<div class="row"><div><b>نسبة الحافز</b><div class="m">من الزيادة عن المتوسط</div></div><div style="text-align:left"><b>${p.incentive_pct}%</b>${own?` <button class="btn s g" onclick="hrSet('incentive_pct','نسبة الحافز (%)')">تعديل</button>`:""}</div></div>
<div class="row"><div><b>عدد أسابيع المتوسط</b></div><div style="text-align:left"><b>${p.avg_weeks}</b>${own?` <button class="btn s g" onclick="hrSet('avg_weeks','عدد أسابيع المتوسط (1 إلى 12)')">تعديل</button>`:""}</div></div>
<div class="row"><div><b>سماح التأخير (دقيقة)</b></div><div style="text-align:left"><b>${p.grace_min}</b>${own?` <button class="btn s g" onclick="hrSet('grace_min','سماح التأخير بالدقايق')">تعديل</button>`:""}</div></div>
<h2>جدول التقييم</h2>${p.tiers.map(t=>`<div class="row"><div>${t[0]} درجة فأكتر</div><div><b>${t[1]}%</b></div></div>`).join("")}
<p class="m">الإجراءات المالية كلها (صرف حافز، جزاء) بتتسجّل بضغطة تأكيد منك أو من المدير، ومفيش حاجة بتتخصم لوحدها.</p>`}

function hrTab(t){HR.tab=t;V.hr()}
function hrWeek(n){HR.week=hrDays(HR.week,n);V.hr()}
async function hrSet(k,l){const v=hrNum(await askInput(l,String(HR.data.policy[k])));if(Number.isNaN(v)||v<0)return toast("الرقم غلط");
const{error}=await sb.rpc("hr_policy_save",{p:{[k]:v}});if(error)return toast(hrErr(error));toast("اتحفظ ✓");V.hr()}
async function hrEval(id){
const M=[["الجودة (من 30)",30],["الالتزام بالمواعيد (من 25)",25],["النظافة (من 15)",15],["التعامل مع العملاء (من 20)",20],["التعاون (من 10)",10]],s=[];
for(const m of M){const r=await askInput(m[0],"");if(r==null)return;const v=hrNum(r);if(Number.isNaN(v)||v<0||v>m[1])return toast("الدرجة لازم من 0 لـ "+m[1]);s.push(v)}
const note=await askInput("ملاحظة (اختياري)","",{multi:true});
const{data,error}=await sb.rpc("hr_eval_save",{p_staff:id,p_week:HR.week,p_q:s[0],p_p:s[1],p_h:s[2],p_m:s[3],p_c:s[4],p_note:note||null});
if(error)return toast(hrErr(error));toast("التقييم "+data+"/100 ✓");V.hr()}
async function hrPay(id,name,amt){if(!await askConfirm(`صرف حافز ${fm(amt)} لـ ${name} عن الأسبوع ده؟ هيتسجّل مكافأة غير مدفوعة في حسابه.`))return;
const{error}=await sb.rpc("hr_incentive_pay",{p_staff:id,p_week:HR.week});if(error)return toast(hrErr(error));toast("اتصرف ✓");V.hr()}
async function hrVioAdd(sid,kind,det){
const B=HR.data.barbers;let id=sid;
if(!id){const n=hrNum(await askInput("اختار الحلاق برقمه:\n"+B.map((b,i)=>(i+1)+" - "+b.name).join("\n"),""));if(!(n>=1&&n<=B.length))return toast("رقم غلط");id=B[n-1].id}
if(!kind){const k=hrNum(await askInput("نوع المخالفة:\n1 - جسيمة (تلاعب، اعتداء...)\n2 - غياب بدون إذن\n3 - سلوك أو التزام",""));if(![1,2,3].includes(k))return toast("رقم غلط");kind=["major","absence","conduct"][k-1]}
const d=det||await askInput("اكتب وقائع المخالفة بالتفصيل","",{multi:true});if(!d)return;
const{error}=await sb.rpc("hr_violation_add",{p_staff:id,p_day:null,p_kind:kind,p_code:null,p_details:d});if(error)return toast(hrErr(error));toast("اتسجّلت، مستنية قرارك ✓");HR.tab="vio";V.hr()}
async function hrVioDecide(id,ok){
if(!ok){if(!await askConfirm("إلغاء المخالفة؟ مش هتأثر على الحافز."))return;const r=await askInput("سبب الإلغاء (اختياري)","");
const{error}=await sb.rpc("hr_violation_decide",{p_id:id,p_confirm:false,p_reply:r||null,p_action:"none",p_amount:0});if(error)return toast(hrErr(error));return V.hr()}
const rep=await askInput("أقوال الحلاق (لازم تسمعه قبل التأكيد):","",{multi:true});if(!rep)return;
const a=hrNum(await askInput("الإجراء:\n1 - بدون إجراء\n2 - إنذار\n3 - إنذار نهائي\n4 - جزاء مالي",""));if(![1,2,3,4].includes(a))return toast("رقم غلط");
const act=["none","warning","final_warning","penalty"][a-1];let amt=0;
if(act=="penalty"){amt=hrNum(await askInput("مبلغ الجزاء (جنيه)",""));if(!(amt>0))return toast("المبلغ غلط");if(!await askConfirm(`خصم ${fm(amt)} من الحلاق؟ هيتسجّل في حسابه.`))return}
const{error}=await sb.rpc("hr_violation_decide",{p_id:id,p_confirm:true,p_reply:rep,p_action:act,p_amount:amt});if(error)return toast(hrErr(error));toast("اتأكدت ✓");V.hr()}
