/* features/customers/redeem_requests.js — إشعار + موافقة على طلبات استبدال النقاط (للموظفين) */
(()=>{
  if(typeof APP_MODE==="undefined"||APP_MODE==="customer")return;
  let n=-1,list=[],btn=null,box=null;
  const beep=()=>{try{const a=new (window.AudioContext||window.webkitAudioContext)(),o=a.createOscillator(),g=a.createGain();o.connect(g);g.connect(a.destination);o.frequency.value=880;g.gain.value=.15;o.start();o.stop(a.currentTime+.25)}catch(e){}};
  function ui(){
    if(btn)return;
    btn=document.createElement("button");
    btn.style.cssText="position:fixed;bottom:84px;left:14px;z-index:60;display:none;padding:12px 16px;border:0;border-radius:999px;background:#c0392b;color:#fff;font:700 16px system-ui;box-shadow:0 4px 14px #0006;cursor:pointer";
    btn.onclick=open;document.body.appendChild(btn);
  }
  function paint(){ui();btn.style.display=list.length?"block":"none";btn.textContent="🔔 طلبات استبدال ("+list.length+")";if(box)render()}
  async function poll(){
    try{
      const{data:{session}}=await sb.auth.getSession();if(!session)return paint(list=[]);
      const{data,error}=await sb.rpc("pending_redeems");
      if(error){list=[];return paint()}
      list=data||[];
      if(n>=0&&list.length>n){toast("طلب استبدال نقاط جديد");beep();try{navigator.vibrate&&navigator.vibrate(200)}catch(e){}}
      n=list.length;paint();
    }catch(e){}
  }
  function open(){
    if(box)return;
    box=document.createElement("div");
    box.style.cssText="position:fixed;inset:0;z-index:80;background:#000a;display:flex;align-items:flex-end;justify-content:center";
    box.onclick=e=>{if(e.target===box)close()};
    document.body.appendChild(box);render();
  }
  function close(){if(box){box.remove();box=null}}
  function render(){
    box.innerHTML=`<div class="box" style="width:min(520px,100%);max-height:80vh;overflow:auto;border-radius:18px 18px 0 0;padding:16px">
<div style="display:flex;justify-content:space-between;align-items:center"><h2 style="margin:0">طلبات استبدال النقاط</h2><button class="btn s g" onclick="rrClose()">إغلاق</button></div>
${list.length?list.map(r=>`<div class="row" style="flex-direction:column;align-items:stretch;gap:8px;margin-top:10px">
<div><b>${esc(r.customer||"—")}</b> <span class="m">${esc(r.phone||"")}</span></div>
<div>${esc(r.reward||"—")} · <b>${num(r.cost)} نقطة</b> <span class="m">(رصيده ${num(r.points)})</span></div>
<div style="display:flex;gap:8px"><button class="btn s" style="flex:1" onclick="rrDecide(${r.id},true)">موافقة</button><button class="btn s g" style="flex:1" onclick="rrDecide(${r.id},false)">رفض</button></div></div>`).join(""):`<p class="m">مفيش طلبات معلّقة.</p>`}</div>`;
  }
  window.rrClose=close;
  window.rrDecide=async(id,ok)=>{
    let note=null;if(!ok){note=prompt("سبب الرفض (اختياري)","");if(note===null)return}
    else if(!confirm("توافق؟ هتتخصم النقاط ويتفعّل الكوبون."))return;
    const{data,error}=await sb.rpc("decide_redeem",{p_id:id,p_approve:ok,p_note:note});
    if(error)return toast(error.message);
    toast(ok?"تمت الموافقة — كود الكوبون: "+data:"تم الرفض");
    await poll();if(!list.length)close();
  };
  poll();setInterval(poll,15000);
})();
