/* features/money/export_template.js — ملف الإكسيل الجاهز (قالب المالك) متملي من بيانات المشروع. للمالك بس. */

function loadZip(){return new Promise((ok,no)=>{if(window.JSZip)return ok(window.JSZip);const s=document.createElement("script");s.src="https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js";s.onload=()=>window.JSZip?ok(window.JSZip):no(new Error("مقدرتش أحمّل أداة الملفات"));s.onerror=()=>no(new Error("مفيش نت لتحميل أداة الملفات"));document.head.appendChild(s)})}

// كل جدول: ملف الورقة، أول صف بيانات، ونوع كل عمود: n رقم · d تاريخ · t وقت · s نص · - (معادلة، بنسيبه)
const XT_SHEETS={
  sales:{f:"sheet2.xml",r:13,k:"ndssssnnnnns"},
  barbers:{f:"sheet3.xml",r:5,k:"dssnnnnn-sss"},
  attendance:{f:"sheet4.xml",r:5,k:"dssttttnss"},
  inventory:{f:"sheet5.xml",r:5,k:"dsssnn-n-ss"},
  services:{f:"sheet6.xml",r:9,k:"ndsssnnss"},
  cash:{f:"sheet7.xml",r:13,k:"dnnnn-nnns"}
};
const XT_NS="http://schemas.openxmlformats.org/spreadsheetml/2006/main",XT_COLS="ABCDEFGHIJKLMNOPQRSTUVWXYZ";

function xtSerial(v){ // "YYYY-MM-DD" أو "YYYY-MM-DD HH:MM" ← رقم تاريخ إكسيل
  const m=/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?/.exec(String(v||""));if(!m)return null;
  return Date.UTC(+m[1],+m[2]-1,+m[3])/86400000+25569+((+m[4]||0)*60+(+m[5]||0))/1440}
function xtTime(v){const m=/^(\d{1,2}):(\d{2})/.exec(String(v||""));return m?((+m[1])*60+(+m[2]))/1440:null}
function xtCell(doc,row,ref,kind,val){
  let c=[...row.children].find(x=>x.getAttribute("r")===ref);
  if(!c){c=doc.createElementNS(XT_NS,"c");c.setAttribute("r",ref);
    const ci=XT_COLS.indexOf(ref[0]),nx=[...row.children].find(x=>XT_COLS.indexOf(x.getAttribute("r")[0])>ci);row.insertBefore(c,nx||null)}
  while(c.firstChild)c.removeChild(c.firstChild);c.removeAttribute("t");
  if(val===null||val===undefined||val==="")return;
  let num=null;
  if(kind==="n")num=Number.isFinite(+val)?+val:null;else if(kind==="d")num=xtSerial(val);else if(kind==="t")num=xtTime(val);
  if(num!==null){const v=doc.createElementNS(XT_NS,"v");v.textContent=String(num);c.appendChild(v);return}
  c.setAttribute("t","inlineStr");const is=doc.createElementNS(XT_NS,"is"),t=doc.createElementNS(XT_NS,"t");t.setAttribute("xml:space","preserve");t.textContent=String(val);is.appendChild(t);c.appendChild(is)}
function xtRow(doc,sd,n){let r=[...sd.children].find(x=>x.getAttribute("r")===String(n));
  if(!r){r=doc.createElementNS(XT_NS,"row");r.setAttribute("r",String(n));const nx=[...sd.children].find(x=>+x.getAttribute("r")>n);sd.insertBefore(r,nx||null)}return r}
async function xtEdit(zip,path,fn){const f=zip.file(path);if(!f)throw new Error("القالب ناقصه ورقة: "+path);const doc=new DOMParser().parseFromString(await f.async("string"),"application/xml");
  if(doc.getElementsByTagName("parsererror").length)throw new Error("القالب تالف: "+path);fn(doc,doc.getElementsByTagName("sheetData")[0]);zip.file(path,new XMLSerializer().serializeToString(doc))}

// بيبني الملف من القالب + نتيجة export_report. بيرجّع {blob, counts, truncated}
async function xtBuild(Z,tpl,d){
  const zip=await Z.loadAsync(tpl),m=d.meta||{};
  for(const key of Object.keys(XT_SHEETS)){const S=XT_SHEETS[key],rows=d[key]||[];
    await xtEdit(zip,"xl/worksheets/"+S.f,(doc,sd)=>{rows.slice(0,1000).forEach((vals,i)=>{const row=xtRow(doc,sd,S.r+i);
      S.k.split("").forEach((k,ci)=>{if(k!=="-")xtCell(doc,row,XT_COLS[ci]+(S.r+i),k,vals[ci])})})})}
  const stamp=new Date().toLocaleString("ar-EG",{hourCycle:"h23",dateStyle:"medium",timeStyle:"short"});
  await xtEdit(zip,"xl/worksheets/sheet1.xml",(doc,sd)=>{const r4=xtRow(doc,sd,4);xtCell(doc,r4,"B4","d",m.from);xtCell(doc,r4,"D4","d",m.to);
    xtCell(doc,xtRow(doc,sd,2),"A2","s","تم التصدير من تطبيق الصالون بتاريخ "+stamp+" — الأرقام دي من بيانات المشروع الفعلية للفترة المحددة")});
  await xtEdit(zip,"xl/worksheets/sheet8.xml",(doc,sd)=>{
    const set=(n,v)=>xtCell(doc,xtRow(doc,sd,n),"B"+n,"s",v);
    set(4,"متصل — تصدير من التطبيق (حساب المالك)");set(5,stamp);set(6,m.from+" → "+m.to);set(7,"قاعدة بيانات المشروع (Supabase) عبر دالة export_report");set(9,"من التطبيق: التقارير ← تصدير الملف الجاهز")});
  let wb=await zip.file("xl/workbook.xml").async("string");
  wb=/<calcPr[^>]*>/.test(wb)?wb.replace(/<calcPr[^>]*\/>/,'<calcPr calcId="191029" fullCalcOnLoad="1"/>'):wb.replace("</workbook>",'<calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>');
  zip.file("xl/workbook.xml",wb);
  const blob=await zip.generateAsync({type:"blob",mimeType:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",compression:"DEFLATE"});
  return{blob,counts:m.counts||{},truncated:!!m.truncated}}

async function exportTemplate(){
  if(!me||me.role!=="owner")return toast("الملف ده للمالك بس");
  const[a,b]=C.rr||[],e=new Date(b);e.setDate(e.getDate()-1);if(!a||!b)return toast("اختار الفترة الأول");
  toast("بنجهّز الملف الجاهز…");
  let Z;try{Z=await loadZip()}catch(err){return toast(err.message)}
  const{data:d,error}=await sb.rpc("export_report",{p_token:null,p_from:ymd(a),p_to:ymd(e)});
  if(error)return toast(/Could not find the function/i.test(error.message||"")?"شغّل ملف patch_excel_export.sql في Supabase الأول":error.message);
  let tpl;try{const r=await fetch("/report-template.xlsx?v="+Date.now());if(!r.ok)throw new Error(r.status);tpl=await r.arrayBuffer()}catch(err){return toast("مقدرتش أحمّل قالب الإكسيل")}
  let out;try{out=await xtBuild(Z,tpl,d)}catch(err){return toast("فشل تجهيز الملف: "+err.message)}
  const url=URL.createObjectURL(out.blob),el=document.createElement("a");el.href=url;el.download=`تقارير-صالون-${ymd(a)}_${ymd(e)}.xlsx`;document.body.appendChild(el);el.click();el.remove();setTimeout(()=>URL.revokeObjectURL(url),4000);
  toast(out.truncated?"تم ✓ بس الفترة كبيرة: الجداول اتقطعت عند 1000 صف، قصّر الفترة":"تم تنزيل الملف الجاهز ✓")}
