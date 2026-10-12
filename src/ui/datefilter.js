/* ui/datefilter.js — فلتر التاريخ */

/* ===== فلتر التاريخ (من / إلى) — بيتستخدم في أكتر من شاشة ===== */

function dfGet(k){return(C.df=C.df||{})[k]||{f:"",t:""}}

function dfSet(k,w,v){const d=dfGet(k);d[w]=v||"";if(d.f&&d.t&&d.f>d.t){const x=d.f;d.f=d.t;d.t=x}C.df[k]=d}

function dfClr(k){(C.df=C.df||{})[k]={f:"",t:""}}

function dfOn(k){const d=dfGet(k);return!!(d.f||d.t)}

function dfIn(k,v){if(!dfOn(k))return true;if(!v)return false;const d=dfGet(k),x=String(v).length>10?ymd(new Date(v)):String(v).slice(0,10);return(!d.f||x>=d.f)&&(!d.t||x<=d.t)}

function dfNext(t){const d=new Date(t+"T00:00");d.setDate(d.getDate()+1);return ymd(d)}

function dfQ(q,col,k,ts){const d=dfGet(k);if(d.f)q=q.gte(col,ts?new Date(d.f+"T00:00").toISOString():d.f);if(d.t)q=ts?q.lt(col,new Date(dfNext(d.t)+"T00:00").toISOString()):q.lte(col,d.t);return q}

function dfBar(k,run){const d=dfGet(k);return `<div class="box" style="margin:8px 0"><div class="chips" style="align-items:center"><span class="m">من</span><input type="date" value="${d.f}" style="width:auto;margin:0" onchange="dfSet('${k}','f',this.value);${run}"><span class="m">إلى</span><input type="date" value="${d.t}" style="width:auto;margin:0" onchange="dfSet('${k}','t',this.value);${run}">${dfOn(k)?`<button class="btn s g" onclick="dfClr('${k}');${run}">مسح الفلتر</button>`:""}</div></div>`}
