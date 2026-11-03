// اختبار منطق واجهة الحجز (book.js) بدون متصفح: DOM وهمي + Supabase وهمي.
// ⚠ ده اختبار لسلوك الواجهة فقط (mocks) — مش دليل على سلامة الداتابيز. اختبار الداتابيز: db_concurrency.mjs
import vm from 'node:vm'; import fs from 'node:fs'; import assert from 'node:assert/strict';
const src = fs.readFileSync(new URL('../book.js', import.meta.url), 'utf8');
function make(rpcImpl){
  const calls=[], toasts=[], ls={}, els={};
  const el=id=>els[id]??={id,innerHTML:'',textContent:'',disabled:false,value:'',appendChild(){},remove(){}};
  const fakeSb={rpc:async(n,a)=>{calls.push([n,a]);return rpcImpl(n,a)},
    from:()=>({select:()=>({eq:()=>({order:async()=>({data:[{id:1,name:'قص',price:100,active:true}],error:null})}),then:r=>r({data:[],error:null})})})};
  const ctx={console,setTimeout,clearTimeout,setInterval:()=>0,clearInterval(){},Date,Math,JSON,String,Number,Array,Object,
    SUPABASE_URL:'http://x',SUPABASE_KEY:'k',confirm:()=>true,
    supabase:{createClient:()=>fakeSb},
    localStorage:{getItem:k=>k in ls?ls[k]:null,setItem:(k,v)=>{ls[k]=v},removeItem:k=>{delete ls[k]}},
    document:{getElementById:el,title:'',createElement:()=>({className:'',textContent:'',remove(){}}),body:{appendChild:(e)=>toasts.push(e.textContent)}}};
  ctx.window=ctx; vm.createContext(ctx); vm.runInContext(src,ctx);
  return {ctx,calls,toasts,ls,els,run:c=>vm.runInContext(c,ctx)};
}
const tick=()=>new Promise(r=>setTimeout(r,5));
const ok=(over={})=>async(n)=>n==='public_book_v2'?{data:{ok:true,existing:false,ticket:{id:7,no:3,day:'2026-10-10',period:'evening',barber:'ع'},...over},error:null}:{data:[],error:null};
let pass=0; const t=async(name,fn)=>{await fn();pass++;console.log('✓',name)};

await t('الحجز بدون خدمة: الزرار يتفعّل ويتبعت p_services فاضي',async()=>{
  const m=make(ok()); await tick(); m.run(`C.sv=[{id:1,name:'قص',price:100}];C.b={s:[],day:0,period:'evening',barber:null};C.f={n:'أحمد',p:'01012345678'};draw()`);
  assert.equal(m.els.cbtn.disabled,false,'الزرار لازم يبقى مفعّل من غير خدمات');
  await m.run('bookNow()'); const c=m.calls.find(x=>x[0]==='public_book_v2'); assert.ok(c); assert.equal(JSON.stringify(c[1].p_services),"[]");
  assert.ok(JSON.parse(m.ls.salon_book_last).id===7);
});
await t('الضغط المتكرر بيبعت طلب واحد بس',async()=>{
  const m=make(async(n)=>{await tick();return ok()(n)}); await tick(); m.run(`C.b={s:[],day:0,period:'evening',barber:null};C.f={n:'أحمد',p:'01012345678'};draw()`);
  await Promise.all([m.run('bookNow()'),m.run('bookNow()'),m.run('bookNow()')]);
  assert.equal(m.calls.filter(x=>x[0]==='public_book_v2').length,1);
});
await t('فشل الاتصال: مفيش تأكيد وهمي ولا تذكرة محفوظة، وإعادة المحاولة متاحة',async()=>{
  let down=true; const m=make(async(n)=>n==='public_book_v2'&&down?{data:null,error:{message:'TypeError: Failed to fetch'}}:ok()(n)); await tick();
  m.run(`C.b={s:[],day:0,period:'evening',barber:null};C.f={n:'أحمد',p:'01012345678'};draw()`);
  await m.run('bookNow()'); assert.equal(m.ls.salon_book_last,undefined); assert.ok(!m.toasts.some(x=>/تم الحجز/.test(x)));
  assert.ok(m.toasts.some(x=>/لم يتأكد/.test(x))); assert.equal(m.els.cbtn.disabled,false);
  down=false; await m.run('bookNow()'); assert.equal(JSON.parse(m.ls.salon_book_last).id,7);
});
await t('رقم له حجز نشط: بيتعرض الحجز الموجود بدل حجز جديد',async()=>{
  const m=make(ok({existing:true})); await tick(); m.run(`C.b={s:[1],day:0,period:'morning',barber:null};C.f={n:'أحمد',p:'01012345678'};draw()`);
  await m.run('bookNow()'); assert.ok(m.toasts.some(x=>/عندك حجز نشط/.test(x))); assert.equal(JSON.parse(m.ls.salon_book_last).id,7);
});
await t('رسالة خطأ السيرفر (حجز ممنوع) بتظهر ومفيش تذكرة',async()=>{
  const m=make(async n=>n==='public_book_v2'?{data:null,error:{code:'P0001',message:'الفترة دي اكتملت'}}:{data:[],error:null}); await tick();
  m.run(`C.b={s:[],day:0,period:'evening',barber:null};C.f={n:'أحمد',p:'01012345678'};draw()`); await m.run('bookNow()');
  assert.ok(m.toasts.some(x=>/اكتملت/.test(x))); assert.equal(m.ls.salon_book_last,undefined);
});
await t('public_book_v2 غير موجودة: مفيش رجوع للدالة القديمة، ورسالة واضحة، ومفيش تذكرة',async()=>{
  const m=make(async n=>n==='public_book_v2'?{data:null,error:{code:'PGRST202',message:'Could not find the function public_book_v2'}}:{data:[{t_id:9,t_no:1}],error:null}); await tick();
  m.run(`C.b={s:[1],day:0,period:'evening',barber:null};C.f={n:'أحمد',p:'01012345678'};draw()`); await m.run('bookNow()');
  assert.equal(m.calls.filter(x=>x[0]==='public_book').length,0,'ممنوع النداء على public_book القديمة من الواجهة');
  assert.equal(m.ls.salon_book_last,undefined); assert.ok(m.toasts.some(x=>/متوقف مؤقتًا/.test(x))); assert.equal(m.els.cbtn.disabled,false);
});
await t('تغيير الحلاق: يتنادى public_change_barber ومفيش نجاح وهمي عند فشل الاتصال',async()=>{
  let down=true; const m=make(async n=>n==='public_change_barber'&&down?{data:null,error:{message:'Failed to fetch'}}:{data:{ok:true,changed:true},error:null}); await tick();
  m.ls.salon_book_last=JSON.stringify({id:7,p:'01012345678'});
  await m.run("doChangeB('abc')"); assert.ok(m.toasts.some(x=>/لم يتأكد/.test(x))); assert.ok(!m.toasts.some(x=>/تم تغيير/.test(x)));
});
await t('تحقق الموبايل في الواجهة',async()=>{
  const m=make(ok()); await tick(); m.run(`C.b={s:[],day:0,period:'evening',barber:null};C.f={n:'أحمد',p:'123'};draw()`); await m.run('bookNow()');
  assert.equal(m.calls.filter(x=>x[0]==='public_book_v2').length,0);
});
console.log(`\n${pass} client-logic tests passed (mocks only)`);
