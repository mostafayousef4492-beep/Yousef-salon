/* features/team/looks.js — ملف اللوك (نص): الحلاق بيشوفه للعميل اللي على تذكرته بس، والإدارة بتشوف الكل، والعميل بيشوف ملفه */

const LK_F=[["last_cut","آخر قصة","مثال: فيد / كلاسيك"],["clipper","رقم الماكينة","مثال: 2"],["grade","درجات التدريج","مثال: 1 على الجنب و 2 فوق"],["beard_style","شكل تحديد الدقن","مثال: تحديد حاد"],["notes","ملاحظات عن اللوك اللي بيحبه","اللي يخلّي الحلاق يفتكر بسرعة"]];
const lkHas=l=>!!l&&LK_F.some(f=>l[f[0]]);
const lkDate=l=>l&&l.updated_at?new Date(l.updated_at).toLocaleDateString("ar-EG",{day:"numeric",month:"long"}):"";
const lkVals=()=>LK_F.map(f=>($("lk_"+f[0])||{}).value||"");

function lookForm(l,saveCall,title){
  dsOpen(title,(l.wish_style?`<div class="box" style="margin-bottom:8px"><div class="m">الشكل اللي العميل عايزه (من تجربة القصة)</div><b>${esc(l.wish_style)}</b></div>`:"")+`<div class="m" style="margin-bottom:6px">${lkHas(l)?"آخر تحديث "+lkDate(l):"لسه مفيش ملف للعميل ده، اكتب اللي تعرفه."}</div>`
  +LK_F.map(f=>`<label class="m" style="display:block;margin-top:8px">${f[1]}</label>`+(f[0]=="notes"?`<textarea id="lk_${f[0]}" rows="3" maxlength="600" placeholder="${f[2]}">${esc(l[f[0]]||"")}</textarea>`:`<input id="lk_${f[0]}" maxlength="200" placeholder="${f[2]}" value="${esc(l[f[0]]||"")}">`)).join("")
  +`<button class="btn" style="width:100%;margin-top:12px" onclick="${saveCall}">حفظ</button>`)}

// الحلاق: لوك العميل اللي على تذكرته (الحماية في الداتابيز: تذكرته هو وحالتها لسه شغالة)
async function lookOpen(apptId){const{data,error}=await sb.rpc("look_for_ticket",{p_appt:apptId});if(error)return toast(error.message);lookForm(data||{},`lookSaveT(${apptId})`,"لوك العميل")}
async function lookSaveT(apptId){const v=lkVals(),{error}=await sb.rpc("look_save_for_ticket",{p_appt:apptId,p_last_cut:v[0],p_clipper:v[1],p_grade:v[2],p_beard:v[3],p_notes:v[4]});error?toast(error.message):(toast("اتحفظ اللوك ✓"),svcClose())}

// المالك/المدير: من صفحة العميل
async function lookAdmin(id){const{data,error}=await sb.rpc("look_get",{p_customer:id});if(error)return toast(error.message);lookForm(data||{},`lookSaveC(${id})`,"ملف اللوك")}
async function lookSaveC(id){const v=lkVals(),{error}=await sb.rpc("look_save",{p_customer:id,p_last_cut:v[0],p_clipper:v[1],p_grade:v[2],p_beard:v[3],p_notes:v[4]});error?toast(error.message):(toast("اتحفظ اللوك ✓"),svcClose())}

// العميل: ملفه (قراءة بس)
async function lookMine(){const{data,error}=await sb.rpc("my_look");if(error)return toast(error.message);const l=data||{};
  dsOpen("ملف اللوك بتاعي",(l.wish_style?`<div class="box" style="margin-bottom:8px"><div class="m">الشكل اللي عجبك</div><b>${esc(l.wish_style)}</b></div>`:"")+(lkHas(l)?`<div class="m" style="margin-bottom:6px">آخر تحديث ${lkDate(l)}. ده اللي الحلاق عارفه عن لوكك، فمش محتاج تشرح من الأول كل مرة.</div>`+LK_F.filter(f=>l[f[0]]).map(f=>`<div class="box" style="margin-top:8px"><div class="m">${f[1]}</div><b style="white-space:pre-wrap">${esc(l[f[0]])}</b></div>`).join(""):`<p class="m">لسه مفيش ملف للوك بتاعك. الحلاق هيسجّل اللي بتحبه في زيارتك الجاية، وهتلاقيه هنا.</p>`))}
