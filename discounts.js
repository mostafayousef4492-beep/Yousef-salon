/* features/floor/discounts.js — الخصومات والموافقات */

// ===== الخصومات: حدود حسب الدور + طلب موافقة (السيرفر هو اللي بيفرض، ده بس واجهة) =====

const discLim=()=>{const g=+C.cfg.disc_global_max_pct||20;return me.role=="owner"?g:Math.min(g,can("approve_discount")?+C.cfg.disc_manager_max_pct||30:+C.cfg.disc_cashier_max_pct||10)};

const discOpts=()=>{const g=+C.cfg.disc_global_max_pct||20;return String(C.cfg.disc_options||"0,5,10,20").split(",").map(Number).filter(n=>n>=0&&n<=g)};

const fixOpts=()=>String(C.cfg.disc_fixed_options||"20,30,50,100").split(",").map(Number).filter(n=>n>0);

const subOf=P=>P.s.reduce((a,i)=>a+(+(P.sv.find(y=>y.id==i)||{}).price||0),0)+P.p.reduce((a,i)=>a+(+(P.pr.find(y=>y.id==i.id)||{}).price||0)*i.q,0);

const fxPct=(x,sub)=>sub>0?x/sub*100:0;

function pickDisc(x){const P=C.P;P.dfx=0;if(x<=discLim()){P.disc=x;P.rqid=null;chSave();return drawPos()}reqDisc(x,0)}

function pickFix(x){const P=C.P,sub=subOf(P);if(P.dfx==x){P.dfx=0;P.rqid=null;chSave();return drawPos()}if(!sub)return toast("ضيف خدمات الأول");if(x>sub)return toast("الخصم أكبر من الفاتورة");
if(fxPct(x,sub)<=discLim()+0.005){P.disc=0;P.dfx=x;P.rqid=null;chSave();return drawPos()}reqDisc(fxPct(x,sub),x)}

async function reqDisc(pct,fx){const P=C.P,sub=subOf(P);
if(!sub)return toast("ضيف خدمات الأول");const why=prompt("الخصم ده فوق حدّك ومحتاج موافقة المدير.\nسبب الخصم:");if(why===null)return;
const{data,error}=await sb.rpc("request_discount",{p_chair:P.chair,p_pct:Math.ceil(pct*100)/100,p_subtotal:sub,p_reason:why});if(error)return toast(error.message);
toast("اتبعت طلب الموافقة للمدير ⏳");const ch=P.chair,t=setInterval(async()=>{if(!C.P||C.P.chair!=ch)return clearInterval(t);const{data:r}=await sb.from("discount_requests").select("status").eq("id",data).maybeSingle();
if(r&&r.status=="approved"){clearInterval(t);C.P.disc=fx?0:pct;C.P.dfx=fx||0;C.P.rqid=data;chSave();toast("اتوافق على الخصم ✓");drawPos()}else if(r&&r.status=="rejected"){clearInterval(t);toast("المدير رفض الخصم")}},4000)}

async function decideD(id,ok){const{error}=await sb.rpc("decide_discount",{p_id:id,p_ok:ok});error?toast(error.message):(toast(ok?"تمت الموافقة ✓":"اتم الرفض"),V.home())}
