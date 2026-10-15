/* ui/whatsapp.js — واتساب */

/* ===== زر واتساب للعميل (wa.me) ===== */

function waNum(ph){let d=String(ph||"").replace(/[٠-٩]/g,c=>"٠١٢٣٤٥٦٧٨٩".indexOf(c)).replace(/\D/g,"");if(!d)return"";if(d.startsWith("00"))d=d.slice(2);if(/^01\d{9}$/.test(d))return"20"+d.slice(1);if(/^1\d{9}$/.test(d))return"20"+d;return d.length>=10?d:""}

function waBtn(ph,big,text){const n=waNum(ph);if(!n)return"";return `<a href="https://wa.me/${n}${text?"?text="+encodeURIComponent(text):""}" target="_blank" rel="noopener" onclick="event.stopPropagation()" aria-label="واتساب" style="display:inline-flex;align-items:center;gap:5px;background:#25D366;color:#fff;border-radius:999px;text-decoration:none;font-weight:700;${big?"padding:10px 16px;":"padding:5px 11px;font-size:.8rem;"}"><svg width="${big?18:14}" height="${big?18:14}" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2zm5.8 14.2c-.2.7-1.4 1.3-1.9 1.3-.5.1-1.1.1-1.8-.1-.4-.1-1-.3-1.7-.6-3-1.3-4.9-4.3-5.1-4.5-.1-.2-1.2-1.6-1.2-3s.8-2.1 1-2.4c.3-.3.6-.3.8-.3h.6c.2 0 .4 0 .6.5l.9 2.1c.1.2.1.4 0 .5l-.4.6-.3.4c-.1.2-.3.3-.1.6.2.3.8 1.3 1.7 2.1 1.2 1 2.1 1.4 2.4 1.5.3.1.5.1.6-.1l.9-1.1c.2-.3.4-.2.6-.1l2 1c.3.1.5.2.5.3.1.2.1.8-.1 1.5z"/></svg>واتساب</a>`}

/* ===== رسائل واتساب الجاهزة (فاتورة + رابط الباركود) ===== */

const WA_PAY={cash:"كاش",card:"كارت",wallet:"محفظة"};

function waSalon(){return(C.cfg&&C.cfg.salon_name)||"الصالون"}

function waAppMsg(name){return `أهلاً ${name||""} 👋\nسجّل في تطبيق ${waSalon()} وتابع دورك ونقاطك من الرابط ده (نفس الباركود اللي في الصالون):\n${location.origin}/\n\nأو احجز من غير تسجيل:\n${location.origin}/book`}

function waInvText(i,name){const L=(i.invoice_items||[]).map(z=>`• ${z.name}${z.qty>1?" ×"+z.qty:""} — ${fm((+z.unit_price||0)*(z.qty||1))}`).join("\n");
const dt=new Date(i.created_at).toLocaleString("ar-EG",{hourCycle:"h23",dateStyle:"medium",timeStyle:"short"});
return `*${waSalon()}*\nفاتورة رقم ${i.no}\n${dt}${name?"\nالعميل: "+name:""}\n──────────\n${L}\n──────────\n`+(+i.discount>0?`الإجمالي: ${fm(i.subtotal)}\nالخصم: ${fm(i.discount)}\n`:"")+`*المطلوب: ${fm(i.total)}*\nالدفع: ${WA_PAY[i.payment_method]||i.payment_method}\n\nشكراً لزيارتكم 🙏`}

async function waPrep(id,cust,cid){C.lastWa=null;try{if(!id||typeof id=="object")return;let ph=cust&&cust.phone,nm=cust&&cust.name;
if(!ph&&cid){const{data:c}=await sb.from("customers").select("name,phone").eq("id",cid).maybeSingle();if(c){ph=c.phone;nm=c.name}}
if(!waNum(ph))return;
const{data:inv}=await sb.from("invoices").select("no,subtotal,discount,total,payment_method,created_at,invoice_items(name,qty,unit_price)").eq("id",id).maybeSingle();
if(inv)C.lastWa={phone:ph,name:nm,no:inv.no,text:waInvText(inv,nm)}}catch(e){}}

function waLastCard(){const w=C.lastWa;if(!w)return"";return `<div class="box" style="margin:10px 0"><div class="m" style="margin-bottom:8px">فاتورة #${w.no} اتدفعت${w.name?" — "+esc(w.name):""}</div><div class="chips" style="align-items:center">${waBtn(w.phone,1,w.text)}<button class="btn s g" onclick="C.lastWa=null;V.pos()">إخفاء</button></div></div>`}
