-- =====================================================================================================
-- 05_upgrade_v41.sql   Gaddam Venu portal v41   -> for an EXISTING database (v40).  Keeps ALL data.
-- Run it ONCE, then run  02_functions.sql  again (it is safe to run again).
-- (A NEW install does not need this file: 01_tables.sql already contains everything.)
--
-- v41 adds
--   1. TASKS: how students submit  (submit_mode = 'link' Drive link  |  'button' one press)  + ONE deadline field (date and time)
--   2. VISIBLE = true / false  for every tab of a subject and for every card inside it (the admin right-clicks and types true / false)
-- =====================================================================================================

-- ---- 1. tasks: submit mode + deadline ----
alter table tasks            add column if not exists submit_mode text not null default 'link';
alter table tasks            add column if not exists deadline timestamptz;
alter table task_submissions add column if not exists via_button boolean not null default false;

alter table tasks drop constraint if exists tasks_submit_mode_check;
alter table tasks add  constraint tasks_submit_mode_check check (submit_mode in ('link','button'));

-- a submission made with the button has no link and no file: drop the old "file or link" check and make a new one
do $$ declare c record; begin
  for c in select conname from pg_constraint
           where conrelid='public.task_submissions'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%file_data%' loop
    execute 'alter table task_submissions drop constraint '||quote_ident(c.conname);
  end loop; end $$;
alter table task_submissions drop constraint if exists task_sub_has_answer;
alter table task_submissions add  constraint task_sub_has_answer check (file_data is not null or link is not null or via_button);

-- old tasks: the old "last date" becomes the deadline (end of that day, India time)
update tasks set deadline = ((due_date + time '23:59')::timestamp at time zone 'Asia/Kolkata') where deadline is null and due_date is not null;

-- ---- 2. visible = true / false ----
alter table materials add column if not exists visible boolean not null default true;
alter table videos    add column if not exists visible boolean not null default true;
alter table notices   add column if not exists visible boolean not null default true;
alter table labs      add column if not exists visible boolean not null default true;
alter table tasks     add column if not exists visible boolean not null default true;
alter table formats   add column if not exists visible boolean not null default true;
alter table subjects  add column if not exists hidden_tabs text[] not null default '{}';   -- tabs the admin switched off (visible = false)

notify pgrst, 'reload schema';
