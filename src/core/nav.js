/* core/nav.js — أقسام القائمة */

// الهيكل الجديد: ٦ أقسام + مركز التحكم (للمالك). كل شاشة ليها مكان واحد بس.
//   الرئيسية · الصالة · العملاء · الفريق · الحسابات والتقارير · الخدمات والمخزون · (مركز التحكم)
// كل قسم = [id, الاسم، الأيقونة، الشاشات اللي جواه (بالترتيب)، الاسم لغير الإدارة]
const HUBS=[
  ["h_ops","الصالة","menu",["pos","appts"],"الصالة"],
  ["h_cust","العملاء","cust",["cust","rem"],"العملاء"],
  ["h_hr","الفريق","team",["team","att","tgt","ann","lb","me"],"شاشتي"],
  ["h_fin","الحسابات والتقارير","fin",["inv","cash","fin","rep"],"الخزنة والفواتير"],
  ["h_stk","الخدمات والمخزون","stock",["svc","stock"],"الخدمات والمخزون"],
  ["h_cafe","كوفي كورنر","cafe",["cafe_dash","cafe","cafe_prods","cafe_buy","cafe_exp","cafe_rep"],"كوفي كورنر"],
  ["h_ctl","مركز التحكم","ctl",["ctl","set"],"مركز التحكم"]
];

// ترتيب الأقسام في القائمة. المثبّت في آخر القائمة الجانبية: مركز التحكم.
const TAB_ORDER=["home","h_ops","pos","appts","h_cust","cust","rem","h_hr","team","att","me","ann","tgt","lb","h_fin","inv","cash","fin","rep","h_stk","svc","stock","h_cafe","cafe_dash","cafe","cafe_prods","cafe_buy","cafe_exp","cafe_rep","h_ctl","ctl","set","none"];
const NAV_PINNED=["h_ctl","ctl","set"];

// أسماء وصفية للشاشات الفرعية (الشريط الفرعي جوه القسم)
const SUB_LABEL={cafe_dash:"لوحة الكوفي",cafe:"بيع سريع",cafe_prods:"المنتجات والأسعار",cafe_buy:"المشتريات والمخزون",cafe_exp:"المصروفات",cafe_rep:"التقارير",pos:"الكراسي والكاشير",appts:"الحجوزات والطابور",cust:"العملاء",rem:"التذكير",team:"الموظفين",att:"الحضور",tgt:"التارجت",ann:"الإعلانات",lb:"لوحة الشرف",me:"شاشتي",inv:"الفواتير",cash:"الخزنة",fin:"المالية",rep:"التقارير",svc:"الخدمات",stock:"المخزون",ctl:"مركز التحكم",set:"الإعدادات"};

function hubTabs(T){const tabs=[],hubs={},done=new Set(),adm=isAdm(me);
  T.forEach(x=>{const H=HUBS.find(h=>h[3].includes(x[0]));if(!H){tabs.push(x);return}if(done.has(H[0]))return;done.add(H[0]);
    let m=H[3].map(k=>T.find(y=>y[0]==k)).filter(Boolean);
    if(m.length<2){tabs.push(x);return}
    if(!adm&&H[0]=="h_hr")m=[...m.filter(y=>y[0]=="me"),...m.filter(y=>y[0]!="me")];
    m=m.map(y=>[y[0],SUB_LABEL[y[0]]||y[1]]);
    hubs[H[0]]=m;tabs.push([H[0],adm?H[1]:H[4],(!adm&&H[0]=="h_hr")?"me":H[2],m.map(y=>y[0])])});
  return{tabs,hubs}}
