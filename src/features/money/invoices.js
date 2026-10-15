/* features/money/invoices.js — الفواتير */

V.inv=async function(){
const{data,error}=await sb.from("invoices").select("id,no,total,payment_method,created_at,customers(name),barber:barber_id(full_name),invoice_items(name,qty,unit_price)").order("created_at",{ascending:false}).limit(100);
if(error)return put(`<h1>الفواتير</h1><p class="m">مفيش صلاحية لعرض الفواتير لحسابك.</p>`);
put(`<h1>الفواتير</h1>`+(data.length?data.map(i=>`<button class="row" style="cursor:pointer;width:100%;text-align:right" onclick="dsInvOne(${i.id})"><div><b>#${i.no}</b> · ${esc(i.customers?.name||"عميل عابر")}<div class="m">${new Date(i.created_at).toLocaleString("ar-EG")} · ${(i.invoice_items||[]).map(z=>esc(z.name)+(z.qty>1?" ×"+z.qty:"")).join(" + ")}</div><div class="m">الحلاق: ${esc(i.barber?.full_name||"—")}</div></div><div style="text-align:left"><b>${fm(i.total)}</b><div class="m">${PAYL[i.payment_method]||i.payment_method}</div></div></button>`).join(""):`<p class="m">لسه مفيش فواتير.</p>`))};

async function delInv(id,force){if(!force&&!confirm("حذف الفاتورة دي؟\nالمخزون هيرجع، ونقاط العميل وزيارته هتتعكس، وأرقام المبيعات هتتعدّل."))return;const{data,error}=await sb.rpc("admin_void_invoice",{p_id:String(id),p_force:!!force});if(error)return toast(error.message);if(data?.needs_force){if(!confirm("الفاتورة دي من يوم "+data.day+" وهو مقفول في الخزنة.\nلو حذفتها أرقام اليوم هتبقى مختلفة عن اللي اتجرد.\nتكمّل؟"))return;return delInv(id,true)}toast("اتحذفت الفاتورة #"+(data?.no??"")+" ✓");V.inv()}

async function delAppt(id){if(!confirm("حذف الحجز ده نهائيًا؟\n(مختلف عن الإلغاء: بيتمسح من السجل بالكامل)"))return;const{data,error}=await sb.rpc("admin_delete_appointment",{p_id:String(id)});if(error)return toast(error.message);toast("اتحذف الحجز ✓");go("appts")}

// ---- قايمة فواتير (بفلاتر) ← الضغط على فاتورة يفتح تفاصيلها ----

async function dsInv(o){dsLoad(o.t);
  let q=sb.from("invoices").select("id,no,total,discount,payment_method,created_at,customers(name,phone),barber:barber_id(full_name),invoice_items(name,qty)").order("created_at",{ascending:false}).limit(200);
  if(o.from)q=q.gte("created_at",o.from);if(o.to)q=q.lt("created_at",o.to);
  if(o.barber)q=q.eq("barber_id",o.barber);if(o.customer)q=q.eq("customer_id",o.customer);
  if(o.pay)q=q.eq("payment_method",o.pay);if(o.disc)q=q.gt("discount",0);
  if(o.hour!=null)q=q.limit(1000);const{data,error}=await q;if(error)return dsOpen(o.t,dsEmpty(error.message));
  const L=(data||[]).filter(i=>o.hour==null||new Date(i.created_at).getHours()==o.hour);
  const h=L.length?`<div class="m" style="margin-bottom:8px">${L.length>=200?"أحدث 200 فاتورة":L.length+" فاتورة"} · ${L.length>=200?"إجمالي المعروض":"الإجمالي"} <b>${fm(sumOf(L,x=>x.total))}</b>${o.disc?" · خصومات "+fm(sumOf(L,x=>x.discount)):""}</div>`+L.map(i=>`<button class="row" style="cursor:pointer;width:100%;text-align:right" onclick="dsInvOne(${i.id})"><div><b>#${i.no}</b> · ${esc(i.customers?.name||"عميل عابر")}${dsPh()&&i.customers?.phone?` · <span dir="ltr">${esc(i.customers.phone)}</span>`:""}<div class="m">${dsT(i.created_at)} · ${(i.invoice_items||[]).map(z=>esc(z.name)+(z.qty>1?" ×"+z.qty:"")).join(" + ")}</div><div class="m">الحلاق: ${esc(i.barber?.full_name||"—")}</div></div><div style="text-align:left"><b>${fm(i.total)}</b><div class="m">${PAYL[i.payment_method]||esc(i.payment_method)}${+i.discount>0?" · خصم "+fm(i.discount):""}</div></div></button>`).join(""):dsEmpty("مفيش فواتير في الفترة دي.");
  dsOpen(o.t,h,{list:1})}

// ---- تفاصيل فاتورة واحدة: الزبون / مين اشتغل / اتعمل إيه / الحساب ----

async function dsInvOne(id){dsLoad("تفاصيل الفاتورة");
  const{data:i,error}=await sb.from("invoices").select("id,no,subtotal,discount,total,payment_method,created_at,customers(name,phone,visits),barber:barber_id(full_name),cashier:cashier_id(full_name),invoice_items(id,name,qty,unit_price,item_type,assistant_cut,assistant:assistant_id(full_name))").eq("id",id).maybeSingle();
  if(error||!i)return dsOpen("تفاصيل الفاتورة",dsEmpty(error?error.message:"الفاتورة مش موجودة."),{back:1});
  const it=i.invoice_items||[],asst=[...new Set(it.map(x=>x.assistant?.full_name).filter(Boolean))],cu=i.customers;
  dsOpen("فاتورة #"+i.no,`<div class="m" style="margin-bottom:8px">${new Date(i.created_at).toLocaleString("ar-EG",{hourCycle:"h23",weekday:"long",day:"numeric",month:"long",year:"numeric",hour:"2-digit",minute:"2-digit"})}</div>
<h2>الزبون</h2><div class="box">${cu?dsKv("الاسم",`<b>${esc(cu.name)}</b>`)+(dsPh()&&cu.phone?dsKv("الموبايل",`<span dir="ltr">${esc(cu.phone)}</span>`):"")+(cu.visits!=null?dsKv("عدد زياراته",cu.visits):""):`<span class="m">عميل عابر (من غير حساب)</span>`}</div>
<h2>مين اشتغل</h2><div class="box">${dsKv("الحلاق",`<b>${esc(i.barber?.full_name||"—")}</b>`)}${asst.length?dsKv("المساعد",asst.map(a=>esc(a)).join("، ")):""}${dsKv("الكاشير (اللي حاسب)",esc(i.cashier?.full_name||"—"))}</div>
<h2>اتعمل إيه</h2><div class="box">${it.map(x=>`<div style="padding:5px 0;border-bottom:1px dashed var(--line)"><div style="display:flex;justify-content:space-between;gap:10px"><span><b>${esc(x.name)}</b> <span class="tag">${x.item_type=="product"?"منتج":"خدمة"}</span></span><b>${fm(x.unit_price*x.qty)}</b></div><div class="m">${x.qty>1?x.qty+" × "+fm(x.unit_price):"سعر "+fm(x.unit_price)}${x.assistant?` · المساعد: ${esc(x.assistant.full_name)}${+x.assistant_cut?` (اتخصم ${fm(x.assistant_cut)} للمساعد)`:""}`:""}</div></div>`).join("")||`<span class="m">مفيش بنود</span>`}</div>
<h2>الحساب</h2><div class="box">${dsKv("المجموع",fm(i.subtotal))}${+i.discount>0?dsKv("الخصم","- "+fm(i.discount)):""}${dsKv("الإجمالي",fm(i.total),1)}${dsKv("طريقة الدفع",PAYL[i.payment_method]||esc(i.payment_method))}</div>
${me.role=="owner"?`<button class="btn s g" style="color:var(--red);margin-top:8px" onclick="svcClose();delInv('${i.id}')">حذف الفاتورة</button>`:""}`,{back:1})}
