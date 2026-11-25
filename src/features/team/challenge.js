/* features/team/challenge.js — عجلة التحدي: شاشة الموظف (V.chw) + إدارة التحديات والمستويات (للمدير/المالك)
   اللف نفسه في challenge-run.js. التحديات والنقاط والحدود كلها بتتحدد من الإعدادات. */

/* ===== شاشة الموظف: العملاء الحاضرين + لفّ التحدي ===== */
V.chw=async function(){put(`<h1>عجلة التحدي</h1><p class="m">بنحمّل...</p>`);
  const{data,error}=await sb.rpc("challenge_present");
  if(error)return put(`<h1>عجلة التحدي</h1><p class="m">${/challenge_present|PGRST202|42883/.test(error.code+" "+error.message)?"الميزة لسه مش متفعّلة: شغّل patch_challenge_wheel.sql في Supabase.":esc(error.message)}</p>`);
  if(!data||!data.on)return put(`<h1>عجلة التحدي</h1><p class="m">العجلة مش شغّالة. شغّلها من الإعدادات ← المكافآت والولاء.</p>`);
  const L=data.list||[];window.chrOnClose=()=>{if(tab=="chw")V.chw()};
  put(`<h1>عجلة التحدي</h1><p class="m">العملاء الحاضرين دلوقتي. لفّ العجلة للعميل واعرض عليه التحدي، ولو وافق نفّذوه وأكّد.</p>${L.length?L.map(x=>`<div class="row"><div><b>${esc(x.customer||"عميل")}</b> <span class="tag">${esc(x.ticket||"")}</span><div class="m">مستواه: ${esc((x.level||{}).name||"مبتدئ")} · ${x.current?(x.current.status=="accepted"?"عنده تحدي مقبول":"عنده تحدي مستني رد"):(x.left_today>0?"جاهز للفة":"خلّص لفّات النهارده")}</div></div><button class="btn s" ${x.current||x.left_today>0?"":"disabled"} onclick="chrOpen(${x.appt},'${esc(x.customer||"").replace(/'/g,"")}',false)">${x.current?"كمّل":"🎯 لفّ"}</button></div>`).join(""):`<p class="m">مفيش عملاء حاضرين دلوقتي (لازم يتسجّل حضورهم أو يبقوا على الكرسي).</p>`}`)};

/* ===== إدارة التحديات (للمدير/المالك) ===== */
async function challengeAdmin(){dsOpen("🎯 عجلة التحدي — الإدارة",`<p class="m">بنحمّل...</p>`);
  const[a,b,r]=await Promise.all([sb.from("challenge_defs").select("*").order("sort").order("id"),sb.from("challenge_levels").select("*").order("min_points"),sb.rpc("challenge_report",{p_days:30})]);
  if(a.error)return dsOpen("🎯 عجلة التحدي — الإدارة",`<p class="m">${/challenge_defs|42P01|PGRST205/.test(a.error.code+" "+a.error.message)?"الميزة لسه مش متفعّلة: شغّل patch_challenge_wheel.sql في Supabase الأول.":esc(a.error.message)}</p>`);
  const D=a.data||[],Lv=b.data||[],rep=r.data||{},tot=D.filter(x=>x.active).reduce((t,x)=>t+(+x.weight||0),0);
  const K=[["fun","ترفيهي"],["barber","حلاقة"],["surprise","مفاجأة"]],RR=[["common","عادي"],["rare","نادر"],["legend","أسطوري"]];
  const opt=(L,v)=>L.map(x=>`<option value="${x[0]}" ${x[0]==v?"selected":""}>${x[1]}</option>`).join("");
  dsOpen("🎯 عجلة التحدي — الإدارة",`<p class="m">التشغيل والحدود (لفات اليوم، سقف النقاط الشهري، الصلاحية) من الإعدادات ← المكافآت والولاء. النقاط نقاط ولاء عادية بتتضاف بعد تأكيد الموظف (من التابلت أو حسابه).</p>
<div class="m" style="margin:8px 0">آخر 30 يوم: <b>${num(rep.spins||0)}</b> لفة · <b>${num(rep.done||0)}</b> اتنفّذ · <b>${num(rep.points_given||0)}</b> نقطة اتوزّعت · <b>${num(rep.pending||0)}</b> مستني تأكيد</div>
<h3>التحديات (نسبة الظهور = وزن التحدي ÷ مجموع الأوزان)</h3>
${D.map(x=>`<div class="row" style="flex-wrap:wrap;gap:6px"><input id="cd_t${x.id}" value="${esc(x.title)}" style="flex:1;min-width:150px"><select id="cd_k${x.id}">${opt(K,x.kind)}</select><select id="cd_r${x.id}">${opt(RR,x.rarity)}</select><input id="cd_p${x.id}" type="number" min="0" value="${x.points}" style="width:70px" title="النقاط"><input id="cd_w${x.id}" type="number" min="0" value="${x.weight}" style="width:60px" title="الوزن"><span class="m" style="min-width:40px">${tot>0&&x.active?(100*x.weight/tot).toFixed(1):0}%</span><label class="m"><input type="checkbox" id="cd_a${x.id}" ${x.active?"checked":""}> شغّال</label><button class="btn s" onclick="chdSave(${x.id})">حفظ</button><button class="btn s g" onclick="chdDel(${x.id})">مسح</button></div>`).join("")||`<p class="m">مفيش تحديات.</p>`}
<button class="btn g s" style="margin-top:8px" onclick="chdAdd()">+ تحدي جديد</button>
<h3 style="margin-top:16px">المستويات (حسب نقاط التحديات المؤكّدة)</h3>
${Lv.map(x=>`<div class="row" style="gap:6px"><input id="cl_n${x.id}" value="${esc(x.name)}" style="flex:1"><input id="cl_m${x.id}" type="number" min="0" value="${x.min_points}" style="width:90px" title="النقاط المطلوبة"><input id="cl_r${x.id}" type="number" min="0" max="5000" value="${x.reward_points||0}" style="width:90px" title="نقاط مكافأة الوصول للمستوى (مرة واحدة)" placeholder="مكافأة" ${"reward_points" in x?"":"disabled"}><button class="btn s" onclick="chlSave(${x.id})">حفظ</button><button class="btn s g" onclick="chlDel(${x.id})">مسح</button></div>`).join("")}
<button class="btn g s" style="margin-top:8px" onclick="chlAdd()">+ مستوى جديد</button>`)}
async function chdSave(id){const{error}=await sb.from("challenge_defs").update({title:$("cd_t"+id).value.trim()||"—",kind:$("cd_k"+id).value,rarity:$("cd_r"+id).value,points:Math.max(0,parseInt($("cd_p"+id).value)||0),weight:Math.max(0,parseInt($("cd_w"+id).value)||0),active:$("cd_a"+id).checked}).eq("id",id);error?toast(error.message):(toast("اتحفظ ✓"),challengeAdmin())}
async function chdAdd(){const{error}=await sb.from("challenge_defs").insert({title:"تحدي جديد",kind:"fun",rarity:"common",points:10,weight:1,sort:999});error?toast(error.message):challengeAdmin()}
async function chdDel(id){if(!await askConfirm("تمسح التحدي ده؟ (السجل القديم بيفضل)"))return;const{error}=await sb.from("challenge_defs").delete().eq("id",id);error?toast(error.message):challengeAdmin()}
async function chlSave(id){const{error}=await sb.from("challenge_levels").update({name:$("cl_n"+id).value.trim()||"—",min_points:Math.max(0,parseInt($("cl_m"+id).value)||0),...($("cl_r"+id)&&!$("cl_r"+id).disabled?{reward_points:Math.min(5000,Math.max(0,parseInt($("cl_r"+id).value)||0))}:{})}).eq("id",id);error?toast(error.message):(toast("اتحفظ ✓"),challengeAdmin())}
async function chlAdd(){const{error}=await sb.from("challenge_levels").insert({name:"مستوى جديد",min_points:1000,sort:99});error?toast(error.message):challengeAdmin()}
async function chlDel(id){if(!await askConfirm("تمسح المستوى ده؟"))return;const{error}=await sb.from("challenge_levels").delete().eq("id",id);error?toast(error.message):challengeAdmin()}
