/* main.js — نقطة البداية */

const _boot=boot;

boot=async function(){const r=await _boot.apply(this,arguments);pushAfterBoot().catch(()=>{});return r};

boot();
