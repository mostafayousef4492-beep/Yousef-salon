/* features/customer/mascot.js — «يوسف» مجسّم الصالون: شخصية ثلاثية الأبعاد (شبه 3D بطبقات SVG + منظور CSS)
   بيرمش ويتنفّس ويلوّح ويتكلم وعينه بتتابع الصباع. مفيش مكتبات خارجية. */
(()=>{
const SVG=`<svg viewBox="0 0 240 300" class="mc-svg" aria-hidden="true">
<defs>
<radialGradient id="mcSk" cx="42%" cy="35%" r="75%"><stop offset="0" stop-color="#FFD9B8"/><stop offset=".6" stop-color="#F0B88C"/><stop offset="1" stop-color="#D79868"/></radialGradient>
<linearGradient id="mcHr" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3A2A22"/><stop offset=".55" stop-color="#1B1210"/><stop offset="1" stop-color="#0E0908"/></linearGradient>
<linearGradient id="mcAp" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2A2F3D"/><stop offset="1" stop-color="#141821"/></linearGradient>
<linearGradient id="mcGd" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#F0D78F"/><stop offset=".5" stop-color="#C9A24B"/><stop offset="1" stop-color="#8F6F2A"/></linearGradient>
<radialGradient id="mcSh" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#000" stop-opacity=".45"/><stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>
</defs>
<ellipse cx="120" cy="288" rx="78" ry="9" fill="url(#mcSh)"/>
<g class="mc-body">
 <path d="M38 292 C38 232 70 214 120 214 C170 214 202 232 202 292 Z" fill="url(#mcAp)"/>
 <path d="M38 292 C38 232 70 214 120 214 C170 214 202 232 202 292" fill="none" stroke="url(#mcGd)" stroke-width="3"/>
 <path d="M96 214 L120 250 L144 214 Z" fill="#F4EFE6"/>
 <path d="M104 238 L120 232 L136 238 L120 246 Z" fill="url(#mcGd)"/><circle cx="120" cy="238" r="4.5" fill="#8F6F2A"/>
 <rect x="104" y="262" width="32" height="26" rx="6" fill="#0E1118" stroke="#C9A24B" stroke-opacity=".5"/>
 <path d="M112 270 h16 M112 277 h10" stroke="#C9A24B" stroke-width="2" stroke-linecap="round"/>
</g>
<g class="mc-arm-l"><path d="M44 250 C30 262 28 278 34 288" fill="none" stroke="url(#mcAp)" stroke-width="22" stroke-linecap="round"/><circle cx="34" cy="288" r="11" fill="url(#mcSk)"/></g>
<g class="mc-arm-r">
 <path d="M196 246 C214 236 220 214 214 196" fill="none" stroke="url(#mcAp)" stroke-width="22" stroke-linecap="round"/>
 <g class="mc-hand"><circle cx="214" cy="188" r="12" fill="url(#mcSk)"/>
  <g transform="translate(214 168) rotate(-20)"><path d="M-3 0 L-9 -22" stroke="url(#mcGd)" stroke-width="3.5" stroke-linecap="round"/><path d="M3 0 L9 -22" stroke="#E8CB7C" stroke-width="3.5" stroke-linecap="round"/><circle cx="-5" cy="6" r="5" fill="none" stroke="url(#mcGd)" stroke-width="3"/><circle cx="5" cy="6" r="5" fill="none" stroke="#E8CB7C" stroke-width="3"/></g></g>
</g>
<rect x="104" y="188" width="32" height="34" rx="12" fill="#D79868"/>
<g class="mc-head">
 <ellipse cx="62" cy="130" rx="10" ry="15" fill="#E3A777"/><ellipse cx="178" cy="130" rx="10" ry="15" fill="#E3A777"/>
 <path d="M120 52 C74 52 58 88 60 124 C62 164 88 196 120 196 C152 196 178 164 180 124 C182 88 166 52 120 52 Z" fill="url(#mcSk)"/>
 <path d="M60 124 C62 164 88 196 120 196 C152 196 178 164 180 124 C176 150 154 176 120 178 C86 176 64 150 60 124 Z" fill="#B97D4E" opacity=".18"/>
 <path d="M58 112 C48 62 84 30 124 34 C170 36 192 70 182 112 C176 92 168 78 150 70 C128 80 92 80 70 74 C62 84 60 98 58 112 Z" fill="url(#mcHr)"/>
 <path d="M84 52 C104 40 134 38 156 50" fill="none" stroke="#6B5246" stroke-width="3" stroke-linecap="round" opacity=".55"/>
 <path d="M70 150 C74 176 96 192 120 192 C144 192 166 176 170 150 C160 170 140 178 120 178 C100 178 80 170 70 150 Z" fill="#1B1210" opacity=".55"/>
 <g class="mc-brows" stroke="#1B1210" stroke-width="5" stroke-linecap="round" fill="none"><path d="M82 100 Q96 92 110 99"/><path d="M130 99 Q144 92 158 100"/></g>
 <g class="mc-eyes"><g class="mc-eye"><ellipse cx="96" cy="118" rx="12" ry="13" fill="#fff"/><circle class="mc-pu" cx="96" cy="119" r="7" fill="#2A1A12"/><circle cx="99" cy="115" r="2.5" fill="#fff"/></g>
 <g class="mc-eye"><ellipse cx="144" cy="118" rx="12" ry="13" fill="#fff"/><circle class="mc-pu" cx="144" cy="119" r="7" fill="#2A1A12"/><circle cx="147" cy="115" r="2.5" fill="#fff"/></g></g>
 <ellipse cx="82" cy="146" rx="10" ry="6" fill="#E57A6B" opacity=".28"/><ellipse cx="158" cy="146" rx="10" ry="6" fill="#E57A6B" opacity=".28"/>
 <path d="M120 122 C116 134 112 142 118 146 C122 148 126 146 128 144" fill="none" stroke="#C48458" stroke-width="3" stroke-linecap="round"/>
 <path d="M84 156 C96 146 112 152 120 156 C128 152 144 146 156 156 C146 166 130 164 120 162 C110 164 94 166 84 156 Z" fill="url(#mcHr)"/>
 <g class="mc-mouth"><path class="mc-m-c" d="M104 170 Q120 182 136 170" fill="none" stroke="#7A3B2E" stroke-width="4" stroke-linecap="round"/>
  <ellipse class="mc-m-o" cx="120" cy="174" rx="11" ry="8" fill="#5A1F1A"/><ellipse class="mc-m-t" cx="120" cy="178" rx="6" ry="3" fill="#E57A6B"/></g>
</g></svg>`;
window.MASCOT={svg:SVG,head:()=>SVG.replace('viewBox="0 0 240 300" class="mc-svg"','viewBox="44 28 152 176" class="mc-svg mc-mini"'),
 mount(el){el.innerHTML=`<div class="mc-wrap"><div class="mc-3d">${SVG}</div></div>`;
  const w=el.querySelector(".mc-wrap"),svg=el.querySelector(".mc-svg"),pu=[...el.querySelectorAll(".mc-pu")];
  const look=(x,y)=>{const r=svg.getBoundingClientRect(),cx=r.left+r.width/2,cy=r.top+r.height*.4,dx=Math.max(-1,Math.min(1,(x-cx)/220)),dy=Math.max(-1,Math.min(1,(y-cy)/220));
    w.style.setProperty("--ry",(dx*14).toFixed(1)+"deg");w.style.setProperty("--rx",(-dy*9).toFixed(1)+"deg");pu.forEach((p,i)=>p.style.transform=`translate(${dx*4}px,${dy*3}px)`)};
  const mv=e=>{const t=e.touches?e.touches[0]:e;look(t.clientX,t.clientY)};
  addEventListener("pointermove",mv,{passive:true});addEventListener("touchmove",mv,{passive:true});
  return{talk(on){el.classList.toggle("mc-talk",!!on)},wave(on){el.classList.toggle("mc-wave",!!on)},look,destroy(){removeEventListener("pointermove",mv);removeEventListener("touchmove",mv)}}}};
})();
