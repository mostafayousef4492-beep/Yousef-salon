// اختبار تكامل حقيقي للداتابيز — لازم يتشغّل على مشروع Supabase *تجريبي* بعد تطبيق sql/booking_queue_upgrade.sql.
// ⚠ ما اتشغّلش في التسليم ده: مفيش بيئة غير إنتاجية متاحة. بيرفض يشتغل على مشروع الإنتاج، ومبيستخدمش أي بيانات إنتاج.
// بيعمل بيانات اختبار (أرقام عشوائية) في الداتابيز التجريبية.
// تشغيل:
//   TEST_URL=https://<test-ref>.supabase.co TEST_ANON=<anon> \
//   TEST_STAFF_JWT=<jwt كاشير/مالك: manage_appts + use_pos> TEST_SERVICE_KEY=<service_role للتجريبي فقط> node tests/db_concurrency.mjs
import assert from 'node:assert/strict';
const U=process.env.TEST_URL,K=process.env.TEST_ANON,J=process.env.TEST_STAFF_JWT,SK=process.env.TEST_SERVICE_KEY;
if(!U||!K){console.error('اضبط TEST_URL و TEST_ANON');process.exit(2)}
if(/vjesigpmaddlhupbymoy/.test(U)){console.error('ممنوع: ده مشروع الإنتاج');process.exit(3)}
const H=(jwt,key)=>({apikey:key||K,authorization:'Bearer '+(jwt||key||K),'content-type':'application/json'});
const rpc=(n,a,jwt)=>fetch(`${U}/rest/v1/rpc/${n}`,{method:'POST',headers:H(jwt),body:JSON.stringify(a)}).then(async r=>({s:r.status,j:await r.json().catch(()=>null)}));
const get=(path,jwt,key)=>fetch(`${U}/rest/v1/${path}`,{headers:H(jwt,key)}).then(r=>r.json());
const patch=(path,body,jwt)=>fetch(`${U}/rest/v1/${path}`,{method:'PATCH',headers:{...H(jwt),prefer:'return=representation'},body:JSON.stringify(body)}).then(async r=>({s:r.status,j:await r.json().catch(()=>null)}));
const ph=()=>'01'+String(Math.floor(Math.random()*1e9)).padStart(9,'0');
const args=(p,day,over={})=>({p_name:'اختبار',p_phone:p,p_barber:null,p_day:day,p_period:'evening',p_services:null,...over});
let pass=0,skipped=[];const t=async(n,f,need)=>{if(need&&!need()){skipped.push(n);console.log('⏭ تخطّيت:',n);return}await f();pass++;console.log('✓',n)};
const iso=d=>new Date(Date.now()+d*864e5).toLocaleDateString('en-CA');
let DAY;for(let d=0;d<5&&!DAY;d++){const r=await rpc('public_book_v2',args(ph(),iso(d)));if(r.s===200)DAY=iso(d);else if(r.j?.code==='PGRST202'){console.error('public_book_v2 مش موجودة: طبّق الترقية الأول');process.exit(4)}}
if(!DAY){console.error('مفيش يوم متاح للحجز في الداتابيز التجريبية');process.exit(5)}
const book=(p,over)=>rpc('public_book_v2',args(p,DAY,over));
const barbers=async()=>(await rpc('available_barbers',{p_day:DAY,p_period:'evening'})).j||[];

await t('حجز بدون خدمة ينجح',async()=>{const r=await book(ph());assert.equal(r.s,200,JSON.stringify(r.j));assert.equal(r.j.existing,false)});
await t('حجز بخدمات (لو موجودة) ينجح',async()=>{const s=await get('services?select=id&active=eq.true&limit=1',null);if(!s?.[0])return;const r=await book(ph(),{p_services:[s[0].id]});assert.equal(r.s,200,JSON.stringify(r.j))});
await t('حجز بحلاق محدد',async()=>{const b=(await barbers())[0];assert.ok(b,'مفيش حلاق متاح');const r=await book(ph(),{p_barber:b.id});assert.equal(r.j.ticket.barber,b.full_name)});
await t('حجز "أي حلاق متاح"',async()=>{const r=await book(ph());assert.equal(r.s,200);assert.ok(r.j.ticket.barber)});
await t('20 طلب متزامن لنفس الرقم => تذكرة واحدة فقط وصف واحد في الجدول',async()=>{const p=ph();
  const R=await Promise.all(Array.from({length:20},()=>book(p)));const ok=R.filter(r=>r.s===200);
  assert.equal(new Set(ok.map(r=>r.j.ticket.id)).size,1,JSON.stringify(R.map(r=>r.j)));assert.equal(ok.filter(r=>!r.j.existing).length,1,'لازم واحد بس ينشئ');
  if(SK){const c=await get(`customers?select=id&phone=eq.${p}`,null,SK);const a=await get(`appointments?select=id&customer_id=eq.${c[0].id}&status=in.(upcoming,checked_in,in_service)`,null,SK);assert.equal(a.length,1,'صف نشط واحد بس')}});
await t('أرقام مختلفة على نفس الحلاق متزامنة => أرقام دور مختلفة',async()=>{const b=(await barbers())[0];
  const R=await Promise.all(Array.from({length:8},()=>book(ph(),{p_barber:b.id})));const seen=new Set();
  for(const r of R.filter(r=>r.s===200)){assert.ok(!seen.has(r.j.ticket.no),'رقم دور مكرر '+r.j.ticket.no);seen.add(r.j.ticket.no)}});
await t('رقم له حجز نشط يطلب فترة تانية => نفس الحجز بدل واحد جديد',async()=>{const p=ph();const a=await book(p);const b=await book(p,{p_period:'afternoon'});assert.equal(b.j.existing,true);assert.equal(b.j.ticket.id,a.j.ticket.id)});
await t('الدالة القديمة public_book ما بتنشئش حجز تاني ولا بتشترط خدمة',async()=>{const p=ph();await book(p);const r=await rpc('public_book',args(p,DAY,{p_services:[]}));assert.equal(r.s,200,JSON.stringify(r.j));assert.equal(r.j.length,1)});
await t('إلغاء الحجز يحتفظ بالسجل، وبعده يقدر العميل يحجز تاني',async()=>{const p=ph();const a=await book(p);
  const c=await rpc('public_cancel',{p_id:a.j.ticket.id,p_phone:p});assert.equal(c.s,200,JSON.stringify(c.j));
  if(SK){const row=await get(`appointments?select=status&id=eq.${a.j.ticket.id}`,null,SK);assert.equal(row[0].status,'cancelled')}
  const b=await book(p);assert.equal(b.s,200);assert.equal(b.j.existing,false);assert.notEqual(b.j.ticket.id,a.j.ticket.id)});
await t('تغيير الحلاق من العميل: ينقل ويحافظ على أسبقية التسجيل',async()=>{const B=await barbers();assert.ok(B.length>=2,'محتاج حلاقين اتنين متاحين');
  const [A1,B1]=B;const p1=ph(),p4=ph();const t1=await book(p1,{p_barber:A1.id});const t4=await book(p4,{p_barber:B1.id});
  const r=await rpc('public_change_barber',{p_id:t1.j.ticket.id,p_phone:p1,p_barber:B1.id});assert.equal(r.s,200,JSON.stringify(r.j));
  if(SK){const rows=await get(`appointments?select=id,barber_id,ticket_no&id=in.(${t1.j.ticket.id},${t4.j.ticket.id})`,null,SK);
    const m=rows.find(x=>x.id===t1.j.ticket.id),o=rows.find(x=>x.id===t4.j.ticket.id);assert.equal(m.barber_id,B1.id);assert.ok(m.ticket_no<o.ticket_no,'المنقول (أقدم تسجيلًا) لازم يسبق اللي سجّل بعده')}});
await t('إشعارات: تأكيد الحجز مرة واحدة، وتغيّر الترتيب بعد الإلغاء مرة واحدة بدون تكرار',async()=>{
  const b=(await barbers())[0];const P=Array.from({length:6},()=>ph());const T=[];for(const p of P)T.push((await book(p,{p_barber:b.id})).j.ticket);
  const notif=async id=>get(`customer_notifications?select=kind&appointment_id=eq.${id}`,null,SK);
  for(const x of T)assert.equal((await notif(x.id)).filter(n=>n.kind.startsWith('booked:')).length,1,'تأكيد الحجز لازم مرة واحدة');
  const c1=await rpc('public_cancel',{p_id:T[0].id,p_phone:P[0]});assert.equal(c1.s,200);
  await rpc('public_cancel',{p_id:T[0].id,p_phone:P[0]}); // إعادة نفس الطلب
  const last=await notif(T[5].id);const pos=last.filter(n=>n.kind.startsWith('pos:'));
  assert.ok(pos.length<=1,'إشعار ترتيب مكرر: '+JSON.stringify(last)); // =1 لو الترتيب الجديد أكبر من near_turn_threshold
  const ks=last.map(n=>n.kind);assert.equal(new Set(ks).size,ks.length,'kind مكرر')},()=>!!SK);
await t('تخطي من الكاشير: no_show بيحتفظ بالسجل وبيتبلّغ اللي وراه، واسترجاعه بيرجّعه لمكانه',async()=>{
  const b=(await barbers())[0];const P=Array.from({length:4},()=>ph());const T=[];for(const p of P)T.push((await book(p,{p_barber:b.id})).j.ticket);
  const s=await patch(`appointments?id=eq.${T[0].id}`,{status:'no_show'},J);assert.equal(s.s,200,JSON.stringify(s.j));
  const row=await get(`appointments?select=status,ticket_no&id=eq.${T[0].id}`,null,SK);assert.equal(row[0].status,'no_show');assert.equal(row[0].ticket_no,T[0].no);
  const r=await patch(`appointments?id=eq.${T[0].id}`,{status:'upcoming'},J);assert.equal(r.s,200);
  const row2=await get(`appointments?select=ticket_no&id=eq.${T[0].id}`,null,SK);assert.equal(row2[0].ticket_no,T[0].no,'رجع لنفس رقمه')},()=>!!J&&!!SK);
await t('Walk-in بحلاق محدد وبدون خدمة: نفس سجل العميل، booking_source=walk_in، والمرة التانية existing',async()=>{
  const b=(await barbers())[0];const p=ph();
  const a=await rpc('walk_in_ticket_v2',{p_customer:null,p_name:'ويك',p_phone:p,p_barber:b.id,p_services:null},J);assert.equal(a.s,200,JSON.stringify(a.j));
  assert.equal(a.j.existing,false);assert.equal(a.j.source,'walk_in');assert.equal(a.j.status,'checked_in');assert.equal(a.j.barber,b.full_name);
  const b2=await rpc('walk_in_ticket_v2',{p_customer:null,p_name:'ويك',p_phone:p,p_barber:b.id,p_services:null},J);assert.equal(b2.j.existing,true);assert.equal(b2.j.id,a.j.id);
  if(SK){const c=await get(`customers?select=id&phone=eq.${p}`,null,SK);assert.equal(c.length,1,'سجل عميل واحد بس')}},()=>!!J);
await t('Walk-in لعميل عنده حجز أونلاين نشط: ما يتعملش دور تاني، والحجز الأصلي زي ما هو',async()=>{
  const p=ph();const on=await book(p);const w=await rpc('walk_in_ticket_v2',{p_customer:null,p_name:'ويك',p_phone:p,p_barber:null,p_services:null},J);
  assert.equal(w.j.existing,true);assert.equal(w.j.id,on.j.ticket.id);assert.equal(w.j.status,'upcoming','ما اتغيّرتش الحالة: الكاشير هو اللي يؤكد الوصول')},()=>!!J);
await t('منع تكرار الفاتورة: pos_checkout متزامن مرتين لنفس الحجز => فاتورة واحدة فقط',async()=>{
  const b=(await barbers())[0];const w=await rpc('walk_in_ticket_v2',{p_customer:null,p_name:'فاتورة',p_phone:ph(),p_barber:b.id,p_services:null},J);assert.equal(w.s,200,JSON.stringify(w.j));
  assert.equal((await patch(`appointments?id=eq.${w.j.id}`,{status:'in_service'},J)).s,200);
  const call=()=>rpc('pos_checkout',{p_customer:null,p_barber:b.id,p_items:[],p_discount_pct:0,p_discount_fixed:0,p_method:'cash',p_appointment:w.j.id,p_request:null},J);
  const R=await Promise.all([call(),call()]);
  const inv=await get(`invoices?select=id&appointment_id=eq.${w.j.id}`,J);assert.equal(inv.length,1,'لازم فاتورة واحدة: '+JSON.stringify(R.map(r=>r.j)))},()=>!!J);
await t('صلاحيات: زائر مجهول ما يقدرش ينقل ولا يسجّل Walk-in',async()=>{
  const a=await rpc('walk_in_ticket_v2',{p_customer:null,p_name:'x',p_phone:ph(),p_barber:null,p_services:null});assert.ok(a.s>=400);
  const b=await rpc('reassign_ticket',{p_id:1,p_barber:null});assert.ok(b.s>=400)});
console.log(`\n${pass} DB integration tests passed${skipped.length?` | تخطّيت ${skipped.length} (محتاجة TEST_STAFF_JWT / TEST_SERVICE_KEY)`:''}`);
