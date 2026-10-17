/* features/team/late_rules.js — شاشة التحكم في طريقة خصم التأخير لكل موظف (للمالك) */
const LM={flat:"خصم الدقيقة",att:"أجر يوم بالحضور",adj:"تعديل بالساعات",none:"بدون خصم تأخير"};
async function lateRules(){
  const{data,error}=await sb.rpc("late_rules_list");
  if(error)return toast(error.code=="PGRST202"?"شغّل patch_late_deduction.sql في Supabase الأول":error.message);
  const g=data;
  dsOpen("خصم التأخير",`<div class="box" style="display:flex;flex-direction:column;gap:8px">
<label class="m"><input type="checkbox" id="lr_on" ${g.enabled?"checked":""}> تشغيل "خصم الدقيقة"</label>
<label class="m"><input type="checkbox" id="lr_w" ${g.wage_on?"checked":""}> نزّل اليومية أول ما الموظف يسجل حضور (ناقص خصم التأخير)</label>
<label class="m">دقايق السماح</label><input id="lr_g" type="number" inputmode="numeric" value="${+g.grace}">
<label class="m">الخصم لكل دقيقة (جنيه)</label><input id="lr_r" type="number" inputmode="decimal" value="${+g.rate}">
<div class="m">بعد السماح يتخصم من أول دقيقة. مثال: ${+g.grace+1} دقيقة تأخير = ${fm((+g.grace+1)*(+g.rate))}</div>
<button class="btn" onclick="lateGlobal()">حفظ</button></div>
<h2>طريقة الخصم لكل موظف</h2><div class="m" style="margin-bottom:6px">المالك والمدير مستثنيين. اختيار طريقة بيوقف التانية (من غير ما يمسح إعداداتها).</div>
${(g.staff||[]).map(s=>`<div class="row" style="flex-direction:column;align-items:stretch;gap:6px"><div><b>${esc(s.name)}</b> <span class="m">${RL[s.role]||s.role} · ${+s.wage>0?"يومية "+fm(s.wage):"مفيش يومية محددة"}</span></div>
<select onchange="lateSet('${s.id}',this.value)">${Object.keys(LM).map(k=>`<option value="${k}" ${s.method==k?"selected":""}>${LM[k]}</option>`).join("")}</select></div>`).join("")||`<p class="m">مفيش موظفين.</p>`}`);
}
async function lateGlobal(){
  const{error}=await sb.rpc("set_late_global",{p_enabled:$("lr_on").checked,p_grace:Math.round(+$("lr_g").value),p_rate:+$("lr_r").value,p_wage:$("lr_w").checked});
  error?toast(error.message):(toast("تم الحفظ ✓"),lateRules());
}
async function lateSet(id,m){
  const{error}=await sb.rpc("set_late_method",{p_staff:id,p_method:m});
  error?toast(error.message):toast("تم ✓ — "+LM[m]);
  lateRules();
}
