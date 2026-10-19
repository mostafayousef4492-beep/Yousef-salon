-- خيارات الخدمة: خدمة ليها اختيارات كل واحد بسعره (قص الشعر: كلاسيك / تدريج، دقن: موس / ماكينة ...)
-- كل اختيار خدمة عادية في services (الاسم الكامل «المجموعة — الاختيار»)، وgroup_name/option_label بيجمّعوهم في الشاشات.
alter table public.services add column if not exists group_name text, add column if not exists option_label text;
alter table public.services drop constraint if exists services_group_pair;
alter table public.services add constraint services_group_pair check ((group_name is null) = (option_label is null));
create index if not exists services_group_idx on public.services(group_name) where group_name is not null;
create unique index if not exists services_group_option_uq on public.services(group_name, option_label) where group_name is not null;
