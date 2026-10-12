// فحص منطقي ثابت (بدون Postgres) لمسار التراجع: كل كائن بتنشئه الترقية لازم يتعالج في ملف التراجع.
// ⚠ ده فحص نصّي — مش تنفيذ. التنفيذ الحقيقي للتراجع لازم يتجرّب على نسخة تجريبية.
import fs from 'node:fs'; import assert from 'node:assert/strict';
const up=fs.readFileSync(new URL('../sql/booking_queue_upgrade.sql',import.meta.url),'utf8');
const rb=fs.readFileSync(new URL('../sql/booking_queue_rollback.sql',import.meta.url),'utf8');
const ORIGINAL=['make_ticket','walk_in_ticket','public_book','admin_book_ticket']; // موجودة قبل الترقية ومتبدّلة (CREATE OR REPLACE)
const sig=(sql,n)=>{const m=sql.match(new RegExp(`create or replace function public\\.${n}\\(([^)]*)\\)`,'i'));return m&&m[1].split(',').map(x=>x.trim().split(/\s+/).slice(1).join(' ').replace(/ default .*/i,'')).join(',')};
const created=[...up.matchAll(/create or replace function public\.(\w+)\(/gi)].map(m=>m[1]);
let n=0;const ok=(c,m)=>{assert.ok(c,m);n++;console.log('✓',m)};
for(const f of new Set(created)){
  if(ORIGINAL.includes(f)){
    ok(sig(up,f)===sig(rb,f),`${f}: التوقيع في التراجع = التوقيع في الترقية (${sig(rb,f)})`);
    ok(new RegExp(`create or replace function public\\.${f}\\(`,'i').test(rb),`${f}: بيترجّع لتعريفه الأصلي`);
    ok(!new RegExp(`drop function[^;]*public\\.${f}\\(`,'i').test(rb),`${f}: ما بيتحذفش`);
  } else ok(new RegExp(`drop function if exists public\\.${f}\\(`,'i').test(rb),`${f}: جديدة => بتتحذف في التراجع`);
}
for(const t of [...up.matchAll(/create trigger (\w+)/gi)].map(m=>m[1])) ok(new RegExp(`drop trigger if exists ${t}\\b`,'i').test(rb),`trigger ${t} بيتحذف`);
for(const i of [...up.matchAll(/create unique index if not exists (\w+)/gi)].map(m=>m[1])) ok(new RegExp(`drop index if exists public\\.${i}`,'i').test(rb),`index ${i} بيتحذف`);
ok(/update public\.app_settings set value = '0'/.test(up)&&/update public\.app_settings set value = '10'/.test(rb),'إعداد no_show_after_minutes: الترقية 0 والتراجع 10');
const pos=(re)=>rb.search(re);
ok(pos(/create or replace function public\.walk_in_ticket\(/i)<pos(/drop function if exists public\.walk_in_ticket_v2/i),'walk_in_ticket الأصلية بتترجّع قبل حذف walk_in_ticket_v2');
ok(pos(/create or replace function public\.public_book\(/i)<pos(/drop function if exists public\.p14_book_core/i),'public_book الأصلية بتترجّع قبل حذف p14_book_core');
ok(pos(/create or replace function public\.make_ticket\(/i)<pos(/drop function if exists public\.p14_make_ticket/i),'make_ticket الأصلية بتترجّع قبل حذف p14_make_ticket');
ok(pos(/drop trigger if exists zz_p14_notify_order/i)<pos(/drop function if exists public\.p14_notify_order_change/i),'الـtrigger بيتحذف قبل دالته');
ok(!/grant\s/i.test(rb.replace(/--.*$/gm,'')),'التراجع ما بيمنحش صلاحيات (ACL الأصلية ما اتغيّرتش)');
console.log(`\n${n} rollback-consistency checks passed (static)`);
