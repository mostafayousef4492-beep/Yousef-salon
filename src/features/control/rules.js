/* features/control/rules.js — مركز تحكم المالك */

// ===== مركز تحكم المالك: القواعد من rule_defs، والسيرفر بيتحقق ويسجّل كل تغيير =====

V.ctl=async()=>{if(me.role!="owner")return put(`<p class="m">للمالك بس.</p>`);await loadCfg();
const[{data:D,error},{data:H}]=await Promise.all([sb.from("rule_defs").select("*").order("sort"),sb.from("settings_history").select("*").order("id",{ascending:false}).limit(15)]);
if(error)return put(`<h1>مركز التحكم</h1><p class="m">${esc(error.message)}<br>شغّل patch_owner_control.sql في Supabase.</p>`);
C.RD=D||[];C.RH=H||[];C.rq="";put(`<h1>مركز التحكم</h1><p class="m">كل قاعدة ليها القيمة الحالية والافتراضية، وكل تغيير بيتسجّل.</p><button class="btn" style="width:100%;margin:6px 0" onclick="auditOpen()">🗂 الأرشيف الكامل (كل حركة اتعملت أو اتحذفت)</button><input placeholder="ابحث: خصم، كاشير، دفع، ولاء..." oninput="C.rq=this.value;$('rl').innerHTML=ruleRows()"><div id="rl">${ruleRows()}</div><h2>آخر التغييرات</h2>${C.RH.length?C.RH.map(h=>`<div class="row"><div><b>${esc((C.RD.find(d=>d.key==h.key)||{}).label||h.key)}</b><div class="m">${esc(JSON.stringify(h.old_value))} ← ${esc(JSON.stringify(h.new_value))}${h.reason?" · "+esc(h.reason):""}</div></div><span class="m">${new Date(h.changed_at).toLocaleString("ar-EG")}</span></div>`).join(""):`<p class="m">لسه مفيش تغييرات.</p>`}`)};

function ruleRows(){const q=(C.rq||"").trim().toLowerCase(),L=C.RD.filter(d=>!q||(d.label+d.grp+(d.kw||"")+(d.hint||"")).toLowerCase().includes(q));if(!L.length)return `<p class="m">مفيش قاعدة بالاسم ده.</p>`;let g="",h="";
L.forEach(d=>{if(d.grp!=g){g=d.grp;h+=`<h2>${esc(g)}</h2>`}const v=C.cfg[d.key]??d.def,df=JSON.stringify(d.def)==JSON.stringify(v);
h+=`<div class="box" style="margin-bottom:8px"><b>${esc(d.label)}</b>${d.hint?`<div class="m">${esc(d.hint)}</div>`:""}<div class="row" style="border:0;padding:6px 0">${d.kind=="bool"?`<input type="checkbox" id="r_${d.key}" ${v===true?"checked":""} style="width:22px;height:22px;margin:0">`:`<input id="r_${d.key}" ${d.kind=="list"?"":'type="number" step="any"'} value="${esc(v)}" style="margin:0">`}<button class="btn s" onclick="saveRule('${d.key}')">حفظ</button></div><div class="m">الافتراضي: ${d.kind=="bool"?(d.def?"شغّال":"موقوف"):esc(d.def)} ${df?"":`· <a href="#" style="color:var(--blue)" onclick="resetRule('${d.key}');return false">رجوع للافتراضي</a>`}</div></div>`});return h}

async function saveRule(k,val){const d=C.RD.find(x=>x.key==k),e=$("r_"+k);let v=val!==undefined?val:d.kind=="bool"?e.checked:d.kind=="list"?e.value.trim():+e.value;
if(d.danger&&!confirm("القاعدة دي حساسة: "+d.label+"\nهتتغير إلى: "+(d.kind=="bool"?(v?"شغّال":"موقوف"):v)+"\nمتأكد؟"))return;
const why=d.danger?prompt("سبب التغيير (اختياري)")||"":"";const{error}=await sb.rpc("owner_set_rule",{p_key:k,p_value:v,p_reason:why});error?toast(error.message):(toast("تم الحفظ ✓"),V.ctl())}

function resetRule(k){const d=C.RD.find(x=>x.key==k);saveRule(k,d.def)}
