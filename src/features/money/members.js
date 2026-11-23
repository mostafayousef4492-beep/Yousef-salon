/* features/money/members.js — ABO YOUSEF MEMBERSHIP: شاشة الاشتراكات للكاشير والإدارة
   الكاشير/المدير: شحن رصيد لعميل + عرض رصيده. المدير: الباقات، كل الحسابات، تصحيح بحركة عكسية، تجميد/فك/قفل.
   الحسابات والتسوية كلها في السيرفر (patch_membership.sql). الشحن الكاش بيتسجّل إيداع في الدرج، مش مبيعات. */

const MB={plans:[],cust:null};
const mbN=n=>Number(+n||0).toLocaleString("ar-EG",{maximumFractionDigits:2});
const mbNeed=e=>/member_|PGRST202|42883|42P01|PGRST205/.test((e.code||"")+" "+(e.message||""))?"الميزة لسه مش متفعّلة: شغّل patch_membership.sql في Supabase.":esc(e.message||"");
const MB_ST={active:"شغّال",frozen:"مجمّد",expired:"منتهي",closed:"مقفول"};

V.mbr=async function(){put(`<h1>الاشتراكات</h1><p class="m">بنحمّل...</p>`);
  const pl=await sb.from("member_plans").select("*").order("sort").order("id");
  if(pl.error)return put(`<h1>الاشتراكات</h1><p class="m">${mbNeed(pl.error)}</p>`);
  MB.plans=pl.data||[];const adm=isAdm(me);let L=null;
  if(adm){const r=await sb.rpc("member_list");if(!r.error)L=r.data}
  put(`<h1>الاشتراكات</h1><p class="m">شحن رصيد العميل بيتحول لرصيد أساسي + هدية. الكاش بيدخل الدرج كإيداع (مش مبيعات). التفاصيل والدفع من الرصيد عند الكاشير في المرحلة الجاية.</p>
<div class="box"><b>شحن رصيد</b><input id="mb_ph" type="tel" inputmode="numeric" placeholder="رقم موبايل العميل 01xxxxxxxxx" style="margin-top:6px"><button class="btn s" style="margin-top:6px" onclick="mbFind()">دوّر</button><div id="mb_res"></div></div>
${L?`<div class="box" style="margin-top:10px"><div class="row"><span>اشتراكات</span><b>${mbN(L.totals.accounts)}</b></div><div class="row"><span>أرصدة أساسية عند العملاء</span><b>${mbN(L.totals.paid)}</b></div><div class="row"><span>هدايا قائمة</span><b>${mbN(L.totals.bonus)}</b></div><div class="row"><span>خصومات الهدية آخر 30 يوم</span><b>${mbN(L.penalties_30d)}</b></div><div class="m">الأرصدة الأساسية التزام على الصالون لحد ما العميل يستهلكها.</div></div>
<h2>الحسابات</h2>${(L.rows||[]).length?L.rows.map(r=>`<div class="row" style="cursor:pointer" onclick="mbOpenCust(${r.customer_id})"><div><b>${esc(r.name)}</b> <span class="tag">${MB_ST[r.status]||r.status}</span><div class="m">${esc(r.plan)} · صالح لحد ${esc(r.expires_on)}</div></div><div style="text-align:left"><b>${mbN(+r.paid+ +r.bonus)}</b><div class="m">${mbN(r.paid)} + ${mbN(r.bonus)}</div></div></div>`).join(""):`<p class="m">مفيش اشتراكات لسه.</p>`}`:""}
${adm?mbPlansHtml():""}`)};

function mbPlansHtml(){return `<h2>الباقات</h2>${MB.plans.map(p=>`<div class="box" style="margin-bottom:8px"><div class="row" style="gap:6px;flex-wrap:wrap"><input id="mp_n${p.id}" value="${esc(p.name)}" style="flex:1;min-width:130px"><label class="m"><input type="checkbox" id="mp_a${p.id}" ${p.active?"checked":""}> شغّالة</label></div>
<div class="row" style="gap:6px;flex-wrap:wrap"><label class="m">السعر <input id="mp_p${p.id}" type="number" min="1" value="${p.price}" style="width:90px"></label><label class="m">الهدية <input id="mp_b${p.id}" type="number" min="0" value="${p.bonus}" style="width:90px"></label><label class="m">زيارات/أسبوع <input id="mp_w${p.id}" type="number" min="1" max="14" value="${p.weekly_visits}" style="width:60px"></label><label class="m">خصم % <input id="mp_c${p.id}" type="number" min="0" max="100" value="${p.penalty_pct}" style="width:60px"></label><label class="m">صلاحية (يوم) <input id="mp_d${p.id}" type="number" min="1" value="${p.valid_days}" style="width:70px"></label></div>
<button class="btn s" onclick="mpSave(${p.id})">حفظ</button></div>`).join("")}<button class="btn g s" onclick="mpAdd()">+ باقة جديدة</button><div class="m" style="margin-top:6px">تعديل الباقة بيسري على الشحن الجديد بس. حسابات العملاء الحالية بتتحدّث شروطها وقت أول شحن بعد التعديل.</div>`}
async function mpSave(id){const g=k=>$("mp_"+k+id),{error}=await sb.from("member_plans").update({name:g("n").value.trim()||"باقة",price:Math.max(1,+g("p").value||1),bonus:Math.max(0,+g("b").value||0),weekly_visits:Math.min(14,Math.max(1,parseInt(g("w").value)||2)),penalty_pct:Math.min(100,Math.max(0,+g("c").value||0)),valid_days:Math.max(1,parseInt(g("d").value)||90),active:g("a").checked}).eq("id",id);error?toast(error.message):(toast("اتحفظ ✓"),V.mbr())}
async function mpAdd(){const{error}=await sb.from("member_plans").insert({name:"باقة جديدة",price:500,bonus:100,weekly_visits:2,penalty_pct:25,valid_days:90,sort:999});error?toast(error.message):V.mbr()}

async function mbFind(){const o=$("mb_res"),ph=($("mb_ph").value||"").replace(/\D/g,"");if(!/^01\d{9}$/.test(ph)){o.innerHTML=`<div class="m" style="color:var(--red)">الرقم لازم يبدأ بـ 01 ويبقى 11 رقم</div>`;return}
  o.innerHTML=`<div class="m">بندوّر...</div>`;const{data,error}=await sb.from("customers").select("id,name,phone").in("phone",[ph,"+2"+ph,"2"+ph]).order("id").limit(1);
  if(error)return o.innerHTML=`<div class="m" style="color:var(--red)">${esc(error.message)}</div>`;
  if(!data||!data[0])return o.innerHTML=`<div class="m">مفيش عميل بالرقم ده. سجّله الأول من شاشة الكاشير.</div>`;mbOpenCust(data[0].id,data[0].name)}

async function mbOpenCust(id,nm){MB.cust=id;dsOpen("💳 اشتراك العميل",`<p class="m">بنحمّل...</p>`);
  const{data:d,error}=await sb.rpc("member_get",{p_customer:id});if(error)return dsOpen("💳 اشتراك العميل",`<p class="m">${mbNeed(error)}</p>`);
  const adm=isAdm(me),act=(MB.plans||[]).filter(p=>p.active);
  dsOpen("💳 اشتراك العميل",`${nm?`<b>${esc(nm)}</b>`:""}${d?`<div class="box" style="margin-top:8px"><div class="m">${esc(d.plan)} · ${MB_ST[d.status]||d.status} · صالح لحد ${esc(d.expires_on)}</div><div class="row"><span>أساسي</span><b>${mbN(d.paid)}</b></div><div class="row"><span>هدية</span><b>${mbN(d.bonus)}</b></div><div class="row"><span>زيارات الأسبوع</span><b>${d.visits} / ${d.required}</b></div></div>`:`<p class="m">مفيش اشتراك للعميل ده لسه.</p>`}
<h3 style="margin-top:12px">شحن</h3>${act.length?`<select id="mb_plan">${act.map(p=>`<option value="${p.id}">${esc(p.name)} — ${mbN(p.price)} + هدية ${mbN(p.bonus)}</option>`).join("")}</select><select id="mb_m" style="margin-top:6px"><option value="cash">كاش</option><option value="card">كارت</option><option value="wallet">محفظة إلكترونية</option></select><button class="btn" style="width:100%;margin-top:8px" onclick="mbTopup()">تأكيد الشحن</button>`:`<p class="m">مفيش باقات شغّالة.</p>`}
${d&&adm?`<h3 style="margin-top:14px">إدارة</h3><div class="row" style="gap:6px;flex-wrap:wrap"><select id="mb_b"><option value="paid">أساسي</option><option value="bonus">هدية</option></select><input id="mb_a" type="number" placeholder="مبلغ (سالب للخصم)" style="width:140px"><input id="mb_n" placeholder="السبب (إجباري)" style="flex:1;min-width:120px"><button class="btn s" onclick="mbAdj()">تصحيح</button></div>
<div style="margin-top:8px"><button class="btn s g" onclick="mbSt('${d.status=="frozen"?"active":"frozen"}')">${d.status=="frozen"?"فك التجميد":"تجميد"}</button> <button class="btn s g" onclick="mbSt('closed')">قفل الاشتراك</button></div>`:""}
${d&&(d.ledger||[]).length?`<h3 style="margin-top:14px">السجل</h3>${d.ledger.map(l=>`<div class="row"><div><b>${MBK_A[l.kind]||l.kind}</b> <span class="tag">${l.bucket=="paid"?"أساسي":"هدية"}</span><div class="m">${new Date(l.at).toLocaleString("ar-EG",{day:"numeric",month:"short",hour:"2-digit",minute:"2-digit"})}${l.note?" · "+esc(l.note):""}</div></div><b>${+l.amount>0?"+":""}${mbN(l.amount)}</b></div>`).join("")}`:""}`)}
const MBK_A={topup:"شحن",bonus_grant:"هدية",spend:"دفع",weekly_penalty:"خصم أسبوعي",expire:"انتهاء هدية",adjust:"تصحيح"};
async function mbTopup(){const p=+$("mb_plan").value,m=$("mb_m").value,pl=MB.plans.find(x=>x.id==p);if(!await askConfirm(`شحن «${pl?pl.name:""}» بـ ${mbN(pl?pl.price:0)} جنيه (${{cash:"كاش",card:"كارت",wallet:"محفظة"}[m]})؟`))return;
  const{error}=await sb.rpc("member_topup",{p_customer:MB.cust,p_plan:p,p_method:m});error?toast(error.message):(toast("اتشحن ✓"),mbOpenCust(MB.cust),tab=="mbr"&&V.mbr())}
async function mbAdj(){const a=+$("mb_a").value;if(!a)return toast("اكتب المبلغ");const{error}=await sb.rpc("member_adjust",{p_customer:MB.cust,p_bucket:$("mb_b").value,p_amount:a,p_note:$("mb_n").value});error?toast(error.message):(toast("اتسجّل تصحيح ✓"),mbOpenCust(MB.cust))}
async function mbSt(s){if(!await askConfirm("تأكيد تغيير حالة الاشتراك؟"))return;const{error}=await sb.rpc("member_set_status",{p_customer:MB.cust,p_status:s});error?toast(error.message):(toast("تم ✓"),mbOpenCust(MB.cust))}
