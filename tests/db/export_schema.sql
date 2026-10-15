-- شغّله على الإنتاج (قراءة فقط) وسيب النتيجة في schema.json — build.py بيبني منها نسخة محلية للاختبار.
select jsonb_build_object(
 'funcs', (select jsonb_agg(jsonb_build_object('n',p.proname,'d',pg_get_functiondef(p.oid))) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f'),
 'cols', (select jsonb_agg(jsonb_build_object('t',c.relname,'c',a.attname,'ty',format_type(a.atttypid,a.atttypmod),'nn',a.attnotnull,'df',pg_get_expr(d.adbin,d.adrelid),'gen',a.attgenerated)) from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum where n.nspname='public' and c.relkind='r'),
 'cons', (select jsonb_agg(jsonb_build_object('t',c.relname,'n',k.conname,'d',pg_get_constraintdef(k.oid),'ty',k.contype)) from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'),
 'idx', (select jsonb_agg(indexdef) from pg_indexes where schemaname='public'),
 'trg', (select jsonb_agg(pg_get_triggerdef(t.oid)) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal),
 'pol', (select jsonb_agg(jsonb_build_object('t',tablename,'n',policyname,'cmd',cmd,'roles',roles,'q',qual,'w',with_check)) from pg_policies where schemaname='public'),
 'enums', (select jsonb_agg(jsonb_build_object('n',t.typname,'v',(select jsonb_agg(e.enumlabel order by e.enumsortorder) from pg_enum e where e.enumtypid=t.oid))) from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typtype='e')
) as j;
