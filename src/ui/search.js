/* ui/search.js — البحث العام */

// ===== بحث عام: عملاء / موبايل / فواتير / خدمات / موظفين (حسب الصلاحية) =====

let gsT=0;

function gsDeb(){clearTimeout(gsT);gsT=setTimeout(gsRun,250)}

async function gsRun(){const el=$("gs"),o=$("gsr");if(!el||!o)return;const q=el.value.trim().replace(/[%,()]/g,"");if(q.length<2){o.innerHTML="";return}
const dg=q.replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)),isN=/^\d+$/.test(dg),own=isAdm(me);
const[c,v,sv,st]=await Promise.all([sb.from("customers").select("id,name,phone").or(`name.ilike.%${q}%,phone.ilike.%${dg}%`).limit(5),
isN&&(own||can("view_invoices"))?sb.from("invoices").select("no,total,created_at").eq("no",+dg).limit(3):Promise.resolve({data:[]}),
sb.from("services").select("name,price").ilike("name",`%${q}%`).limit(3),
own?sb.from("profiles").select("id,full_name,role").ilike("full_name",`%${q}%`).neq("role","customer").limit(3):Promise.resolve({data:[]})]);
if($("gs").value.trim().replace(/[%,()]/g,"")!=q)return;
const sec=(t,L)=>L.length?`<div class="m" style="margin-top:8px">${t}</div>`+L.join(""):"";
const h=sec("عملاء",(c.data||[]).map(x=>`<button class="row" style="cursor:pointer" onclick="gsCust(${x.id})"><div><b>${esc(x.name)}</b><div class="m">${esc(x.phone||"")}</div></div><span class="tag">افتح ‹</span></button>`))
+sec("فواتير",(v.data||[]).map(x=>`<button class="row" style="cursor:pointer" onclick="go('inv')"><div><b>فاتورة #${x.no}</b><div class="m">${new Date(x.created_at).toLocaleDateString("ar-EG")}</div></div><b>${fm(x.total)}</b></button>`))
+sec("خدمات",(sv.data||[]).map(x=>`<div class="row"><b>${esc(x.name)}</b><span>${fm(x.price)}</span></div>`))
+sec("موظفين",(st.data||[]).map(x=>`<button class="row" style="cursor:pointer" onclick="go('team')"><div><b>${esc(x.full_name)}</b><div class="m">${RL[x.role]||""}</div></div><span class="tag">‹</span></button>`));
o.innerHTML=h||`<p class="m">مفيش نتيجة لـ "${esc(q)}".</p>`}

async function gsCust(id){if(!C.CU||!C.CU.some(y=>y.id==id)){const{data}=await sb.rpc("customers_overview");C.CU=data||[]}if(!C.CU.some(y=>y.id==id))return toast("مقدرتش أفتح العميل ده");openCust(id)}
