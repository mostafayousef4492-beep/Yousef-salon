/* features/catalog/stock.js — المخزون */

V.stock=async function(){
const{data,error}=await sb.from("products").select("*").order("name");
if(error)return put(`<h1>المخزون</h1><p class="m">${esc(error.message)}</p>`);
C.stk=data||[];const low=C.stk.filter(p=>p.stock<=p.min_stock).length,cr=can("restock");
put(`<h1>المخزون</h1>${cr?`<button class="btn s" onclick="stockAddNew()">+ صنف جديد</button>`:""}${low?`<div class="m" style="margin:6px 0">${low} صنف وصل للحد الأدنى أو أقل</div>`:""}`+C.stk.map(p=>`<div class="row"><div><b>${esc(p.name)}</b><div class="m">شراء ${p.cost} · بيع ${p.price}</div></div><div style="text-align:left"><span class="tag" style="${p.stock<=p.min_stock?"background:var(--red);color:#fff":""}">${p.stock} قطعة</span><br>${cr?`<button class="btn s g" onclick="restock(${p.id})">+ توريد</button>`:""}</div></div>`).join(""))};

// بيحوّل الأرقام العربي لإنجليزي ويرجّع عدد صحيح موجب (أو NaN لو غلط، أو null لو الغى)
const stockNum=(v,min)=>{if(v===null)return null;const n=Number(String(v).trim().replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)));return Number.isInteger(n)&&n>=min&&n<=100000?n:NaN};

// توريد: أي كمية تكتبها بتتضاف على المخزون وبتتسجل في حركة المخزون
async function restock(id){if(C.stkBusy)return;const p=(C.stk||[]).find(x=>x.id==id);if(!p)return;
const q=stockNum(prompt("كام قطعة دخلت المخزون من «"+p.name+"»؟\nالكمية الحالية: "+p.stock,"10"),1);if(q===null)return;if(Number.isNaN(q))return toast("اكتب عدد صحيح أكبر من صفر");
if(!confirm("إضافة "+q+" قطعة لـ «"+p.name+"»؟\nالكمية هتبقى "+(p.stock+q)))return;
C.stkBusy=1;const{error}=await sb.rpc("restock_product",{p_id:id,p_qty:q});C.stkBusy=0;error?toast(error.message):(toast("اتضاف "+q+" قطعة"),go("stock"))}

// صنف جديد: بيتسجل بكمية صفر، وبعدين الكمية الابتدائية بتدخل كتوريد علشان تظهر في حركة المخزون
async function stockAddNew(){if(C.stkBusy)return;
const n=(prompt("اسم الصنف")||"").trim();if(!n)return;
if((C.stk||[]).some(p=>String(p.name).trim()==n))return toast("الصنف ده موجود، استخدم «+ توريد»");
const pr=Number(String(prompt("سعر البيع")||"").trim());if(!(pr>=0))return toast("سعر البيع غلط");
const co=Number(String(prompt("سعر الشراء","0")||"0").trim());if(!(co>=0))return toast("سعر الشراء غلط");
const q=stockNum(prompt("الكمية الحالية","0"),0);if(q===null)return;if(Number.isNaN(q))return toast("الكمية لازم تكون عدد صحيح");
C.stkBusy=1;const{data,error}=await sb.from("products").insert({name:n,price:pr,cost:co,stock:0,min_stock:+(C.cfg&&C.cfg.low_stock_default)||5}).select("id").single();
if(error){C.stkBusy=0;return toast(error.message)}
if(q>0){const{error:e2}=await sb.rpc("restock_product",{p_id:data.id,p_qty:q});if(e2)toast("اتضاف الصنف بس التوريد فشل: "+e2.message)}
C.stkBusy=0;toast("اتضاف «"+n+"»");go("stock")}
