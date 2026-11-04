/* features/money/edit_dates.js — تعديل تاريخ سجل (فاتورة / مصروف ...) بدل حذفه (للمالك) */
function editDate(kind,id,cur,force,val){
  const ts=kind=="invoice"||kind=="staff_tx";
  if(val===undefined){
    const d=new Date(cur&&String(cur).length>10?cur:(cur||Date.now())),p=n=>String(n).padStart(2,"0");
    const v=ts?`${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`:String(cur).slice(0,10);
    const o=document.createElement("div");o.id="edm";
    o.style.cssText="position:fixed;inset:0;z-index:95;background:#000a;display:flex;align-items:center;justify-content:center;padding:16px";
    o.innerHTML=`<div class="box" style="width:min(380px,100%);display:flex;flex-direction:column;gap:12px"><h2 style="margin:0">تعديل التاريخ</h2><input id="edv" type="${ts?"datetime-local":"date"}" value="${v}" max="${ts?"":ymd(new Date())}"><div style="display:flex;gap:8px"><button class="btn s" style="flex:1" id="edok">حفظ</button><button class="btn s g" style="flex:1" id="edno">إلغاء</button></div></div>`;
    document.body.appendChild(o);
    $("edno").onclick=()=>o.remove();
    $("edok").onclick=()=>{const x=$("edv").value;if(!x)return toast("اختار التاريخ");o.remove();editDate(kind,id,cur,false,x)};
    return;
  }
  return edDo(kind,id,cur,force,val,ts);
}
async function edDo(kind,id,cur,force,val,ts){
  const iso=(ts?new Date(val):new Date(val+"T12:00:00")).toISOString();
  const{data,error}=await sb.rpc("admin_set_date",{p_kind:kind,p_id:String(id),p_ts:iso,p_force:!!force});
  if(error)return toast(error.code=="PGRST202"?"شغّل patch_edit_dates.sql في Supabase الأول":error.message);
  if(data?.needs_force){if(!confirm("اليوم "+data.day+" مقفول في الخزنة.\nتعديل التاريخ هيغيّر أرقام اليوم عن اللي اتجرد.\nتكمّل؟"))return;return edDo(kind,id,cur,true,val,ts)}
  toast("اتعدّل التاريخ ✓");
  try{svcClose&&svcClose()}catch(e){}
  try{if(kind=="invoice")V.inv();else if(kind=="staff_tx"&&C.reload)C.reload();else if(typeof repLoad=="function")repLoad()}catch(e){}
}

// نقل حركة (ضخ/سحب، مصروف، حركة موظف) ليوم عمل تاني — لقطة إقفال اليومين بتتحدّث تلقائي (للمالك)
async function entryMove(kind,id,after){
  const{data}=await sb.rpc("business_days_list");const L=(Array.isArray(data)?data:[]).map(x=>x.day).reverse();
  if(!L.length)return toast("مفيش أيام عمل مسجّلة");
  C.emv={kind,id,after};
  dsOpen("نقل الحركة ليوم تاني",`<div class="m" style="margin-bottom:8px">اختار يوم العمل اللي الحركة دي بتاعته. لقطة إقفال اليوم القديم والجديد بتتحدّث لوحدها (العدّ الفعلي ما بيتغيّرش) وبيتسجّل التغيير في سجل المحذوفات.</div><select id="emv_d">${L.map(d=>`<option value="${d}">${d}${C.biz&&C.biz.open&&C.biz.day==d?" (اليوم المفتوح)":""}</option>`).join("")}</select><button class="btn" style="width:100%;margin-top:8px" onclick="entryMoveGo()">نقل</button>`)}
async function entryMoveGo(){const e=C.emv,d=$("emv_d")&&$("emv_d").value;if(!e||!d)return;if(!confirm("تنقل الحركة دي ليوم "+d+"؟\nإقفال اليوم القديم واليوم "+d+" هيتحدّث (المتوقع بس)."))return;
  const{error}=await sb.rpc("move_entry_day",{p_kind:e.kind,p_id:e.id,p_day:d});
  if(error)return toast(error.code=="PGRST202"?"شغّل patch_day_workflow.sql في Supabase الأول":error.message);
  toast("اتنقلت ✓ وإقفال اليومين اتحدّث");try{svcClose()}catch(x){}await bizLoad(true);try{e.after&&e.after()}catch(x){}}
