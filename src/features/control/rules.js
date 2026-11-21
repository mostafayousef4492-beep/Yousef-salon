/* features/control/rules.js — مركز تحكم المالك */

// ===== مركز تحكم المالك: القواعد من rule_defs، والسيرفر بيتحقق ويسجّل كل تغيير =====

// مركز التحكم اتدمج في الإعدادات: القواعد جوه كل موضوع، والرقابة في قسم الرقابة والأمان
V.ctl_rules=async()=>{if(me.role!="owner")return put(`<p class="m">للمالك بس.</p>`);await loadCfg();C.sec="safety";V.set()};

function ruleCard(d){const v=C.cfg[d.key]??d.def,df=JSON.stringify(d.def)==JSON.stringify(v);
return `<div class="box" style="margin-bottom:8px"><b>${esc(d.label)}</b>${d.hint?`<div class="m">${esc(d.hint)}</div>`:""}<div class="row" style="border:0;padding:6px 0">${d.kind=="bool"?`<input type="checkbox" id="r_${d.key}" ${v===true?"checked":""} style="width:22px;height:22px;margin:0">`:`<input id="r_${d.key}" ${d.kind=="list"?"":'type="number" step="any"'} value="${esc(v)}" style="margin:0">`}<button class="btn s" onclick="saveRule('${d.key}')">حفظ</button></div><div class="m">الافتراضي: ${d.kind=="bool"?(d.def?"شغّال":"موقوف"):esc(d.def)} ${df?"":`· <a href="#" style="color:var(--blue)" onclick="resetRule('${d.key}');return false">رجوع للافتراضي</a>`}</div></div>`}

function ruleRows(){const q=(C.rq||"").trim().toLowerCase(),L=C.RD.filter(d=>!q||(d.label+d.grp+(d.kw||"")+(d.hint||"")).toLowerCase().includes(q));if(!L.length)return `<p class="m">مفيش قاعدة بالاسم ده.</p>`;let g="",h="";
L.forEach(d=>{if(d.grp!=g){g=d.grp;h+=`<h2>${esc(g)}</h2>`}const v=C.cfg[d.key]??d.def,df=JSON.stringify(d.def)==JSON.stringify(v);
h+=`<div class="box" style="margin-bottom:8px"><b>${esc(d.label)}</b>${d.hint?`<div class="m">${esc(d.hint)}</div>`:""}<div class="row" style="border:0;padding:6px 0">${d.kind=="bool"?`<input type="checkbox" id="r_${d.key}" ${v===true?"checked":""} style="width:22px;height:22px;margin:0">`:`<input id="r_${d.key}" ${d.kind=="list"?"":'type="number" step="any"'} value="${esc(v)}" style="margin:0">`}<button class="btn s" onclick="saveRule('${d.key}')">حفظ</button></div><div class="m">الافتراضي: ${d.kind=="bool"?(d.def?"شغّال":"موقوف"):esc(d.def)} ${df?"":`· <a href="#" style="color:var(--blue)" onclick="resetRule('${d.key}');return false">رجوع للافتراضي</a>`}</div></div>`});return h}

async function saveRule(k,val){const d=C.RD.find(x=>x.key==k),e=$("r_"+k);let v=val!==undefined?val:d.kind=="bool"?e.checked:d.kind=="list"?e.value.trim():+e.value;
if(d.danger&&!await askConfirm("القاعدة دي حساسة: "+d.label+"\nهتتغير إلى: "+(d.kind=="bool"?(v?"شغّال":"موقوف"):v)+"\nمتأكد؟"))return;
const why=d.danger?await askInput("سبب التغيير (اختياري)")||"":"";const{error}=await sb.rpc("owner_set_rule",{p_key:k,p_value:v,p_reason:why});error?toast(error.message):(toast("تم الحفظ ✓"),(C.inHub?V.set():V.ctl_rules()))}

function resetRule(k){const d=C.RD.find(x=>x.key==k);saveRule(k,d.def)}
