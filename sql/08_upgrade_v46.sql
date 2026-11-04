-- =====================================================================================================
-- 08_upgrade_v46.sql   Gaddam Venu portal v46   -> for an EXISTING database (v41 - v45).  Keeps ALL data.
-- Run ONLY THIS FILE, once in  Supabase > SQL Editor  (safe to run again).  Do NOT run 02_functions.sql after it.
-- NEW install: run 01_tables.sql, 02_functions.sql, 03_admin_seed.sql and then this file.
--
-- v46 changes
--   1. EXAMS are now LINKS.  The exam builder (Theory MCQ / Lab write-up / templates / marking) is removed.
--      The admin posts  Lab exam | Theory exam | Login IDs  as a link; students open it in a NEW page.
--   2. LAB MANUAL tab (Theory + Lab subjects): Name + Google Drive link + optional note, for all students or one batch.
--   3. MATERIALS: category  Other  with a name you type (Previous papers, Question bank ...).
--   4. ZOOM MEETING tab: Title + meeting link (+ optional date and time).
--   5. TASKS: title + Google Drive link + deadline (no SQL change; the form is simpler).
-- =====================================================================================================

-- ---------- 0. remove the old exam builder (functions only; the old exam TABLES and their data are kept, see the end of the file) ----------
do $$ declare r record; begin
  for r in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace='public'::regnamespace
             and (p.proname like 'exam\_%' or p.proname like '\_exam\_%' or p.proname='exams_list'
                  or p.proname in ('_q_score','_unperm','_disp_opts','_disp_ans','_merge_max','_vlog_merge'))
  loop execute 'drop function if exists ' || r.sig || ' cascade'; end loop;
end $$;

-- ---------- 1. new tables ----------
create table if not exists exam_links(           -- Lab exam / Theory exam / Login IDs posted as a link
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  kind text not null check (kind in ('lab','theory','login')),
  title text not null, link text not null,
  visible boolean not null default true,
  created_at timestamptz default now());
create table if not exists lab_manuals(          -- lab manual: Google Drive link, for all students or for one batch
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  title text not null, note text, link text not null,
  batch smallint check (batch is null or batch in (1,2)),
  visible boolean not null default true,
  created_at timestamptz default now());
create table if not exists meetings(             -- Zoom / Google Meet / Teams link
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  title text not null, link text not null, starts_at timestamptz,
  visible boolean not null default true,
  created_at timestamptz default now());
create index if not exists exam_links_sub on exam_links(subject_id, created_at desc);
create index if not exists lab_manuals_sub on lab_manuals(subject_id, created_at desc);
create index if not exists meetings_sub on meetings(subject_id, created_at desc);
alter table exam_links enable row level security;
alter table lab_manuals enable row level security;
alter table meetings enable row level security;

-- materials: the category  Other  + the name the admin types for it
alter table materials add column if not exists label text;
alter table materials drop constraint if exists materials_category_check;
alter table materials add constraint materials_category_check check (category in ('Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks','Other'));

-- ---------- 2. materials: Other + name ----------
create or replace function _mat_tab(cat text) returns text language sql immutable as $$
  select case when cat in ('Theory Syllabus','Lab Syllabus') then 'syllabus'
              when cat in ('Theory Lesson Plan','Lab Lesson Plan') then 'lessonplan'
              when cat like 'Unit %' or cat='Other' then 'materials'
              when cat='Lab Marks' then 'labsheet' else 'marks' end $$;

create or replace function material_add(t text, sid uuid, rw jsonb) returns int language plpgsql security definer set search_path=public as $$
declare x jsonb; n int:=0; ti text; cd text; kd text; lb text; begin perform _admin(t);
  select kind into kd from subjects where id=sid; if kd is null then raise exception 'Subject not found'; end if;
  for x in select * from jsonb_array_elements(rw) loop
    if x->>'category' in ('Lab Marks','Lab Syllabus','Lab Lesson Plan') and kd<>'lab' then raise exception 'Lab Syllabus, Lab Lesson Plan and Lab Sheet are only for Theory + Lab subjects'; end if;
    if coalesce(x->>'category','') <> all(array['Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks','Other']) then raise exception 'Choose a valid category'; end if;
    if coalesce(x->>'link','') !~* '^https?://\S+$' then raise exception 'Every row needs a valid link (starting with https://)'; end if;
    lb:=null;
    if x->>'category'='Other' then
      lb:=nullif(trim(coalesce(x->>'label','')),'');
      if lb is null then raise exception 'For Other, type what it is (example: Previous question papers)'; end if;
      if length(lb)>60 then raise exception 'The name after Other is too long (60 characters)'; end if;
    end if;
    ti:=coalesce(nullif(trim(x->>'title'),''), lb, x->>'category');
    insert into materials(subject_id,category,title,link,label) values(sid,x->>'category',ti,trim(x->>'link'),lb); n:=n+1;
  end loop;
  select code into cd from subjects where id=sid;
  insert into activity(msg) values(n||' material(s) added to '||cd);
  perform _notify_subject(sid,'material',cd||' · new upload',n||' item(s) added',
    'subject/'||cd||'/'||_mat_tab(rw->0->>'category')); return n; end $$;

-- ---------- 3. EXAM LINKS ----------
create or replace function examlinks_get(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; begin r:=_access(t,sid);
  if r<>'admin' and _hid(sid,'exams') then return '[]'::json; end if;
  return (select coalesce(json_agg(x order by x.created_at desc),'[]') from (select id,kind,title,link,visible,created_at from exam_links where subject_id=sid and (r='admin' or visible)) x); end $$;

create or replace function examlink_add(t text, sid uuid, kd text, ti text, lk text) returns void language plpgsql security definer set search_path=public as $$
declare cd text; v text; nm text; begin perform _admin(t);
  if kd is null or kd not in ('lab','theory','login') then raise exception 'Choose Lab exam, Theory exam or Login IDs'; end if;
  if length(trim(coalesce(ti,'')))<1 then raise exception 'Enter a title'; end if;
  if length(ti)>120 then raise exception 'The title is too long (120 characters)'; end if;
  v:=btrim(coalesce(lk,'')); if v !~* '^https?://\S+$' then raise exception 'Paste a valid link (starting with https://)'; end if;
  if length(v)>1000 then raise exception 'The link is too long'; end if;
  select code into cd from subjects where id=sid; if cd is null then raise exception 'Subject not found'; end if;
  insert into exam_links(subject_id,kind,title,link) values(sid,kd,trim(ti),v);
  nm:=case kd when 'lab' then 'Lab exam' when 'theory' then 'Theory exam' else 'Exam login IDs' end;
  insert into activity(msg) values(nm||' link posted in '||cd);
  perform _notify_subject(sid,'exam',cd||' · '||nm||': '||trim(ti),null,'subject/'||cd||'/exams'); end $$;

create or replace function examlink_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from exam_links where id=i; end $$;

-- ---------- 4. LAB MANUAL ----------
create or replace function labmanual_get(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; mb smallint; begin r:=_access(t,sid); k:=_s(t);
  if r<>'admin' and _hid(sid,'labmanual') then return '[]'::json; end if;
  if r='student' then select batch into mb from lab_batch_members where subject_id=sid and student_id=k.user_id; end if;
  return (select coalesce(json_agg(x order by x.created_at desc),'[]') from (
    select id,title,note,link,batch,visible,created_at from lab_manuals
    where subject_id=sid and (r<>'student' or batch is null or batch=mb) and (r='admin' or visible)) x); end $$;

create or replace function labmanual_add(t text, sid uuid, ti text, nt text, lk text, bt int) returns void language plpgsql security definer set search_path=public as $$
declare cd text; kd text; b smallint; bn text; begin perform _admin(t);
  select kind, code into kd, cd from subjects where id=sid; if kd is null then raise exception 'Subject not found'; end if;
  if kd<>'lab' then raise exception 'Lab Manual is only for Theory + Lab subjects'; end if;
  if length(trim(coalesce(ti,'')))<1 then raise exception 'Enter the name of the lab manual'; end if;
  if length(ti)>120 then raise exception 'The name is too long (120 characters)'; end if;
  if length(coalesce(nt,''))>300 then raise exception 'The note is too long (300 characters)'; end if;
  b:=case when coalesce(bt,0)=0 then null else bt::smallint end;
  if b is not null and b not in (1,2) then raise exception 'Batch must be 1 or 2'; end if;
  if b is not null and not exists(select 1 from lab_batch_members where subject_id=sid and batch=b) then
    raise exception 'Batch % has no students yet. Create the batches in Lab Programs first, or post for all students.', b; end if;
  insert into lab_manuals(subject_id,title,note,link,batch) values(sid,trim(ti),nullif(trim(coalesce(nt,'')),''),_drive(lk),b);
  insert into activity(msg) values('Lab manual posted in '||cd);
  bn:=case when b is null then '' else ' (Batch '||b||')' end;
  if b is null then perform _notify_subject(sid,'labmanual',cd||' · new lab manual: '||trim(ti),null,'subject/'||cd||'/labmanual');
  else
    insert into notifications(role,user_id,subject_id,kind,title,body,link)
      select 'student', m.student_id, sid, 'labmanual', cd||' · new lab manual'||bn||': '||trim(ti), null, 'subject/'||cd||'/labmanual'
      from lab_batch_members m where m.subject_id=sid and m.batch=b
      union all select 'cr', c.cr_id, sid, 'labmanual', cd||' · new lab manual'||bn||': '||trim(ti), null, 'subject/'||cd||'/labmanual' from cr_subjects c where c.subject_id=sid;
  end if; end $$;

create or replace function labmanual_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from lab_manuals where id=i; end $$;

-- ---------- 5. ZOOM MEETING ----------
create or replace function meetings_get(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; begin r:=_access(t,sid);
  if r<>'admin' and _hid(sid,'meetings') then return '[]'::json; end if;
  return (select coalesce(json_agg(x order by coalesce(x.starts_at,x.created_at) desc),'[]') from (select id,title,link,starts_at,visible,created_at from meetings where subject_id=sid and (r='admin' or visible)) x); end $$;

create or replace function meeting_add(t text, sid uuid, ti text, lk text, st text) returns void language plpgsql security definer set search_path=public as $$
declare cd text; v text; d timestamptz; begin perform _admin(t);
  if length(trim(coalesce(ti,'')))<1 then raise exception 'Enter the meeting title'; end if;
  if length(ti)>120 then raise exception 'The title is too long (120 characters)'; end if;
  v:=btrim(coalesce(lk,'')); if v !~* '^https?://\S+$' then raise exception 'Paste a valid meeting link (starting with https://)'; end if;
  if length(v)>1000 then raise exception 'The link is too long'; end if;
  if btrim(coalesce(st,''))<>'' then begin d:=btrim(st)::timestamptz; exception when others then raise exception 'The date and time are not valid'; end; end if;
  select code into cd from subjects where id=sid; if cd is null then raise exception 'Subject not found'; end if;
  insert into meetings(subject_id,title,link,starts_at) values(sid,trim(ti),v,d);
  insert into activity(msg) values('Meeting posted in '||cd);
  perform _notify_subject(sid,'meeting',cd||' · meeting: '||trim(ti),
    case when d is not null then to_char(d at time zone 'Asia/Kolkata','DD Mon YYYY, HH12:MI AM') end,'subject/'||cd||'/meetings'); end $$;

create or replace function meeting_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from meetings where id=i; end $$;

-- ---------- 6. visible = true / false for the new tabs and cards ----------
create or replace function tab_visible_set(t text, sid uuid, tb text, vis boolean) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  if tb is null or tb not in ('syllabus','lessonplan','materials','videos','marks','notices','tasks','exams','labs','labsheet','teams','formats','work','labmanual','meetings') then raise exception 'This tab cannot be hidden'; end if;
  if vis is null then raise exception 'Type true or false'; end if;
  update subjects set hidden_tabs = case when vis then array_remove(hidden_tabs,tb) else array_remove(hidden_tabs,tb) || tb end where id=sid;
  if not found then raise exception 'Subject not found'; end if; end $$;

create or replace function item_visible_set(t text, kd text, i uuid, vis boolean) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  if vis is null then raise exception 'Type true or false'; end if;
  if    kd='material'  then update materials   set visible=vis where id=i;
  elsif kd='video'     then update videos      set visible=vis where id=i;
  elsif kd='notice'    then update notices     set visible=vis where id=i;
  elsif kd='lab'       then update labs        set visible=vis where id=i;
  elsif kd='task'      then update tasks       set visible=vis where id=i;
  elsif kd='format'    then update formats     set visible=vis where id=i;
  elsif kd='examlink'  then update exam_links  set visible=vis where id=i;
  elsif kd='labmanual' then update lab_manuals set visible=vis where id=i;
  elsif kd='meeting'   then update meetings    set visible=vis where id=i;
  else raise exception 'Wrong item'; end if;
  if not found then raise exception 'Item not found'; end if; end $$;

-- ---------- 7. subject_content: materials now carry the Other name ----------
create or replace function subject_content(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; mb smallint; hid text[]; begin r:=_access(t,sid); k:=_s(t);
  if r='student' then select batch into mb from lab_batch_members where subject_id=sid and student_id=k.user_id; end if;
  select hidden_tabs into hid from subjects where id=sid;                          -- v41: tabs switched off by the admin (visible = false)
  return json_build_object('role',r,'tasks',(select count(*) from tasks where subject_id=sid and (r='admin' or (visible and not ('tasks'=any(hid))))),
    'subject',(select json_build_object('id',id,'code',code,'name',name,'year',year,'full_name',full_name,'kind',kind,'hidden_tabs',hidden_tabs) from subjects where id=sid),
    'materials',(select coalesce(json_agg(json_build_object('id',m.id,'category',m.category,'title',m.title,'link',m.link,'label',m.label,'visible',m.visible,'created_at',m.created_at)
        order by array_position(array['Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks','Other'],m.category), m.label, m.created_at),'[]') from materials m
        where m.subject_id=sid and (r='admin' or (m.visible and not (_mat_tab(m.category)=any(hid))))),
    'videos',(select coalesce(json_agg(v order by v.created_at desc),'[]') from videos v where v.subject_id=sid and (r='admin' or (v.visible and not ('videos'=any(hid))))),
    'notices',(select coalesce(json_agg(n order by n.created_at desc),'[]') from notices n where n.subject_id=sid and (r='admin' or (n.visible and not ('notices'=any(hid))))),
    'labs',(select coalesce(json_agg(l order by l.lab_date nulls last, l.lab_time nulls last, l.created_at),'[]') from labs l
        where l.subject_id=sid and (r<>'student' or l.batch is null or l.batch=mb) and (r='admin' or (l.visible and not ('labs'=any(hid))))),
    'admin',(select json_build_object('name',coalesce(nullif(name,''),'Admin'),'photo',photo) from admins order by username limit 1),
    'crs',(select coalesce(json_agg(json_build_object('name',coalesce(nullif(c.name,''),c.username),'photo',c.photo) order by c.username),'[]') from crs c join cr_subjects x on x.cr_id=c.id where x.subject_id=sid)); end $$;

-- ---------- 8. subject list + dashboard without the old exam tables ----------
create or replace function subjects_list(t text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  return (select coalesce(json_agg(x order by x.year desc, x.code),'[]') from (
    select s.id, s.code, s.name, s.year, s.full_name, s.kind,
      (select count(*) from enrollments e where e.subject_id=s.id) as students,
      (select count(*) from materials m where m.subject_id=s.id and m.category not in ('Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan')) as materials,
      (select count(*) from notices n where n.subject_id=s.id) as notices,
      (select count(*) from labs l where l.subject_id=s.id) as labs,
      (select count(*) from videos v where v.subject_id=s.id) as videos,
      (select count(*) from tasks x where x.subject_id=s.id) as tasks,
      (select count(*) from exam_links x where x.subject_id=s.id and (k.role='admin' or x.visible)) as exams,
      (select count(*) from lab_manuals x where x.subject_id=s.id and (k.role='admin' or x.visible)) as labmanuals,
      (select count(*) from meetings x where x.subject_id=s.id and (k.role='admin' or x.visible)) as meetings,
      (select count(*) from teams x where x.subject_id=s.id) as teams,
      (select count(*) from work_posts x where x.subject_id=s.id) as work,
      (select count(*) from formats x where x.subject_id=s.id) as formats
    from subjects s where s.id in (select * from _mysubs(k))) x); end $$;
create or replace function dashboard(t text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  return json_build_object('role',k.role,
    'events',(select coalesce(json_agg(e order by e."date", e."time"),'[]') from (
        select 'Notice' as kind, n.title, s.code, n.due_date as "date", n.due_time as "time" from notices n join subjects s on s.id=n.subject_id
          where n.due_date is not null and n.subject_id in (select * from _mysubs(k)) and (k.role='admin' or (n.visible and not _hid(n.subject_id,'notices')))
        union all
        select 'Task', x.title, s.code, x.due_date, null::time from tasks x join subjects s on s.id=x.subject_id
          where x.due_date is not null and x.subject_id in (select * from _mysubs(k)) and (k.role='admin' or (x.visible and not _hid(x.subject_id,'tasks')))
        union all
        select 'Meeting', x.title, s.code, (x.starts_at at time zone 'Asia/Kolkata')::date, (x.starts_at at time zone 'Asia/Kolkata')::time from meetings x join subjects s on s.id=x.subject_id
          where x.starts_at is not null and x.subject_id in (select * from _mysubs(k)) and (k.role='admin' or (x.visible and not _hid(x.subject_id,'meetings')))
        union all
        select 'Lab', trim('Exp '||coalesce(l.exp_no,'')||' '||l.title), s.code, l.lab_date, l.lab_time from labs l join subjects s on s.id=l.subject_id
          where l.lab_date is not null and l.subject_id in (select * from _mysubs(k)) and (k.role='admin' or (l.visible and not _hid(l.subject_id,'labs')))) e),
    'stats',case when k.role='admin' then json_build_object(
        'subjects',(select count(*) from subjects),'students',(select count(*) from students),'crs',(select count(*) from crs),
        'materials',(select count(*) from materials where category not in ('Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan')),'videos',(select count(*) from videos),'notices',(select count(*) from notices),'labs',(select count(*) from labs),
        'tasks',(select count(*) from tasks),'exams',(select count(*) from exam_links),'meetings',(select count(*) from meetings),'teams',(select count(*) from teams),'work',(select count(*) from work_posts),'to_check',(select count(*) from task_submissions where status='submitted'),
        'emails_sent',(select count(*) from email_log where status='sent'),'emails_failed',(select count(*) from email_log where status='failed')) end,
    'activity',case when k.role='admin' then (select coalesce(json_agg(a),'[]') from (select msg,created_at from activity order by id desc limit 8) a) end); end $$;

-- ---------- 9. rights: the helper functions of the old builder are gone; the new public functions are called by the site ----------
notify pgrst, 'reload schema';

-- =====================================================================================================
-- OPTIONAL (not run): delete the OLD exam tables and every old exam result / answer sheet.  This cannot be undone.
-- Leave it as it is if you want to keep the old results.  To remove them, delete the two dashes in front of the line:
-- drop table if exists exam_allow, exam_attempts, exam_questions, exam_sections, exams cascade;
-- =====================================================================================================
