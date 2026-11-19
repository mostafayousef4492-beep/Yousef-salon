/* Local-first queue for basic cashier sales. Pending data stays on this device. */
const SalonOffline=(()=>{
  const DB="salon-offline-v1", STORE="pending_sales", REF="cashier_refs", DRAFT="cashier_drafts", OPS="pending_ops";
  const open=()=>new Promise((resolve,reject)=>{const q=indexedDB.open(DB,3);q.onupgradeneeded=()=>{const d=q.result;if(!d.objectStoreNames.contains(STORE))d.createObjectStore(STORE,{keyPath:"request_id"});if(!d.objectStoreNames.contains(REF))d.createObjectStore(REF,{keyPath:"key"});if(!d.objectStoreNames.contains(DRAFT))d.createObjectStore(DRAFT,{keyPath:"id"});if(!d.objectStoreNames.contains(OPS))d.createObjectStore(OPS,{keyPath:"request_id"})};q.onsuccess=()=>resolve(q.result);q.onerror=()=>reject(q.error)});
  async function run(store,mode,fn){const d=await open();return new Promise((resolve,reject)=>{const t=d.transaction(store,mode),s=t.objectStore(store);let out;try{out=fn(s)}catch(e){d.close();reject(e);return}t.oncomplete=()=>{d.close();resolve(out&&out.result)};t.onerror=()=>{d.close();reject(t.error)};t.onabort=()=>{d.close();reject(t.error)}})}
  const put=(store,v)=>run(store,"readwrite",s=>s.put(v)), get=(store,k)=>run(store,"readonly",s=>s.get(k)), all=store=>run(store,"readonly",s=>s.getAll()), del=(store,k)=>run(store,"readwrite",s=>s.delete(k));
  return {
    cacheRefs: v=>put(REF,{key:"cashier",value:v,saved_at:Date.now()}),
    refs: async()=>((await get(REF,"cashier"))||{}).value||null,
    cacheStaff: v=>put(REF,{key:"staff",value:v,saved_at:Date.now()}),
    staff: async()=>((await get(REF,"staff"))||{}).value||null,
    staffSavedAt: async()=>((await get(REF,"staff"))||{}).saved_at||0,
    drafts:()=>all(DRAFT),
    draft: id=>get(DRAFT,id),
    saveDraft: row=>put(DRAFT,row),
    removeDraft: id=>del(DRAFT,id),
    cacheBoard: v=>put(REF,{key:"cxboard",value:v,saved_at:Date.now()}),
    board: async()=>((await get(REF,"cxboard"))||{}).value||null,
    opsList:()=>all(OPS),
    enqueueOp: row=>put(OPS,row),
    removeOp: id=>del(OPS,id),
    list:()=>all(STORE),
    enqueue: row=>put(STORE,row),
    remove: id=>del(STORE,id),
    async sync(){
      if(!navigator.onLine||typeof sb==="undefined"||!me?.id)return;
      const rows=await all(STORE);
      for(const row of rows){
        if(row.user_id!==me.id)continue;
        const {data,error}=row.v===2?await sb.rpc("pos_checkout_offline2",{p_request_id:row.request_id,p_barber:row.barber_id||null,p_items:row.items,p_local_total:row.total,p_sold_at:row.created_at||null,p_method:row.method||"cash",p_pay_channel:row.pay_channel||null,p_pay_ref:row.pay_ref||null,p_discount_pct:row.disc_pct||0,p_discount_fixed:row.disc_fixed||0}):await sb.rpc("pos_checkout_offline",{p_request_id:row.request_id,p_barber:row.barber_id||null,p_items:row.items,p_local_total:row.total,p_sold_at:row.created_at||null});
        if(error){row.last_error=error.message;await put(STORE,row);continue}
        await del(STORE,row.request_id);
        toast(data&&data.note?"اتزامنت فاتورة أوفلاين — "+data.note:"اتزامنت فاتورة أوفلاين ✓");
      }
      const ops=(await all(OPS)).filter(r=>r.user_id===me.id).sort((a,b)=>String(a.created_at).localeCompare(String(b.created_at)));
      for(const row of ops){
        const {error}=await sb.rpc("cashier_offline_op",{p_request_id:row.request_id,p_kind:row.kind,p_args:row.args,p_at:row.created_at||null});
        if(error){if(!/fetch|network|load failed/i.test(error.message||"")){row.last_error=error.message;await put(OPS,row)}continue}
        await del(OPS,row.request_id);
        toast("اتزامنت عملية خزنة أوفلاين ✓");
      }
    }
  };
})();
window.SalonOffline=SalonOffline;
addEventListener("online",()=>setTimeout(()=>SalonOffline.sync().catch(()=>{}),1200));
addEventListener("load",()=>setTimeout(()=>SalonOffline.sync().catch(()=>{}),2500));
