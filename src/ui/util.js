/* ui/util.js — أدوات مشتركة (جداول، أعمدة، كروت) */

async function copyLink(p){const u=location.origin+p;try{await navigator.clipboard.writeText(u);toast("تم نسخ الرابط ✓")}catch(e){prompt("انسخ الرابط:",u)}}

// ================= التقارير =================

const num=x=>Math.round(+x||0).toLocaleString("ar-EG"),ymd=d=>d.toLocaleDateString("en-CA");

const tbl=(h,rows)=>rows.length?`<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse;font-size:13px"><tr>${h.map(x=>`<th style="text-align:right;padding:6px;border-bottom:1px solid var(--line);color:var(--mute);white-space:nowrap">${x}</th>`).join("")}</tr>${rows.map(r=>`<tr>${r.map(c=>`<td style="padding:6px;border-bottom:1px dashed var(--line)">${c}</td>`).join("")}</tr>`).join("")}</table></div>`:`<p class="m">مفيش بيانات في الفترة دي.</p>`;

const bars=(a,lab,val,clk)=>{const m=Math.max(1,...a.map(val));return a.length?a.map((x,i)=>`<div style="margin-bottom:7px${clk?";cursor:pointer":""}"${clk?` role="button" onclick="${clk(x,i)}"`:""}><div style="display:flex;justify-content:space-between;font-size:12px"><span>${lab(x)}</span><b>${fm(val(x))}</b></div><div style="height:8px;border-radius:6px;background:var(--line);overflow:hidden"><i style="display:block;height:100%;width:${val(x)/m*100}%;background:var(--blue)"></i></div></div>`).join(""):`<p class="m">مفيش بيانات.</p>`};

const kc=(l,v,c,a)=>`<div class="box kpi"${a?` role="button" tabindex="0" onclick="${a}" style="cursor:pointer"`:""}><div class="kpi-l">${l}</div><div class="kpi-v" style="color:${c||"inherit"}">${v}</div>${a?`<div class="m" style="font-size:11px">اضغط للتفاصيل</div>`:""}</div>`;

const netErr=e=>!!e&&!e.code&&!e.hint&&!e.details;

function t24(id,val,extra){const v=(val||"").slice(0,5),[h,m]=v?v.split(":"):["",""];
const H=`<option value="">--</option>`+Array.from({length:24},(_,i)=>{const x=String(i).padStart(2,"0");return `<option ${x==h?"selected":""}>${x}</option>`}).join("");
const mins=Array.from({length:12},(_,i)=>String(i*5).padStart(2,"0"));if(m&&!mins.includes(m)){mins.push(m);mins.sort()}
const M=mins.map(x=>`<option ${x==m?"selected":""}>${x}</option>`).join("");
return `<span dir="ltr" style="display:inline-flex;gap:4px;align-items:center"><input type="hidden" id="${id}" value="${v}" ${extra||""}><select onchange="t24c(this)" style="width:auto;margin:0">${H}</select><b>:</b><select onchange="t24c(this)" style="width:auto;margin:0">${M}</select></span>`}

function t24c(el){const w=el.parentNode,s=w.querySelectorAll("select"),h=w.querySelector("input"),nv=s[0].value?s[0].value+":"+s[1].value:"";if(h.value!==nv){h.value=nv;h.dispatchEvent(new Event("change",{bubbles:true}))}}

function t24v(id,v){const el=$(id);if(!el)return;const s=el.parentNode.querySelectorAll("select"),[h,m]=v?v.slice(0,5).split(":"):["",""];
if(m&&![...s[1].options].some(o=>o.value==m)){const o=new Option(m,m);s[1].add(o);[...s[1].options].sort((a,b)=>a.value-b.value).forEach(x=>s[1].add(x))}
s[0].value=h||"";s[1].value=m||"00";el.value=v?v.slice(0,5):""}
