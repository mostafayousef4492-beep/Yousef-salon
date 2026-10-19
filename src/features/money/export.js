/* features/money/export.js — تصدير Excel */

// ---------- تصدير Excel (SheetJS بيتحمّل وقت الضغط بس) ----------

function loadXlsx(){return new Promise((ok,no)=>{if(window.XLSX)return ok(window.XLSX);const s=document.createElement("script");s.src="https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js";s.onload=()=>window.XLSX?ok(window.XLSX):no(new Error("مكتبة Excel ما اشتغلتش"));s.onerror=()=>no(new Error("مقدرناش نحمّل مكتبة Excel، اتأكد من النت"));document.head.appendChild(s)})}

function xSheet(X,wb,name,rows){const ws=X.utils.aoa_to_sheet(rows);ws["!cols"]=(rows[0]||[]).map((_,i)=>({wch:Math.min(40,Math.max(10,...rows.map(r=>String(r[i]??"").length+2)))}));X.utils.book_append_sheet(wb,ws,name.slice(0,31))}

const PAYL={cash:"كاش",card:"كارت",wallet:"محفظة / إنستا باي"};

async function exportXlsx(){const d=C.rd,T=d.totals,[a,b]=C.rr,e=new Date(b);e.setDate(e.getDate()-1);let X;try{X=await loadXlsx()}catch(err){return toast(err.message)}
  toast("بنجهّز ملف Excel…");const da=ymd(a),db=ymd(b),A=a.toISOString(),B=b.toISOString();
  const[{data:inv},{data:pu},{data:sp},{data:cl}]=await Promise.all([sb.from("invoices").select("no,created_at,total,discount,payment_method,customers(name,phone),profiles:barber_id(full_name),invoice_items(name,qty)").gte("created_at",A).lt("created_at",B).order("created_at",{ascending:false}),sb.from("purchases").select("bought_on,kind,total,paid,note,suppliers(name)").gte("bought_on",da).lt("bought_on",db).order("bought_on"),sb.from("salary_payments").select("period,amount,paid_on,paid_from,note,profiles(full_name)").gte("paid_on",da).lt("paid_on",db).order("paid_on"),sb.from("cash_closings").select("*").gte("day",da).lt("day",db).order("day")]);
  const wb=X.utils.book_new();wb.Workbook={Views:[{RTL:true}]};const n=v=>+v||0;
  xSheet(X,wb,"الملخص",[["البند","القيمة"],["الفترة",da+" → "+ymd(e)],["المبيعات",n(T.revenue)],["تكلفة المنتجات المباعة",-n(T.cogs)],["عمولات الحلاقين",-n(T.commissions)],["رواتب ثابتة",-n(T.salaries)],["المكافآت",-n(T.bonuses)],["الخصومات على الموظفين",n(T.deductions)],["المصروفات",-n(T.expenses)],["صافي الربح",n(T.profit)],["عدد الفواتير",n(T.invoices)],["متوسط الفاتورة",n(T.avg)],["الخصومات للعملاء",n(T.discounts)]]);
  xSheet(X,wb,"الفواتير",[["رقم","التاريخ","العميل","الموبايل","الحلاق","البنود","الخصم","الإجمالي","الدفع"],...(inv||[]).map(i=>[i.no,new Date(i.created_at).toLocaleString("ar-EG"),i.customers?.name||"عابر",i.customers?.phone||"",i.profiles?.full_name||"",(i.invoice_items||[]).map(x=>x.name+"×"+x.qty).join(" + "),n(i.discount),n(i.total),PAYL[i.payment_method]||i.payment_method])]);
  xSheet(X,wb,"يوم بيوم",[["اليوم","المبيعات"],...(d.by_day||[]).map(x=>[x.d,n(x.t)])]);
  xSheet(X,wb,"طرق الدفع",[["الطريقة","الفواتير","الإجمالي"],...(d.by_pay||[]).map(x=>[PAYL[x.m]||x.m,n(x.n),n(x.t)])]);
  xSheet(X,wb,"الخدمات",[["الخدمة","العدد","الإيراد"],...(d.services||[]).map(x=>[x.n,n(x.q),n(x.t)])]);
  xSheet(X,wb,"المنتجات",[["المنتج","العدد","الإيراد","الربح"],...(d.products||[]).map(x=>[x.n,n(x.q),n(x.t),n(x.p)])]);
  xSheet(X,wb,"الحلاقين",[["الحلاق","الزباين","المبيعات","العمولة","التقييم"],...(d.barbers||[]).map(x=>[x.n,n(x.cuts),n(x.sales),n(x.comm),x.rating||""])]);
  if((d.assistants||[]).length)xSheet(X,wb,"المساعدين",[["المساعد","خدمات","قيمتها","حصة المحل","راتب الفترة"],...d.assistants.map(x=>[x.n,n(x.svc),n(x.val),n(x.cut),n(x.sal)])]);
  xSheet(X,wb,"المصروفات",[["التاريخ","البند","المبلغ","مصدر الدفع","ملاحظة"],...(C.rx||[]).map(x=>[x.spent_on,x.category,n(x.amount),x.paid_from=="other"?"من برا الدرج":"من الدرج",x.note||""])]);
  xSheet(X,wb,"المشتريات",[["التاريخ","المورد","النوع","الإجمالي","المدفوع","ملاحظة"],...(pu||[]).map(p=>[p.bought_on,p.suppliers?.name||"",p.kind=="stock"?"بضاعة":"مستلزمات",n(p.total),n(p.paid),p.note||""])]);
  xSheet(X,wb,"صرف الرواتب",[["تاريخ الصرف","الموظف","عن شهر","المبلغ","المصدر","ملاحظة"],...(sp||[]).map(p=>[p.paid_on,p.profiles?.full_name||"",p.period,n(p.amount),p.paid_from=="other"?"من برا الدرج":"من الدرج",p.note||""])]);
  xSheet(X,wb,"قفل الخزنة",[["اليوم","رصيد أول","كاش متوقع","كاش معدود","فرق الكاش","كارت متوقع","كارت معدود","فرق الكارت","محفظة متوقع","محفظة معدود","فرق المحفظة","ملاحظة"],...(cl||[]).map(c=>[c.day,n(c.opening),n(c.expected_cash),n(c.counted_cash),n(c.diff_cash),n(c.expected_card),n(c.counted_card),n(c.diff_card),n(c.expected_wallet),n(c.counted_wallet),n(c.diff_wallet),c.note||""])]);
  X.writeFile(wb,`salon-report-${da}_${ymd(e)}.xlsx`);toast("تم تنزيل ملف Excel ✓")}

async function exportMonthly(){let X;try{X=await loadXlsx()}catch(err){return toast(err.message)}const wb=X.utils.book_new();wb.Workbook={Views:[{RTL:true}]};const n=v=>+v||0;
  xSheet(X,wb,"أرباح شهرية",[["الشهر","الفواتير","المبيعات","تكلفة المنتجات","العمولات","رواتب ثابتة","مكافآت","خصومات موظفين","المصروفات","صافي الربح"],...(C.mon||[]).map(x=>[x.month,n(x.invoices),n(x.revenue),n(x.cogs),n(x.commissions),n(x.salaries),n(x.bonuses),n(x.deductions),n(x.expenses),n(x.profit)])]);
  X.writeFile(wb,`salon-monthly-profit-${ymd(new Date())}.xlsx`);toast("تم تنزيل ملف Excel ✓")}
