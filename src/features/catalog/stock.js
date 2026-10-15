/* features/catalog/stock.js — المخزون */

V.stock=async function(){
const{data}=await sb.from("products").select("*").order("name");
put(`<h1>المخزون</h1>`+data.map(p=>`<div class="row"><div><b>${esc(p.name)}</b><div class="m">شراء ${p.cost} · بيع ${p.price}</div></div><div style="text-align:left"><span class="tag" style="${p.stock<=p.min_stock?"background:var(--red);color:#fff":""}">${p.stock} قطعة</span><br>${can("restock")?`<button class="btn s g" onclick="restock(${p.id},${p.stock})">+10 توريد</button>`:""}</div></div>`).join(""))};

async function restock(id,q){const{error}=await sb.rpc("restock_product",{p_id:id,p_qty:10});error?toast(error.message):go("stock")}
