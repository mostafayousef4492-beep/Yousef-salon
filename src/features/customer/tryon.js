/* features/customer/tryon.js — جرّب القصة بالذكاء الاصطناعي (تجريبي)
   الصورة بتتصغّر على جهاز العميل وبتتبعت لدالة hair_tryon، والنتيجة بتتعرض ومش بتتخزّن عند الصالون. */

const TRY_STYLES=[["classic","كلاسيك بفرق جانبي"],["low_fade","فيد منخفض"],["mid_fade","فيد متوسط"],["high_fade","فيد عالي"],["buzz","ماكينة صفر"],["crop","كروب فرنسي"],["pompadour","بومبادور"],["undercut","أندر كت"],["beard_light","دقن خفيفة"],["beard_full","دقن كاملة"]];
const tryName=k=>(TRY_STYLES.find(x=>x[0]==k)||[])[1]||k;
let TRY={img:null,mime:null,prev:null,style:"classic",res:null,busy:false,ck:false};

function tryonOpen(){TRY={img:null,mime:null,prev:null,style:"classic",res:null,busy:false,ck:false};tryonView()}

function tryonView(){
  if(TRY.res)return dsOpen("جرّب قصتك",`<div class="m" style="margin-bottom:6px">${esc(tryName(TRY.style))} · تصوّر تقريبي بالذكاء الاصطناعي، والنتيجة الفعلية ممكن تختلف.</div>
<img src="${TRY.res}" alt="تصوّر القصة" style="width:100%;border-radius:14px;display:block">
<div class="chips" style="margin-top:10px"><button class="btn" onclick="tryWish()">عجبني الشكل ده 👌</button><a class="btn g" download="salon-look.png" href="${TRY.res}">حمّل الصورة</a><button class="btn g" onclick="TRY.res=null;tryonView()">جرّب شكل تاني</button></div>
<div class="m" style="margin-top:8px">«عجبني» بيسجّل اسم الشكل في ملف اللوك بتاعك، والحلاق بيشوفه. الصورة نفسها مش بتتخزّن.</div>`);
  dsOpen("جرّب قصتك بالذكاء الاصطناعي",`<p class="m">شوف تصوّر تقريبي لشكل القصة أو الدقن عليك قبل ما تحلق. للكبار (18+) وبصورة وش واضحة لشخص واحد.</p>
<label class="row" style="cursor:pointer;align-items:flex-start;gap:10px"><input type="checkbox" id="try_ck" ${TRY.ck?"checked":""} onchange="TRY.ck=this.checked" style="width:22px;height:22px;margin:0;flex:none"><span class="m">موافق إن صورتي تتبعت لـ Google (Gemini) لمعالجتها وعمل التصوّر. ممكن Google تستخدم المحتوى لتحسين خدماتها. الصالون مش بيخزّن صورتي.</span></label>
<div style="margin:10px 0">${TRY.prev?`<img src="${TRY.prev}" alt="صورتك" style="width:96px;height:96px;object-fit:cover;border-radius:12px;display:block;margin-bottom:6px">`:""}<input type="file" id="try_f" accept="image/*" onchange="tryPick(this)"></div>
<div class="m">اختار الشكل</div><div class="chips" style="margin:6px 0 12px">${TRY_STYLES.map(x=>`<button class="chip ${TRY.style==x[0]?"sel":""}" onclick="TRY.style='${x[0]}';tryonView()">${x[1]}</button>`).join("")}</div>
<button class="btn" style="width:100%" ${TRY.busy?"disabled":""} onclick="tryRun()">${TRY.busy?"بنجهّز التصوّر… ممكن ياخد لحد دقيقة":"جرّب الشكل"}</button>
<div class="m" style="margin-top:8px">فيه حد أقصى للتجارب في اليوم.</div>`)}

// الصورة بتتصغّر لـ 1024 بكسل JPEG قبل الإرسال (أسرع وأوفر ومش بتخزّن الأصل)
function tryPick(inp){const f=inp.files&&inp.files[0];if(!f)return;if(!/^image\//.test(f.type))return toast("اختار صورة");
  const r=new FileReader();r.onload=()=>{const im=new Image();im.onload=()=>{const k=Math.min(1,1024/Math.max(im.width,im.height)),cv=document.createElement("canvas");cv.width=Math.max(1,Math.round(im.width*k));cv.height=Math.max(1,Math.round(im.height*k));cv.getContext("2d").drawImage(im,0,0,cv.width,cv.height);const u=cv.toDataURL("image/jpeg",0.85);TRY.img=u.split(",")[1];TRY.mime="image/jpeg";TRY.prev=u;tryonView()};im.onerror=()=>toast("الصورة مش مفهومة، جرّب غيرها");im.src=r.result};r.onerror=()=>toast("مقدرناش نقرا الصورة");r.readAsDataURL(f)}

async function tryRun(){if(TRY.busy)return;if(!TRY.ck)return toast("لازم توافق الأول");if(!TRY.img)return toast("اختار صورتك الأول");
  TRY.busy=true;tryonView();
  try{const{data,error}=await sb.functions.invoke("hair_tryon",{body:{image:TRY.img,mime:TRY.mime,style:TRY.style,consent:true}});
    TRY.busy=false;
    if(error){let m="حصلت مشكلة، جرّب تاني";try{const j=await error.context.json();if(j&&j.error)m=j.error}catch(e){}tryonView();return toast(m)}
    if(!data||!data.image){tryonView();return toast("مفيش نتيجة، جرّب تاني")}
    TRY.res="data:"+(data.mime||"image/png")+";base64,"+data.image;tryonView()}
  catch(e){TRY.busy=false;tryonView();toast("حصلت مشكلة في الاتصال")}}

async function tryWish(){const{error}=await sb.rpc("my_look_wish",{p_style:tryName(TRY.style)});error?toast(error.message):toast("اتسجّل في ملف اللوك ✓")}
