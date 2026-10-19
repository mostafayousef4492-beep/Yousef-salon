/* ui/search.js — البحث العام */

// ===== بحث عام: عملاء / فواتير / مصروفات / سحب موظفين / حركات الدرج / رواتب / موردين / صفحات وتقارير (حسب الصلاحية) =====

let gsT=0;

function gsDeb(){clearTimeout(gsT);gsT=setTimeout(gsRun,250)}

// تطبيع عربي للمقارنة (همزات/تاء مربوطة/ياء/تشكيل)
const gsN=t=>String(t||"").replace(/[ً-ْـ]/g,"").replace(/[أإآ]/g,"ا").replace(/ة/g,"ه").replace(/ى/g,"ي").toLowerCase();

// صفحات وتقارير: [العنوان، كلمات بحث، تنفيذ، للمالك بس؟]
const GSP=()=>[...(typeof RSEC!="undefined"?RSEC:[]).map(([k,l])=>["تقرير: "+l,"تقرير تقارير "+l,`C.rs='${k}';go('rep')`,true]),
["الخزنة والدرج","خزنه درج قفل اليوم كاش",`go('cash')`,true],["الفواتير","فاتورة فواتير",`go('inv')`,false],["المصروفات","مصروف مصروفات مصاريف",`C.rs='exp';go('rep')`,true],
["الموردين والمشتريات","مورد موردين مشتريات",`C.fs='pur';go('fin')`,true],["الرواتب","راتب رواتب مرتب",`C.fs='pay';go('fin')`,true],["أرباح شهرية","ارباح شهريه ربح",`C.fs='mon';go('fin')`,true],
["الموظفين","موظف موظفين حلاق سحب سلف",`go('team')`,true],["الحضور","حضور انصراف تاخير",`go('att')`,false],["العملاء","عميل عملاء زبون",`go('cust')`,false],["الكاشير","كاشير بيع كراسي",`go('pos')`,false],
["الحجوزات والدور","حجز حجوزات دور طابور",`go('appts')`,false],["المخزون","مخزون منتج منتجات",`go('stock')`,false],["الإعدادات","اعدادات ضبط",`go('set')`,true]];

const KL={advance:"سحب",deduction:"خصم",bonus:"مكافأة"};

async function gsRun(){const el=$("gs"),o=$("gsr");if(!el||!o)return;const q=el.value.trim().replace(/[%,()*]/g,"");if(q.length<2){o.innerHTML="";return}
const dg=q.replace(/[٠-٩]/g,d=>"٠١٢٣٤٥٦٧٨٩".indexOf(d)),isN=/^\d+(\.\d+)?$/.test(dg),own=isAdm(me)&&can("search_money"),E={data:[]},P=x=>x||Promise.resolve(E);
const live=()=>$("gs")&&$("gs").value.trim().replace(/[%,()*]/g,"")==q,nq=gsN(q);
const[c,v,sv,st,ex,mv,su]=await Promise.all([sb.from("customers").select("id,name,phone").or(`name.ilike.%${q}%,phone.ilike.%${dg}%`).limit(5),
isN&&/^\d+$/.test(dg)&&(own||can("view_invoices"))?sb.from("invoices").select("id,no,total,created_at,customers(name)").eq("no",+dg).limit(3):P(),
sb.from("services").select("name,price").ilike("name",`%${q}%`).limit(3),
own?sb.from("profiles").select("id,full_name,role").ilike("full_name",`%${q}%`).neq("role","customer").limit(4):P(),
own?sb.from("expenses").select("id,category,amount,note,spent_on").or(`note.ilike.%${q}%,category.ilike.%${q}%${isN?`,amount.eq.${dg}`:""}`).order("spent_on",{ascending:false}).limit(6):P(),
own?sb.from("cash_moves").select("id,day,kind,amount,note").or(`note.ilike.%${q}%${isN?`,amount.eq.${dg}`:""}`).order("day",{ascending:false}).limit(5):P(),
own?sb.from("suppliers").select("id,name,phone").or(`name.ilike.%${q}%,phone.ilike.%${dg}%`).limit(3):P()]);
if(!live())return;
// المرحلة التانية: حاجات مربوطة بالاسم (فواتير العميل، حركات/رواتب/فواتير الموظف)
const cids=(c.data||[]).map(x=>x.id),sids=(st.data||[]).map(x=>x.id);
const[ci,tx,sp,bi]=await Promise.all([cids.length&&(own||can("view_invoices"))?sb.from("invoices").select("id,no,total,created_at,customers(name)").in("customer_id",cids).order("created_at",{ascending:false}).limit(5):P(),
own?sb.from("staff_transactions").select("id,kind,amount,note,created_at,profiles(full_name)").or(`note.ilike.%${q}%${sids.length?`,staff_id.in.(${sids.join(",")})`:""}${isN?`,amount.eq.${dg}`:""}`).order("created_at",{ascending:false}).limit(8):P(),
own?sb.from("salary_payments").select("id,amount,paid_on,note,profiles(full_name)").or(`note.ilike.%${q}%${sids.length?`,staff_id.in.(${sids.join(",")})`:""}`).order("paid_on",{ascending:false}).limit(4):P(),
sids.length&&own?sb.from("invoices").select("id,no,total,created_at,customers(name)").in("barber_id",sids).order("created_at",{ascending:false}).limit(4):P()]);
if(!live())return;
const dt=d=>new Date(d).toLocaleDateString("ar-EG"),R=(a,b,c2,on)=>`<button class="row" style="cursor:pointer" onclick="${on}"><div><b>${a}</b><div class="m">${b}</div></div>${c2}</button>`;
const sec=(t,L)=>L.length?`<div class="m" style="margin-top:8px">${t}</div>`+L.join(""):"";
const invR=x=>R(`فاتورة #${x.no}${x.customers?.name?" · "+esc(x.customers.name):""}`,dt(x.created_at),`<b>${fm(x.total)}</b>`,`dsInvOne(${x.id})`);
const seen=new Set(),invs=[...(v.data||[]),...(ci.data||[]),...(bi.data||[])].filter(x=>!seen.has(x.id)&&seen.add(x.id));
const pg=GSP().filter(x=>(!x[3]||own)&&gsN(x[0]+" "+x[1]).includes(nq)&&typeof V[(x[2].match(/go\('(\w+)'\)/)||[])[1]]!="undefined").slice(0,5);
const h=sec("صفحات وتقارير",pg.map(x=>R(esc(x[0]),"افتح",`<span class="tag">‹</span>`,x[2])))
+sec("عملاء",(c.data||[]).map(x=>`<button class="row" style="cursor:pointer" onclick="gsCust(${x.id})"><div><b>${esc(x.name)}</b><div class="m">${esc(x.phone||"")}</div></div><span class="tag">افتح ‹</span></button>`))
+sec("فواتير",invs.map(invR))
+sec("سحب وخصم ومكافآت الموظفين",(tx.data||[]).map(x=>R(`${KL[x.kind]||x.kind} · ${esc(x.profiles?.full_name||"")}`,`${dt(x.created_at)}${x.note?" · "+esc(x.note):""}`,`<b>${fm(x.amount)}</b>`,`go('team')`)))
+sec("مصروفات",(ex.data||[]).map(x=>R(`${esc(x.category||"مصروف")}`,`${dt(x.spent_on)}${x.note?" · "+esc(x.note):""}`,`<b>${fm(x.amount)}</b>`,`C.rs='exp';go('rep')`)))
+sec("حركات الدرج (سحب / إيداع)",(mv.data||[]).map(x=>R(x.kind=="withdraw"?"سحب من الدرج":"إيداع في الدرج",`${dt(x.day)}${x.note?" · "+esc(x.note):""}`,`<b>${fm(x.amount)}</b>`,`C.cd='${x.day}';go('cash')`)))
+sec("رواتب مصروفة",(sp.data||[]).map(x=>R(`راتب · ${esc(x.profiles?.full_name||"")}`,`${dt(x.paid_on)}${x.note?" · "+esc(x.note):""}`,`<b>${fm(x.amount)}</b>`,`C.fs='pay';go('fin')`)))
+sec("موردين",(su.data||[]).map(x=>R(esc(x.name),esc(x.phone||""),`<span class="tag">‹</span>`,`C.fs='pur';go('fin')`)))
+sec("خدمات",(sv.data||[]).map(x=>`<div class="row"><b>${esc(x.name)}</b><span>${fm(x.price)}</span></div>`))
+sec("موظفين",(st.data||[]).map(x=>`<button class="row" style="cursor:pointer" onclick="go('team')"><div><b>${esc(x.full_name)}</b><div class="m">${RL[x.role]||""}</div></div><span class="tag">‹</span></button>`));
o.innerHTML=h||`<p class="m">مفيش نتيجة لـ "${esc(q)}".</p>`}

async function gsCust(id){if(!C.CU||!C.CU.some(y=>y.id==id)){const{data}=await sb.rpc("customers_overview");C.CU=data||[]}if(!C.CU.some(y=>y.id==id))return toast("مقدرتش أفتح العميل ده");openCust(id)}
