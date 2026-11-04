-- v47: Syllabus can have "Other" (the admin types the heading + name + Drive link).  Safe to run again; keeps all data.
-- Run this file ONCE in the Supabase SQL editor, after 08_upgrade_v46.sql.

alter table materials drop constraint if exists materials_category_check;
alter table materials add constraint materials_category_check check (category in ('Theory Syllabus','Lab Syllabus','Other Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks','Other'));

-- 'Other Syllabus' is shown in the Syllabus tab
create or replace function _mat_tab(cat text) returns text language sql immutable as $$
  select case when cat in ('Theory Syllabus','Lab Syllabus','Other Syllabus') then 'syllabus'
              when cat in ('Theory Lesson Plan','Lab Lesson Plan') then 'lessonplan'
              when cat like 'Unit %' or cat='Other' then 'materials'
              when cat='Lab Marks' then 'labsheet' else 'marks' end $$;

create or replace function material_add(t text, sid uuid, rw jsonb) returns int language plpgsql security definer set search_path=public as $$
declare x jsonb; n int:=0; ti text; cd text; kd text; lb text; begin perform _admin(t);
  select kind into kd from subjects where id=sid; if kd is null then raise exception 'Subject not found'; end if;
  for x in select * from jsonb_array_elements(rw) loop
    if x->>'category' in ('Lab Marks','Lab Syllabus','Lab Lesson Plan') and kd<>'lab' then raise exception 'Lab Syllabus, Lab Lesson Plan and Lab Sheet are only for Theory + Lab subjects'; end if;
    if coalesce(x->>'category','') <> all(array['Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks','Other','Other Syllabus']) then raise exception 'Choose a valid category'; end if;
    if coalesce(x->>'link','') !~* '^https?://\S+$' then raise exception 'Every row needs a valid link (starting with https://)'; end if;
    lb:=null;
    if x->>'category' in ('Other','Other Syllabus') then
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

-- subject list + dashboard: do not count Syllabus "Other" as study material
create or replace function subjects_list(t text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  return (select coalesce(json_agg(x order by x.year desc, x.code),'[]') from (
    select s.id, s.code, s.name, s.year, s.full_name, s.kind,
      (select count(*) from enrollments e where e.subject_id=s.id) as students,
      (select count(*) from materials m where m.subject_id=s.id and m.category not in ('Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Other Syllabus')) as materials,
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
        'materials',(select count(*) from materials where category not in ('Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Other Syllabus')),'videos',(select count(*) from videos),'notices',(select count(*) from notices),'labs',(select count(*) from labs),
        'tasks',(select count(*) from tasks),'exams',(select count(*) from exam_links),'meetings',(select count(*) from meetings),'teams',(select count(*) from teams),'work',(select count(*) from work_posts),'to_check',(select count(*) from task_submissions where status='submitted'),
        'emails_sent',(select count(*) from email_log where status='sent'),'emails_failed',(select count(*) from email_log where status='failed')) end,
    'activity',case when k.role='admin' then (select coalesce(json_agg(a),'[]') from (select msg,created_at from activity order by id desc limit 8) a) end); end $$;
