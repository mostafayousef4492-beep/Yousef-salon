/* features/money/cash.js — الخزنة اليومية */

// ===== النظام المالي: الخزنة اليومية + الموردين والمشتريات + الرواتب + الأرباح الشهرية + Excel =====

const paySrc=v=>`<option value="drawer" ${v!="other"?"selected":""}>من درج الكاش</option><option value="other" ${v=="other"?"selected":""}>من برا الدرج (بنك/محفظة)</option>`;

const mAr=d=>new Date(d+"T00:00").toLocaleDateString("ar-EG",{month:"long",year:"numeric"});

const monthR=ym=>{const[y,m]=ym.split("-").map(Number);return[new Date(y,m-1,1),new Date(y,m,1)]};

const CASHK=[["cash","كاش"],["card","كارت"],["wallet","محفظة"]];

const errBox=(box,e)=>{box.innerHTML=`<p class="m">${esc(e.message||e)} — لو الرسالة عن جدول أو دالة مش موجودة، شغّل patch9.sql في Supabase الأول.</p>`};

// ---------- الخزنة ----------

function closeCard(r){return `<div class="box">${tbl(["","المتوقع","المعدود","الفرق"],CASHK.map(([k,l])=>{const d=+r["diff_"+k];return [l,fm(r["expected_"+k]),fm(r["counted_"+k]),`<b style="color:${d==0?"var(--ok)":"var(--red)"}">${d==0?"مظبوط ✓":(d>0?"زيادة ":"عجز ")+fm(Math.abs(d))}</b>`]}))}</div>`}

V.cash=async()=>{await bizLoad();const own=isAdm(me),today=bizToday();if(!own||!C.cd)C.cd=today;const day=C.cd;
  const[{data:closed,error:e0},{data:sm},{data:cl},{data:mv},{data:bl}]=await Promise.all([sb.rpc("is_day_closed",{p_day:day}),own?sb.rpc("day_summary",{p_day:day}):{data:null},own?sb.from("cash_closings").select("*").order("day",{ascending:false}).limit(30):{data:null},own?sb.from("cash_moves").select("*").eq("day",day).order("id"):{data:null},own?sb.rpc("business_days_list"):{data:null}]);
  if(e0)return put(`<h1>الخزنة</h1><p class="m">${esc(e0.message)} — شغّل patch9.sql في Supabase الأول.</p>`);
  let h=`<h1>الخزنة</h1>`;
  if(own)h+=`<div id="kpi">${SK}</div><h2>الدرج وقفل اليوم</h2>`;
  if(own)h+=`<div class="chips" style="align-items:center"><input type="date" id="cdate" value="${day}" max="${today}" style="width:auto;margin:0" onchange="C.cd=this.value||null;V.cash()"><button class="btn s g" onclick="C.cd=null;V.cash()">اليوم</button></div>${bizCtl(day,bl)}${me.role=="owner"?`<button class="btn s" style="margin-top:8px" onclick="bfOpen()">+ تسجيل مبيعات يوم فات</button><div id="bf"></div>`:""}`;
  if(sm){const L=[["رصيد أول اليوم",sm.opening],["مبيعات كاش",sm.cash_sales],["مصروفات من الدرج",-sm.exp_cash],["مشتريات كاش",-sm.pur_cash],["تسديد موردين",-sm.sup_cash],["رواتب مصروفة",-sm.sal_cash],["سحب موظفين (سلف)",-sm.adv_cash],["سحب من الدرج",-sm.moves_out],["إضافة للدرج",sm.moves_in]].filter(r=>+r[1]||r[0]=="رصيد أول اليوم");
    h+=`<h2>المتوقع في الدرج (${sm.invoices} فاتورة)</h2><div class="box">${L.map(r=>`<div style="display:flex;justify-content:space-between;padding:3px 0"><span>${r[0]}</span><span>${fm(r[1])}</span></div>`).join("")}<div style="display:flex;justify-content:space-between;padding:6px 0 0;font-weight:800;border-top:1px solid var(--line);margin-top:4px"><span>الكاش المتوقع</span><span>${fm(sm.expected_cash)}</span></div></div><div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:8px">${kc("مبيعات كارت",fm(sm.card_sales),"","dsDayPay('card')")}${kc("مبيعات محفظة",fm(sm.wallet_sales),"","dsDayPay('wallet')")}</div>`}
  const row=C.cres&&C.cres.day==day?C.cres:(cl||[]).find(x=>x.day==day);
  if(closed||row)h+=`<h2>اتقفل يوم ${day}</h2>`+(row?closeCard(row):`<p class="m">اليوم ده اتقفل قبل كده.</p>`);
  else h+=`<h2>قفل اليوم</h2><div class="box"><p class="m" style="margin-top:0">${own?"اكتب اللي اتعدّ فعلًا. النظام بيقارنه بالمتوقع ويطلّع الفرق.":"عدّ اللي في الدرج واكتب الأرقام. النظام هيحسب الفرق لوحده."}</p>${own?`<div class="chips"><button class="chip" id="kc_m1" onclick="clMode(1)">عدّيت شغل اليوم بس (يتضاف عليه رصيد أول اليوم)</button><button class="chip" id="kc_m0" onclick="clMode(0)">عدّيت كل اللي في الدرج</button></div>`:""}<input id="kc_cash" type="number" inputmode="decimal" placeholder="الكاش اللي في الدرج" oninput="clPrev()"><div class="m" id="kc_prev" style="margin:-4px 0 8px"></div><input id="kc_card" type="number" inputmode="decimal" placeholder="إجمالي الكارت (من تقرير الماكينة)"><input id="kc_wallet" type="number" inputmode="decimal" placeholder="إجمالي المحفظة"><input id="kc_note" placeholder="ملاحظة (اختياري)">${own?`<input id="kc_open" type="number" inputmode="decimal" placeholder="رصيد أول اليوم (سيبه فاضي = رصيد آخر قفل ${sm?sm.opening:0})" oninput="clPrev()">`:""}<button class="btn" style="width:100%" onclick="doClose()">قفل اليوم</button></div>`;
  if(own){h+=`<h2>سحب / إضافة للدرج — ${day}</h2><div class="box"><select id="mv_k"><option value="withdraw">سحب من الدرج (مالك / إيداع بنك)</option><option value="deposit">إضافة للدرج (فكة / ضخ)</option></select><input id="mv_a" type="number" inputmode="decimal" placeholder="المبلغ"><input id="mv_n" placeholder="ملاحظة (اختياري)"><button class="btn s" onclick="addMove()">حفظ</button></div>`+(mv||[]).map(m=>`<div class="row"><div><b>${m.kind=="withdraw"?"سحب":"إضافة"} ${fm(m.amount)}</b><div class="m">${esc(m.note||"")}</div></div><button class="btn s g" onclick="delMove(${m.id})">حذف</button></div>`).join("");
    h+=`<h2>آخر عمليات القفل</h2>`+((cl||[]).length?cl.map(x=>`<details class="row"><summary><b>${x.day}</b> · <span style="color:${+x.diff_cash==0?"var(--ok)":"var(--red)"}">${+x.diff_cash==0?"الكاش مظبوط":(+x.diff_cash>0?"زيادة ":"عجز ")+fm(Math.abs(x.diff_cash))}</span></summary>${closeCard(x)}<div class="m">رصيد أول اليوم ${fm(x.opening)}${x.note?" · "+esc(x.note):""}</div><button class="btn s g" style="margin-top:8px" onclick="delClose('${x.day}')">إعادة فتح اليوم ده (لتعديله)</button></details>`).join(""):`<p class="m">لسه مفيش عمليات قفل.</p>`)}
  C.cmSm=sm;put(h);if(own){showKpi();clMode(clGet())}};

const clGet=()=>{try{return localStorage.getItem("salon_close_mode")=="0"?0:1}catch(e){return 1}};
function clOpening(){const o=$("kc_open")?$("kc_open").value:"",sm=C.cmSm;return o!==""&&!isNaN(parseFloat(o))?parseFloat(o):(sm?+sm.opening||0:0)}
function clMode(m){C.clM=m;try{localStorage.setItem("salon_close_mode",String(m))}catch(e){}const a=$("kc_m1"),b=$("kc_m0"),i=$("kc_cash");if(a)a.classList.toggle("sel",!!m);if(b)b.classList.toggle("sel",!m);if(i)i.placeholder=m?"الكاش من شغل اليوم ده بس (من غير رصيد أول اليوم)":"الكاش اللي في الدرج كله";clPrev()}
function clPrev(){const e=$("kc_prev");if(!e)return;const m=C.clM===undefined?1:C.clM,v=parseFloat($("kc_cash")?.value);if(!m||isNaN(v)){e.textContent=m?"هيتضاف تلقائي رصيد أول اليوم: "+fm(clOpening()):"";return}e.innerHTML="شغل اليوم "+fm(v)+" + رصيد أول اليوم "+fm(clOpening())+" = <b>"+fm(v+clOpening())+"</b> (ده اللي هيتقارن بالمتوقع)"}
async function doClose(){const g=id=>{const v=$(id).value;return v===""?NaN:parseFloat(v)};let c=g("kc_cash");const cd=g("kc_card"),w=g("kc_wallet");const dayOnly=!!$("kc_m1")&&C.clM!==0;if(dayOnly&&!isNaN(c)&&c>=0)c=c+clOpening();
  if([c,cd,w].some(x=>isNaN(x)||x<0))return toast("اكتب الكاش والكارت والمحفظة (اكتب 0 لو مفيش)");
  const op=$("kc_open")?$("kc_open").value:"";if(!confirm(dayOnly?"تقفل اليوم؟\nشغل اليوم "+fm(c-clOpening())+" + رصيد أول اليوم "+fm(clOpening())+" = "+fm(c)+"\nمش هتقدر تعدّل بعد كده (المالك يقدر يعيد فتحه).":"تقفل اليوم؟ مش هتقدر تعدّل بعد كده."))return;
  const{data,error}=await sb.rpc("close_day",{p_day:C.cd||bizToday(),p_counted_cash:c,p_counted_card:cd,p_counted_wallet:w,p_opening:op===""?null:parseFloat(op),p_note:$("kc_note").value||null});
  if(error)return toast(error.message);C.cres=data;await bizLoad(true);toast("تم قفل اليوم ✓");V.cash();if(!(C.biz&&C.biz.open)&&confirm("اتقفل اليوم ✓\nتفتح اليوم الجديد دلوقتي؟"))bizOpen()}

async function delClose(day){if(!confirm("تعيد فتح يوم "+day+"؟\nجرد الدرج بتاعه هيتشال (بيتسجل في المحذوفات) وتقفله تاني بالعدّ الصح. تقدر تعيد فتح آخر يوم اتقفل بس."))return;const{error}=await sb.rpc("reopen_business_day",{p_day:day});if(error)return toast(error.message);C.cres=null;C.cd=null;await bizLoad(true);toast("اتعاد فتح اليوم ✓");V.cash()}

async function addMove(){const a=parseFloat($("mv_a").value);if(!(a>0))return toast("اكتب المبلغ");const{error}=await sb.from("cash_moves").insert({day:C.cd||bizToday(),kind:$("mv_k").value,amount:a,note:$("mv_n").value||null});error?toast(error.message):(toast("تم ✓"),V.cash())}

function delMove(id){return ownerDel("cash_moves",id,()=>V.cash(),"حذف الحركة؟")}

// ---- الخزنة: كروت الفترة + اليوم ----

function dsBar(id,pay){const P=C.kp;if(!P)return;const b=id&&(P.bars||[]).find(x=>x.id==id);dsInv({t:b?"فواتير "+b.n:"فواتير "+PAYL[pay]+" في الفترة",from:P.A,to:P.B,barber:id||null,pay:pay||null})}

function dsAll(){const P=C.kp;if(P)dsInv({t:"كل فواتير الفترة",from:P.A,to:P.B})}

function dsDayPay(p){const day=C.cd||bizToday(),a=new Date(day+"T00:00"),b=new Date(a);b.setDate(b.getDate()+1);dsInv({t:"فواتير "+PAYL[p]+" — "+day,from:a.toISOString(),to:b.toISOString(),pay:p})}
