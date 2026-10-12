/* ui/util.js — أدوات مشتركة (جداول، أعمدة، كروت) */

async function copyLink(p){const u=location.origin+p;try{await navigator.clipboard.writeText(u);toast("تم نسخ الرابط ✓")}catch(e){prompt("انسخ الرابط:",u)}}

// ================= التقارير =================

const num=x=>Math.round(+x||0).toLocaleString("ar-EG"),ymd=d=>d.toLocaleDateString("en-CA");

const tbl=(h,rows)=>rows.length?`<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse;font-size:13px"><tr>${h.map(x=>`<th style="text-align:right;padding:6px;border-bottom:1px solid var(--line);color:var(--mute);white-space:nowrap">${x}</th>`).join("")}</tr>${rows.map(r=>`<tr>${r.map(c=>`<td style="padding:6px;border-bottom:1px dashed var(--line)">${c}</td>`).join("")}</tr>`).join("")}</table></div>`:`<p class="m">مفيش بيانات في الفترة دي.</p>`;

const bars=(a,lab,val)=>{const m=Math.max(1,...a.map(val));return a.length?a.map(x=>`<div style="margin-bottom:7px"><div style="display:flex;justify-content:space-between;font-size:12px"><span>${lab(x)}</span><b>${fm(val(x))}</b></div><div style="height:8px;border-radius:6px;background:var(--line);overflow:hidden"><i style="display:block;height:100%;width:${val(x)/m*100}%;background:var(--blue)"></i></div></div>`).join(""):`<p class="m">مفيش بيانات.</p>`};

const kc=(l,v,c,a)=>`<div class="box kpi"${a?` role="button" tabindex="0" onclick="${a}" style="cursor:pointer"`:""}><div class="kpi-l">${l}</div><div class="kpi-v" style="color:${c||"inherit"}">${v}</div>${a?`<div class="m" style="font-size:11px">اضغط للتفاصيل</div>`:""}</div>`;
