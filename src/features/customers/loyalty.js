/* features/customers/loyalty.js — المكافآت والنقاط */

async function addRw(){const n=await askInput("اسم المكافأة");if(!n)return;const c=+await askInput("تكلفتها بالنقاط","100");if(!(c>0))return;const k=await askInput("النوع: 1 خصم بمبلغ، 2 خصم نسبة %، 3 خدمة مجانية","1");const o={name:n,cost:c};
if(k=="2"){o.kind="pct";o.value=+await askInput("نسبة الخصم %","10")}else if(k=="3"){const sv=C.cat.services,i=+await askInput("اكتب رقم الخدمة:\n"+sv.map((x,j)=>(j+1)+" "+x.name).join("\n"));if(!sv[i-1])return;o.kind="service";o.service_id=sv[i-1].id;o.value=0}else{o.kind="amount";o.value=+await askInput("قيمة الخصم بالجنيه","20")}
const{error}=await sb.from("loyalty_rewards").insert(o);error?toast(error.message):V.set()}

async function togRw(id,a){await sb.from("loyalty_rewards").update({active:a}).eq("id",id);V.set()}
