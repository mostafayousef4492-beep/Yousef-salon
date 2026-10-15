/* features/team/announcements.js — الإعلانات */

// ===== واجهات patch11: الإعلانات / المتصدرين / التسوية / الراتب اليومي / الحجز الإداري / لم يحضر =====

async function annCount(){try{const[{data:L},{data:R}]=await Promise.all([sb.from("team_announcements").select("id,expires_at").eq("active",true).limit(100),sb.from("announcement_reads").select("announcement_id").eq("user_id",me.id)]);const rd=new Set((R||[]).map(x=>x.announcement_id));C.annN=(L||[]).filter(a=>(!a.expires_at||new Date(a.expires_at)>Date.now())&&!rd.has(a.id)).length}catch(e){C.annN=0}annDot()}

function annDot(){const b=document.querySelector('nav button[data-v~="ann"]');if(!b)return;const o=b.querySelector(".adot");if(o)o.remove();if(C.annN>0&&tab!="ann"){const i=document.createElement("i");i.className="adot";i.textContent=C.annN>9?"9+":C.annN;i.style.cssText="position:absolute;top:2px;right:10px;background:var(--red);color:#fff;border-radius:10px;font-size:10px;font-style:normal;padding:0 5px;line-height:16px";b.style.position="relative";b.appendChild(i)}}

V.ann=async()=>{const[{data:L,error},{data:R}]=await Promise.all([sb.from("team_announcements").select("*").order("pinned",{ascending:false}).order("created_at",{ascending:false}).limit(60),sb.from("announcement_reads").select("announcement_id").eq("user_id",me.id)]);
  if(error)return put(`<h1>الإعلانات</h1><p class="m">${esc(error.message)} — شغّل patch11.sql في Supabase الأول.</p>`);
  const rd=new Set((R||[]).map(x=>x.announcement_id)),post=can("manage_announcements"),live=a=>a.active&&(!a.expires_at||new Date(a.expires_at)>Date.now());
  put(`<h1>إعلانات الفريق</h1>${post?`<button class="btn s" onclick="annForm()">+ إعلان جديد</button><div id="af"></div>`:""}`+((L||[]).length?L.map(a=>{const mine=isAdm(me)||a.created_by==me.id,un=live(a)&&!rd.has(a.id);return `<div class="box" style="margin-top:10px;${un?"border-color:var(--gold2);":""}${live(a)?"":"opacity:.55;"}"><div style="display:flex;justify-content:space-between;gap:8px"><b>${a.pinned?"📌 ":""}${esc(a.title)}</b>${un?`<span class="tag">جديد</span>`:""}</div><div style="white-space:pre-wrap;margin:6px 0">${esc(a.body)}</div><div class="m">${new Date(a.created_at).toLocaleString("ar-EG")}${a.expires_at?" · ينتهي "+new Date(a.expires_at).toLocaleDateString("ar-EG"):""}${live(a)?"":" · متوقف"}</div>${post&&mine?`<div class="chips" style="margin-top:8px"><button class="btn s g" onclick="annTog(${a.id},${!a.active})">${a.active?"إيقاف":"تفعيل"}</button><button class="btn s g" onclick="annPin(${a.id},${!a.pinned})">${a.pinned?"إلغاء التثبيت":"تثبيت"}</button><button class="btn s g" onclick="annDel(${a.id})">حذف</button></div>`:""}</div>`}).join(""):`<p class="m">مفيش إعلانات لسه.</p>`));
  await Promise.all((L||[]).filter(a=>live(a)&&!rd.has(a.id)).map(a=>sb.rpc("mark_announcement_read",{p_id:a.id})));C.annN=0;annDot()};

function annForm(){const e=$("af");if(e.innerHTML)return e.innerHTML="";e.innerHTML=`<div class="box" style="margin:10px 0"><input id="an_t" placeholder="عنوان الإعلان"><textarea id="an_b" rows="4" placeholder="نص الإعلان" style="width:100%"></textarea><label class="row" style="cursor:pointer"><span>تثبيت في الأول</span><input type="checkbox" id="an_p" style="width:22px;height:22px;margin:0"></label><label class="m">ينتهي في (اختياري)</label><input type="date" id="an_e"><div class="chips"><button class="btn" onclick="annSave()">نشر</button><button class="btn g" onclick="$('af').innerHTML=''">إلغاء</button></div></div>`}

async function annSave(){const t=$("an_t").value.trim(),b=$("an_b").value.trim(),ex=$("an_e").value;if(!t||!b)return toast("اكتب العنوان والنص");const{error}=await sb.from("team_announcements").insert({title:t,body:b,pinned:$("an_p").checked,expires_at:ex?new Date(ex+"T23:59:59").toISOString():null,created_by:me.id});error?toast(error.message):(toast("تم نشر الإعلان ✓"),V.ann())}

async function annTog(id,v){const{error}=await sb.from("team_announcements").update({active:v}).eq("id",id);error?toast(error.message):V.ann()}

async function annPin(id,v){const{error}=await sb.from("team_announcements").update({pinned:v}).eq("id",id);error?toast(error.message):V.ann()}

async function annDel(id){if(!confirm("تحذف الإعلان ده؟"))return;const{error}=await sb.from("team_announcements").delete().eq("id",id);error?toast(error.message):V.ann()}
