-- =====================================================================================================
-- 06_upgrade_v44.sql   Gaddam Venu portal v44   -> for an EXISTING database (v41 - v43).  Keeps ALL data.
-- Run ONLY THIS FILE, once (safe to run again).  You do NOT need to run 02_functions.sql again.
-- (A NEW install does not need this file: 01_tables.sql and 02_functions.sql already contain everything.)
--
-- v44 adds
--   1. TASKS: the admin posts a task with ONE Google Drive link (+ optional note, deadline, visible true / false) and can edit it
--   2. SUBMIT WORK tab (students post work by Drive link, the admin views it) for EVERY subject (before: projects only)
--   3. EXAM: the student's name comes from the login; only the Gmail is typed
-- =====================================================================================================
alter table tasks add column if not exists link text;

create or replace function task_post(t text, sid uuid, ti text, lk text, nt text, dl text, vis boolean) returns void language plpgsql security definer set search_path=public as $$
declare cd text; d timestamptz; v boolean; begin perform _admin(t);
  if length(trim(coalesce(ti,'')))<1 then raise exception 'Enter a title'; end if;
  if length(coalesce(nt,''))>2000 then raise exception 'The note is too long (2000 characters)'; end if;
  if btrim(coalesce(dl,''))<>'' then begin d:=btrim(dl)::timestamptz; exception when others then raise exception 'The deadline is not a valid date and time'; end; end if;
  v:=coalesce(vis,true);
  insert into tasks(subject_id,title,message,link,due_date,deadline,submit_mode,visible)
    values(sid,trim(ti),nullif(trim(coalesce(nt,'')),''),_drive(lk),(d at time zone 'Asia/Kolkata')::date,d,'link',v);
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Task posted in '||cd);
  if v then perform _notify_subject(sid,'task',cd||' · new task: '||trim(ti),
    case when d is not null then 'Deadline: '||to_char(d at time zone 'Asia/Kolkata','DD Mon YYYY, HH12:MI AM') end,'subject/'||cd||'/tasks'); end if; end $$;

create or replace function task_edit(t text, i uuid, ti text, lk text, nt text, dl text, vis boolean) returns void language plpgsql security definer set search_path=public as $$
declare d timestamptz; begin perform _admin(t);
  if length(trim(coalesce(ti,'')))<1 then raise exception 'Enter a title'; end if;
  if length(coalesce(nt,''))>2000 then raise exception 'The note is too long (2000 characters)'; end if;
  if btrim(coalesce(dl,''))<>'' then begin d:=btrim(dl)::timestamptz; exception when others then raise exception 'The deadline is not a valid date and time'; end; end if;
  update tasks set title=trim(ti), message=nullif(trim(coalesce(nt,'')),''), link=_drive(lk), due_date=(d at time zone 'Asia/Kolkata')::date, deadline=d, visible=coalesce(vis,visible) where id=i;
  if not found then raise exception 'Task not found'; end if; end $$;

create or replace function tasks_get(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; pj boolean; mt uuid; begin r:=_access(t,sid); k:=_s(t); pj:=_isproj(sid); mt:=_myteam(k.user_id,sid);
  if r<>'admin' and _hid(sid,'tasks') then return '[]'::json; end if;
  return (select coalesce(json_agg(json_build_object('id',x.id,'title',x.title,'message',x.message,'due_date',x.due_date,'deadline',x.deadline,'submit_mode',x.submit_mode,'link',x.link,'visible',x.visible,'max_marks',x.max_marks,'created_at',x.created_at,'project',pj,
    'total',case when r<>'student' then (case when pj then (select count(*) from teams tm where tm.subject_id=sid) else (select count(*) from enrollments e where e.subject_id=sid) end) end,
    'submitted',case when r<>'student' then (select count(*) from task_submissions s where s.task_id=x.id) end,
    'verified',case when r<>'student' then (select count(*) from task_submissions s where s.task_id=x.id and s.status='verified') end,
    'mine',case when r='student' then (select json_build_object('id',s.id,'file_name',s.file_name,'file_size',s.file_size,'has_link',(s.link is not null),'via_button',s.via_button,'status',s.status,'marks',s.marks,'remark',s.remark,
        'by',(select name from students where id=s.student_id),'submitted_at',s.submitted_at,'updated_at',s.updated_at,'verified_at',s.verified_at)
        from task_submissions s where s.task_id=x.id and ((pj and s.team_id=mt) or (not pj and s.team_id is null and s.student_id=k.user_id))) end
    ) order by x.created_at desc),'[]') from tasks x where x.subject_id=sid and (r='admin' or x.visible)); end $$;

create or replace function work_add(t text, sid uuid, kd text, ti text, lk text, nt text) returns void language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  if k.role<>'student' then raise exception 'Only a student can post work'; end if;
  if not exists(select 1 from enrollments where student_id=k.user_id and subject_id=sid) then raise exception 'Not allowed'; end if;
  if coalesce(kd,'') not in ('Code','Report','PPT','Other') then raise exception 'Choose what you are posting: Code, Report, PPT or Other'; end if;
  if length(coalesce(nt,''))>500 then raise exception 'The note is too long (500 characters)'; end if;
  insert into work_posts(subject_id,team_id,student_id,kind,title,link,note)
    values(sid,_myteam(k.user_id,sid),k.user_id,kd,coalesce(nullif(trim(coalesce(ti,'')),''),kd),_drive(lk),nullif(trim(coalesce(nt,'')),'')); end $$;

create or replace function exam_info(t text, x text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; e exams; begin k:=_s(t);
  if k.role<>'student' then raise exception 'Only students can take an exam. Log in with the student Gmail.'; end if;
  select * into e from exams where code=upper(btrim(coalesce(x,''))) and status in ('published','closed');
  if e.id is null then raise exception 'This exam was not found or is not published'; end if;
  if not exists(select 1 from enrollments where student_id=k.user_id and subject_id=e.subject_id) then raise exception 'This exam is not for your subject'; end if;
  return json_build_object('code',e.code,'title',e.title,'subject',(select code from subjects where id=e.subject_id),'instructions',e.instructions,'duration_min',e.duration_min,
    'starts_at',e.starts_at,'ends_at',e.ends_at,'max_violations',e.max_violations,'status',e.status,'now',now(),'shuffle',e.shuffle,'lock_sections',e.lock_sections,'min_submit',_exam_min_submit(e.id),
    'total_marks',_exam_total(e.id),'student_name',(select name from students where id=k.user_id),
    'sections',(select coalesce(json_agg(json_build_object('pos',s.pos,'name',s.name,'q_count',s.q_count,'marks',s.marks,'negative',s.negative,'time_min',s.time_min) order by s.pos),'[]') from exam_sections s where s.exam_id=e.id),
    'kinds',(select coalesce(json_agg(distinct q.kind),'[]') from exam_questions q where q.exam_id=e.id),
    'allowed',exists(select 1 from exam_allow w where w.exam_id=e.id and w.student_id=k.user_id) and not exists(select 1 from exam_attempts a where a.exam_id=e.id and a.student_id=k.user_id),
    'my',(select json_build_object('id',a.id,'status',a.status,'score',a.score,'total',a.total,'can',(a.status='in_progress' and now()<=_exam_deadline(a.id))) from exam_attempts a where a.exam_id=e.id and a.student_id=k.user_id)); end $$;

drop function if exists exam_start(text,text,text,text);
create or replace function exam_start(t text, x text, em text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; s students; e exams; a exam_attempts; dl timestamptz; al exam_allow; ms int; cp int; begin k:=_s(t);
  if k.role<>'student' then raise exception 'Only students can take an exam'; end if;
  select * into s from students where id=k.user_id;
  select * into e from exams where code=upper(btrim(coalesce(x,''))) and status='published';
  if e.id is null then raise exception 'This exam is not open'; end if;
  if not exists(select 1 from enrollments where student_id=s.id and subject_id=e.subject_id) then raise exception 'This exam is not for your subject'; end if;
  if lower(btrim(coalesce(em,'')))<>lower(s.email) then raise exception 'The Gmail you typed does not match your login'; end if;
  select * into a from exam_attempts where exam_id=e.id and student_id=s.id;
  if a.id is not null and a.status<>'in_progress' then raise exception 'You have already submitted this exam'; end if;
  if a.id is null then
    select * into al from exam_allow where exam_id=e.id and student_id=s.id;
    if al.exam_id is null then
      if e.starts_at is not null and now()<e.starts_at then raise exception 'The exam has not started yet. It opens on %', to_char(e.starts_at at time zone 'Asia/Kolkata','DD Mon YYYY HH24:MI'); end if;
      if e.ends_at is not null and now()>e.ends_at then raise exception 'The exam time is over'; end if;
    end if;
    if not exists(select 1 from exam_questions where exam_id=e.id) then raise exception 'This exam has no questions yet'; end if;
    insert into exam_attempts(exam_id,student_id,extra_min,bypass) values(e.id,s.id,coalesce(al.extra_min,0),al.exam_id is not null) returning * into a;
    perform _exam_init(a.id);
  end if;
  perform _exam_sync(a.id);
  select * into a from exam_attempts where id=a.id;
  if a.status<>'in_progress' then return json_build_object('over',true,'status',a.status,'attempt_id',a.id); end if;
  dl:=_exam_deadline(a.id);
  if now()>dl then perform _exam_finish(a.id,'auto_time'); return json_build_object('over',true,'status','auto_time','attempt_id',a.id); end if;
  cp:=case when e.lock_sections then (a.sec->>'cur')::int end; ms:=_exam_min_submit(e.id);
  return json_build_object('attempt_id',a.id,'remaining',extract(epoch from (dl-now()))::int,'violations',a.violations,'answers',a.answers,'flags',a.flags,'qtime',a.qtime,'vlog',a.vlog,'name',s.name,'email',s.email,
    'submit_in',case when a.reopens>0 or a.resume_until is not null then 0 else greatest(0,extract(epoch from (a.started_at+(ms||' minutes')::interval-now()))::int) end,
    'min_submit',ms,'total_q',(select count(*) from exam_questions where exam_id=e.id),'sec',_exam_secinfo(a.id),
    'exam',json_build_object('code',e.code,'title',e.title,'subject',(select code from subjects where id=e.subject_id),'duration_min',e.duration_min,'max_violations',e.max_violations,'lock',e.lock_sections,'shuffle',e.shuffle),
    'sections',(select coalesce(json_agg(json_build_object('pos',x2.pos,'name',x2.name,'q_count',x2.q_count,'marks',x2.marks,'negative',x2.negative,'time_min',x2.time_min) order by x2.pos),'[]') from exam_sections x2 where x2.exam_id=e.id),
    'questions',_exam_qs(a.id,cp)); end $$;

grant execute on function task_post(text,uuid,text,text,text,text,boolean) to anon, authenticated;
grant execute on function task_edit(text,uuid,text,text,text,text,boolean) to anon, authenticated;
grant execute on function exam_start(text,text,text) to anon, authenticated;

notify pgrst, 'reload schema';
