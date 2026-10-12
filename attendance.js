/* features/team/attendance.js — الحضور والورديات */

// ===== شيفت وإجازة (المالك) =====

async function openShift(id){
const[{data:p},{data:sh},{data:lv}]=await Promise.all([sb.from("profiles").select("full_name").eq("id",id).single(),sb.from("staff_shifts").select("*").eq("staff_id",id),sb.from("staff_leaves").select("*").eq("staff_id",id).order("from_date",{ascending:false}).limit(15)]);
C.sid=id;const DN=["الأحد","الاثنين","الثلاثاء","الأربعاء","الخميس","الجمعة","السبت"];
put(`<button class="btn g s" style="margin-top:12px" onclick="V.team()">‹ رجوع</button><h1>شيفت ${esc(p.full_name)}</h1><h2>الأسبوع</h2>`+DN.map((d,i)=>{const x=(sh||[]).find(y=>y.weekday==i)||{is_off:false,start_time:"10:00",end_time:"20:00"};return `<div class="row"><b style="min-width:62px">${d}</b><label class="m"><input type="checkbox" id="o${i}" ${x.is_off?"checked":""}> إجازة</label><input type="time" id="a${i}" value="${x.start_time.slice(0,5)}" style="width:auto;margin:0"><input type="time" id="b${i}" value="${x.end_time.slice(0,5)}" style="width:auto;margin:0"></div>`}).join("")+`<button class="btn" style="width:100%" onclick="saveShift()">حفظ الشيفت</button>
<h2>إجازة محددة</h2><div class="box"><label class="m">من</label><input type="date" id="lf"><label class="m">إلى</label><input type="date" id="lt"><input id="lr" placeholder="السبب (اختياري)"><button class="btn" onclick="addLeave()">إضافة الإجازة</button></div>`+(lv||[]).map(l=>`<div class="row"><div>${l.from_date} ← ${l.to_date}<div class="m">${esc(l.reason||"")}</div></div><button class="btn s g" onclick="delLeave(${l.id})">حذف</button></div>`).join(""))}

async function saveShift(){const rows=[0,1,2,3,4,5,6].map(i=>({staff_id:C.sid,weekday:i,is_off:$("o"+i).checked,start_time:$("a"+i).value||"10:00",end_time:$("b"+i).value||"20:00"}));
if(rows.some(r=>!r.is_off&&r.start_time>=r.end_time))return toast("وقت البداية لازم يسبق النهاية");
const{error}=await sb.from("staff_shifts").upsert(rows);error?toast(error.message):toast("تم حفظ الشيفت")}

async function addLeave(){const f=$("lf").value,t=$("lt").value||f;if(!f)return toast("اختار تاريخ البداية");if(t<f)return toast("تاريخ النهاية قبل البداية");
const{error}=await sb.from("staff_leaves").insert({staff_id:C.sid,from_date:f,to_date:t,reason:$("lr").value});error?toast(error.message):(toast("تمت إضافة الإجازة"),openShift(C.sid))}

async function delLeave(id){await sb.from("staff_leaves").delete().eq("id",id);openShift(C.sid)}

async function att(f){if(C.attBusy)return;C.attBusy=1;const bs=[...document.querySelectorAll('[onclick^="att("]')];bs.forEach(b=>b.disabled=true);let ok=false;try{toast("بنحدد موقعك...");const g=await getPos();const{data,error}=await sb.rpc(f,{p_lat:g.lat??null,p_lng:g.lng??null});if(error){const m=error.message||"";toast(/duplicate key|unique/i.test(m)?"حضورك متسجل قبل كده":m)}else{ok=true;toast(data);await C.reload()}}finally{C.attBusy=0;if(!ok)bs.forEach(b=>b.disabled=false)}}

// ===== حضور يدوي (المالك): تسجيل / تعديل / حذف عن يوم فات =====

async function attSave(sid){const g=i=>$(i).value,d=g("aa_d"),i=g("aa_i"),o=g("aa_o"),l=g("aa_l");if(!d||!i)return toast("اختار التاريخ ووقت الحضور");if(l!==""&&!(+l>=0))return toast("دقايق التأخير غير صحيحة");const{data,error}=await sb.rpc("admin_att_save",{p_id:C.aid?String(C.aid):null,p_staff:sid,p_day:d,p_in:i,p_out:o||null,p_late_min:l===""?null:Math.round(+l),p_note:g("aa_n")||null});if(error)return toast(error.message);C.aid=null;toast((data?.msg||"اتسجل ✓")+(data?.open?" (لسه مفتوح)":"")+(data?.pay_recalculated?" · الأجر اليومي اتحسب تاني":""));C.reload()}

function attEdit(rid){const r=(C.attRows||{})[String(rid)];if(!r)return;const a=new Date(r.check_in),b=r.check_out?new Date(r.check_out):null,hh=x=>x.toTimeString().slice(0,5);C.aid=String(rid);$("aa_d").value=a.toLocaleDateString("en-CA");$("aa_i").value=hh(a);$("aa_o").value=b?hh(b):"";$("aa_l").value=r.late_min??"";$("aa_n").value=r.note||"";$("aa_t").textContent=b?"تعديل تسجيل حضور":"تسجيل انصراف";$("aa_b").textContent="حفظ التعديل";$("aa_c").style.display="";$("aa_box").scrollIntoView({behavior:"smooth",block:"center"});if(!b)$("aa_o").focus()}

function attCancel(){C.aid=null;C.reload()}

async function attDel(rid){if(!confirm("حذف تسجيل الحضور ده؟ (هيتسجّل في سجل التعديلات)"))return;const{data,error}=await sb.rpc("admin_att_delete",{p_id:String(rid)});if(error)return toast(error.message);toast("اتحذف"+(data?.pay_recalculated?" · الأجر اليومي اتحسب تاني":" · راجع الأجر اليومي لليوم ده لو متفعّل"));C.reload()}

async function setHere(){const g=await getPos();if(g.lat==null)return toast("فعّل الموقع واسمح للمتصفح");$("s_salon_lat").value=g.lat;$("s_salon_lng").value=g.lng;toast("اتحط موقعك الحالي، اضغط حفظ الإعدادات")}

// ================= كشف حساب الموظف (زي البنك) + لوحة الحضور =================

const STK={salary:"راتب يوم",commission:"عمولة",wage:"يومية حضور",deposit:"إيداع",adj:"تسوية ساعات",withdraw:"سحب",deduction:"خصم",payout:"صرف راتب",settle:"تسوية حساب"};

const dsHm=d=>new Date(d).toLocaleTimeString("ar-EG",{hour:"2-digit",minute:"2-digit",hourCycle:"h23"});

async function stmtLoad(id){if(!$("stmt"))return;const[f,t]=rangeOf(C.rg);
  const{data,error}=await sb.rpc("staff_statement",{p_staff:id,p_from:f,p_to:t});if(!$("stmt"))return;
  if(error)return $("stmt").innerHTML=`<h2>كشف الحساب</h2><p class="m">${esc(error.message)}</p>`;
  C.sm=data;drawStmt()}

function stmtFilter(f){C.smf=f;drawStmt()}

function drawStmt(){const box=$("stmt"),d=C.sm;if(!box||!d)return;const f=C.smf||"all",cl=+d.closing||0,canInv=isAdm(me)||can("view_invoices");
  const E=(d.entries||[]).filter(x=>f=="all"||(f=="in"?+x.credit>0:+x.debit>0)).slice().reverse().slice(0,200);
  box.innerHTML=`<h2>كشف الحساب</h2><div class="box" style="text-align:center"><div class="m">رصيد الحساب</div><div style="font-size:30px;font-weight:800;color:${cl>=0?"var(--ok)":"var(--red)"}">${fm(cl)}</div><div class="m">أول الفترة ${fm(d.opening)} · داخل +${fm(d.credits)} · خارج −${fm(d.debits)}</div></div><div class="chips" style="margin:8px 0">${[["all","الكل"],["in","داخل"],["out","خارج"]].map(x=>`<button class="chip ${f==x[0]?"sel":""}" onclick="stmtFilter('${x[0]}')">${x[1]}</button>`).join("")}</div>`+
  (E.length?E.map(x=>{const cr=+x.credit>0,click=x.kind=="commission"&&x.ref&&canInv;return `<div class="row"${click?` role="button" style="cursor:pointer" onclick="dsInvOne(${x.ref})"`:""}><div><b>${esc(x.label)}</b><div class="m">${dsT(x.at)} · ${STK[x.kind]||esc(x.kind)}</div></div><div style="text-align:left"><b style="color:${cr?"var(--ok)":"var(--red)"}">${cr?"+"+fm(x.credit):"−"+fm(x.debit)}</b><div class="m">الرصيد ${fm(x.balance)}</div></div></div>`}).join(""):`<p class="m">مفيش حركات في الفترة دي.</p>`)+
  `<div class="m" style="margin-top:6px">أي فلوس تدخل (راتب، يومية، عمولة، إيداع) بتتضاف للرصيد، وأي سحب أو خصم أو صرف بيتخصم منه. الراتب الشهري بيدخل يوم بيوم من يوم فتح الحساب.</div>`}

const ATL={in:"حاضرين دلوقتي",out:"انصرفوا النهارده",none:"لسه ما حضروش",off:"راحة / إجازة"};

const attSt=r=>r.today_open?"in":r.today_out?"out":r.today_off?"off":"none";

V.att=async()=>{C.am=C.am||ymd(new Date()).slice(0,7);const[,b]=monthR(C.am),e=new Date(b);e.setDate(e.getDate()-1);
  const{data,error}=await sb.rpc("attendance_report",{p_from:C.am+"-01",p_to:ymd(e)});
  if(error)return put(`<h1>الحضور والانصراف</h1><p class="m">${esc(error.message)}</p>`);
  C.ar=data;const R=data.rows||[],cnt=k=>R.filter(r=>attSt(r)==k).length,sm=f=>R.reduce((a,r)=>a+(+r[f]||0),0);
  const bd=r=>{const s=attSt(r);return `<button class="row" style="cursor:pointer;width:100%;text-align:right" onclick="openStaff('${r.id}','${esc(r.name)}')"><div><b>${esc(r.name)}</b><div class="m">${RL[r.role]||r.role}${r.today_in?" · حضر "+dsHm(r.today_in):""}${r.today_out&&!r.today_open?" · انصرف "+dsHm(r.today_out):""}${+r.today_late>0?" · تأخير "+r.today_late+" د":""}</div></div><span class="tag" style="${s=="in"?"background:var(--ok);color:#fff":s=="none"?"background:var(--red);color:#fff":""}">${{in:"حاضر",out:"انصرف",off:"راحة",none:"لسه"}[s]}</span></button>`};
  put(`<h1>الحضور والانصراف</h1>${isAdm(me)?attCodeBox():""}<h2>النهارده</h2><div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">${kc("حاضرين دلوقتي",cnt("in"),"var(--ok)","attList('in')")}${kc("انصرفوا",cnt("out"),"","attList('out')")}${kc("لسه ما حضروش",cnt("none"),cnt("none")?"var(--red)":"","attList('none')")}${kc("راحة / إجازة",cnt("off"),"","attList('off')")}</div>${R.map(bd).join("")}
<h2>تقرير الشهر</h2><div class="chips" style="align-items:center"><input type="month" value="${C.am}" style="width:auto;margin:0" onchange="C.am=this.value||'${C.am}';V.att()"></div>
<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:8px">${kc("أيام غياب",sm("absent_days"),sm("absent_days")?"var(--red)":"","attKpi('absent_days','أيام الغياب','يوم')")}${kc("دقايق تأخير",sm("late_min"),"","attKpi('late_min','دقايق التأخير','دقيقة')")}${kc("ساعات شغل",sm("hours").toFixed(1),"","attKpi('hours','ساعات الشغل','ساعة')")}${kc("نسي الانصراف",sm("missing_out"),sm("missing_out")?"var(--red)":"","attKpi('missing_out','نسيوا الانصراف','مرة')")}</div>
${tbl(["الموظف","حضور","غياب","تأخير","ساعات"],R.map(r=>[`<a href="#" style="color:var(--gold2)" onclick="openStaff('${r.id}','${esc(r.name)}');return false">${esc(r.name)}</a><div class="m">${RL[r.role]||r.role}</div>`,r.present_days,+r.absent_days?`<b style="color:var(--red)">${r.absent_days}</b>`:r.absent_days,+r.late_min?r.late_min+" د":"—",(+r.hours).toFixed(1)]))}
<div class="m" style="margin-top:6px">الغياب بيتحسب من جدول الشيفتات والإجازات (الموظف اللي ملوش شيفت مش بيتحسب له غياب). اضغط على اسم الموظف تشوف يومه بيومه وتسجّل يدوي.</div>`)};

function attList(k){const R=((C.ar||{}).rows||[]).filter(r=>attSt(r)==k);dsOpen(ATL[k],R.length?R.map(r=>dsRow(`<b>${esc(r.name)}</b>`,(RL[r.role]||r.role)+(r.today_in?" · حضر "+dsHm(r.today_in):"")+(r.today_out&&!r.today_open?" · انصرف "+dsHm(r.today_out):""),+r.today_late>0?`<span class="tag">تأخير ${r.today_late} د</span>`:"")).join(""):dsEmpty("مفيش حد."))}

function attKpi(f,t,u){const R=((C.ar||{}).rows||[]).filter(r=>+r[f]>0).sort((a,b)=>b[f]-a[f]);dsOpen(t+" — "+mAr(C.am+"-01"),R.length?R.map(r=>`<button class="row" style="cursor:pointer;width:100%;text-align:right" onclick="svcClose();openStaff('${r.id}','${esc(r.name)}')"><div><b>${esc(r.name)}</b><div class="m">${RL[r.role]||r.role}</div></div><b>${f=="hours"?(+r[f]).toFixed(1):r[f]} ${u}</b></button>`).join(""):dsEmpty("مفيش حاجة الشهر ده."))}

/* ===== تسجيل حضور / انصراف بكود الموظف (للمالك والإدارة) — بيدعم يوم سابق ===== */

function attCodeBox(){const td=ymd(new Date());return `<div class="box" style="margin:8px 0"><div class="m" style="margin-bottom:6px">تسجيل بكود الموظف</div><input id="ac_c" type="text" inputmode="numeric" autocomplete="off" placeholder="اكتب كود الموظف (مثلاً 101)"><label class="m">اليوم (سيبه النهارده للتسجيل الحالي)</label><input id="ac_d" type="date" max="${td}" value="${C.acd||td}" onchange="C.acd=this.value||''"><div class="chips" style="align-items:center"><div style="flex:1"><label class="m">وقت الحضور</label><input id="ac_i" type="time" style="margin:0"></div><div style="flex:1"><label class="m">وقت الانصراف</label><input id="ac_o" type="time" style="margin:0"></div></div><div class="m" style="margin:4px 0">النهارده: سيب الوقت فاضي = الوقت الحالي. يوم سابق: اكتب الوقت (حضور وانصراف مع بعض، أو واحد منهم).</div><div class="chips"><button class="btn" style="flex:1;background:var(--ok)" onclick="attCode('in')">تسجيل حضور</button><button class="btn g" style="flex:1" onclick="attCode('out')">تسجيل انصراف</button></div></div>`}

async function attCode(kind){if(C.acBusy)return;const c=($("ac_c").value||"").trim();if(!c)return toast("اكتب كود الموظف");
const now=new Date(),td=ymd(now),d=$("ac_d").value||td,ti=$("ac_i").value,to=$("ac_o").value,isT=d==td,hh=x=>x.toTimeString().slice(0,5);
if(d>td)return toast("مينفعش تسجل يوم لسه ماجاش");
if(kind=="in"&&!ti&&!isT)return toast("اكتب وقت الحضور لليوم ده");
if(kind=="out"&&!to&&!isT)return toast("اكتب وقت الانصراف لليوم ده");
C.acBusy=1;try{
const{data:p,error}=await sb.from("profiles").select("id,full_name,role,code").eq("code",c).neq("role","customer").limit(1);
if(error)return toast(error.message);if(!p||!p.length)return toast("مفيش موظف بالكود ده");const st=p[0];
const[{data:dy,error:e0},{data:op,error:e1}]=await Promise.all([
 sb.from("attendance").select("id,check_in,check_out").eq("staff_id",st.id).gte("check_in",new Date(d+"T00:00").toISOString()).lt("check_in",new Date(dfNext(d)+"T00:00").toISOString()).order("check_in",{ascending:false}),
 sb.from("attendance").select("id,check_in").eq("staff_id",st.id).is("check_out",null).order("check_in",{ascending:false}).limit(1)]);
if(e0||e1)return toast((e0||e1).message);
const D=dy||[],open=op&&op.length?op[0]:null;let args,lbl;
if(kind=="in"){
 if(isT&&open)return toast(st.full_name+" حاضر بالفعل من "+hh(new Date(open.check_in)));
 if(D.length)return toast(st.full_name+" عنده تسجيل في اليوم ده قبل كده — استخدم انصراف أو عدّله من صفحته");
 const t=ti||hh(now);args={p_id:null,p_staff:st.id,p_day:d,p_in:t,p_out:to||null,p_late_min:null,p_note:"تسجيل بالكود"};lbl="حضور "+t+(to?" ← انصراف "+to:"")}
else{
 const o=to||hh(now);let row=isT?open:D.find(r=>!r.check_out);
 if(!row){
  if(D.some(r=>r.check_out))return toast("انصراف "+st.full_name+" متسجل بالفعل في اليوم ده");
  if(!ti)return toast(isT?st.full_name+" مش مسجّل حضور دلوقتي":"مفيش حضور مسجّل لـ"+st.full_name+" في اليوم ده — اكتب وقت الحضور كمان");
  args={p_id:null,p_staff:st.id,p_day:d,p_in:ti,p_out:o,p_late_min:null,p_note:"تسجيل بالكود"};lbl="حضور "+ti+" ← انصراف "+o}
 else{const a=new Date(row.check_in);args={p_id:String(row.id),p_staff:st.id,p_day:ymd(a),p_in:hh(a),p_out:o,p_late_min:null,p_note:"تسجيل بالكود"};lbl="انصراف "+o}}
const{data,error:e2}=await sb.rpc("admin_att_save",args);
if(e2)return toast(/duplicate key|unique/i.test(e2.message||"")?st.full_name+" عنده تسجيل في اليوم ده قبل كده":e2.message);
toast(st.full_name+" — "+lbl+(isT?"":" ("+d+")")+" ✓"+(data?.late_min>0&&kind=="in"?" · متأخر "+data.late_min+" د":""));V.att()
}finally{C.acBusy=0}}
