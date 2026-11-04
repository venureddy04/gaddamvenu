-- =====================================================================================================
-- 07_upgrade_v45.sql   Gaddam Venu portal v45   -> for an EXISTING database (v41 - v44).  Keeps ALL data.
-- Run ONLY THIS FILE, once (safe to run again).  You do NOT need to run 02_functions.sql again.
-- (A NEW install does not need this file: 01_tables.sql and 02_functions.sql already contain everything.)
--
-- v45 adds
--   1. EXAM TYPES: Theory (MCQ only) and Lab (write-up, marked by the admin)
--   2. every question compulsory (NPTEL style) - a manual Submit is refused while a question is empty
--   3. lighter exam_save + longer grace for the final submit (100+ students writing at the same time)
-- =====================================================================================================
alter table exams add column if not exists category text not null default 'theory';
alter table exams drop constraint if exists exams_category_check;
alter table exams add constraint exams_category_check check (category in ('theory','lab'));
alter table exams add column if not exists mandatory boolean not null default false;   -- old exams stay as they were
alter table exams alter column mandatory set default true;                              -- new exams: all questions compulsory
alter table exam_questions drop constraint if exists exam_questions_kind_check;
alter table exam_questions add constraint exam_questions_kind_check check (kind in ('mcq','msq','num','fill','lab'));
alter table exam_attempts add column if not exists saved_at timestamptz;                       -- last time the answers reached the server (the admin sees who has lost the connection)
alter table exam_attempts add column if not exists lab jsonb not null default '{}'::jsonb;   -- lab marks {question id: {m: marks, r: remark}}

create or replace function _exam_q_put(eid uuid, qid uuid, x jsonb) returns uuid language plpgsql security definer set search_path=public as $$
declare sp text; s exam_sections; kd text; qt text; opts jsonb; ans text; tol numeric:=0; ex text; n int; nid uuid; np int; mk numeric; ng numeric; pt boolean:=false; im text; ls text[]; begin
  sp:=coalesce(x->>'section',''); if sp !~ '^[0-9]{1,2}$' then raise exception 'The section number is missing'; end if;
  select * into s from exam_sections where exam_id=eid and pos=sp::int; if s.id is null then raise exception 'Section % does not exist in this exam', sp; end if;
  kd:=lower(coalesce(x->>'kind','')); if kd not in ('mcq','msq','num','fill','lab') then raise exception 'The type must be MCQ or Lab'; end if;
  if (select category from exams where id=eid)='lab' then if kd<>'lab' then raise exception 'A lab exam can have lab questions only'; end if; elsif kd='lab' then raise exception 'Lab questions belong to a lab exam only'; end if;
  qt:=btrim(coalesce(x->>'question','')); if qt='' then raise exception 'A question is empty'; end if; if length(qt)>3000 then raise exception 'A question is too long (3000 characters)'; end if;
  ans:=btrim(coalesce(x->>'answer','')); if kd='lab' and ans='' then ans:='-'; end if; if ans='' then raise exception 'The answer is missing for: %', left(qt,40); end if;
  ex:=nullif(btrim(coalesce(x->>'explanation','')),''); if length(coalesce(ex,''))>1500 then raise exception 'An explanation is too long'; end if;
  im:=nullif(btrim(coalesce(x->>'image','')),'');
  if im is not null and (im !~* '^https://[^[:space:]]+$' or length(im)>500) then raise exception 'The image link must start with https:// (up to 500 characters): %', left(qt,40); end if;
  if nullif(btrim(coalesce(x->>'marks','')),'') is not null then
    if btrim(x->>'marks') !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' or btrim(x->>'marks')::numeric<=0 then raise exception 'Marks of a question must be a number above 0: %', left(qt,40); end if; mk:=btrim(x->>'marks')::numeric; end if;
  if nullif(btrim(coalesce(x->>'negative','')),'') is not null then
    if btrim(x->>'negative') !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' then raise exception 'Negative marks of a question must be 0 or more: %', left(qt,40); end if; ng:=btrim(x->>'negative')::numeric; end if;
  pt:=lower(btrim(coalesce(x->>'partial',''))) in ('y','yes','true','t','1');
  if kd in ('mcq','msq') then
    opts:=x->'options'; if jsonb_typeof(opts)<>'array' or jsonb_array_length(opts) not between 2 and 6 then raise exception 'An MCQ / MSQ needs 2 to 6 options: %', left(qt,40); end if;
    if exists(select 1 from jsonb_array_elements_text(opts) o where btrim(o)='' or length(o)>500) then raise exception 'An option is empty or too long: %', left(qt,40); end if;
    n:=jsonb_array_length(opts);
    if kd='mcq' then
      ans:=upper(ans);
      if ans !~ '^[A-F]$' or ascii(ans)-64>n then raise exception 'The correct answer must be the letter of an option (A, B, C, D): %', left(qt,40); end if;
    else
      ls:=(select array_agg(distinct c order by c) from regexp_split_to_table(upper(regexp_replace(ans,'[^A-Za-z]','','g')),'') c where c<>'');
      if ls is null or exists(select 1 from unnest(ls) c where c !~ '^[A-F]$' or ascii(c)-64>n) then raise exception 'The correct answers of an MSQ must be letters of options, like A,C: %', left(qt,40); end if;
      ans:=array_to_string(ls,','); end if;
  elsif kd='num' then
    opts:=null; if ans !~ '^[-+]?[0-9]*\.?[0-9]+$' or length(ans)>20 then raise exception 'The numerical answer must be a number: %', left(qt,40); end if;
    if btrim(coalesce(x->>'tolerance',''))<>'' then
      if btrim(x->>'tolerance') !~ '^[0-9]{1,6}(\.[0-9]{1,6})?$' then raise exception 'Tolerance must be a number: %', left(qt,40); end if; tol:=btrim(x->>'tolerance')::numeric; end if;
  else opts:=null; if kd='lab' then if length(ans)>2000 then raise exception 'The key points of a lab question are too long (2000 characters)'; end if; elsif length(ans)>300 then raise exception 'A fill-in-the-blank answer is too long'; end if; end if;
  if kd<>'msq' then pt:=false; end if;
  if qid is null then
    select coalesce(max(pos),0)+1 into np from exam_questions where section_id=s.id;
    insert into exam_questions(exam_id,section_id,pos,kind,question,image_url,options,answer,tolerance,marks,negative,partial,explanation) values(eid,s.id,np,kd,qt,im,opts,ans,tol,mk,ng,pt,ex) returning id into nid;
  else
    select coalesce(max(pos),0)+1 into np from exam_questions where section_id=s.id and id<>qid;
    update exam_questions set section_id=s.id, pos=case when section_id=s.id then pos else np end, kind=kd, question=qt, image_url=im, options=opts, answer=ans, tolerance=tol, marks=mk, negative=ng, partial=pt, explanation=ex
      where id=qid and exam_id=eid returning id into nid;
    if nid is null then raise exception 'Question not found'; end if;
  end if;
  return nid; end $$;

create or replace function exam_get(t text, eid uuid) returns json language plpgsql security definer set search_path=public as $$
declare e exams; begin perform _admin(t);
  select * into e from exams where id=eid; if e.id is null then raise exception 'Exam not found'; end if;
  return json_build_object('id',e.id,'code',e.code,'title',e.title,'instructions',e.instructions,'duration_min',e.duration_min,'starts_at',e.starts_at,'ends_at',e.ends_at,
    'max_violations',e.max_violations,'shuffle',e.shuffle,'lock_sections',e.lock_sections,'category',e.category,'mandatory',e.mandatory,'min_submit_min',e.min_submit_min,'min_submit',_exam_min_submit(e.id),
    'status',e.status,'published_at',e.published_at,'subject',(select code from subjects where id=e.subject_id),'total_marks',_exam_total(e.id),
    'attempts',(select count(*) from exam_attempts where exam_id=e.id),
    'sections',(select coalesce(json_agg(json_build_object('pos',s.pos,'name',s.name,'q_count',s.q_count,'marks',s.marks,'negative',s.negative,'time_min',s.time_min) order by s.pos),'[]') from exam_sections s where s.exam_id=e.id),
    'questions',(select coalesce(json_agg(json_build_object('id',q.id,'section',s.pos,'kind',q.kind,'question',q.question,'image',q.image_url,'options',q.options,'answer',q.answer,'tolerance',q.tolerance,
        'marks',q.marks,'negative',q.negative,'partial',q.partial,'explanation',q.explanation) order by s.pos,q.pos),'[]')
       from exam_questions q join exam_sections s on s.id=q.section_id where q.exam_id=e.id)); end $$;

create or replace function exams_list(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; begin r:=_access(t,sid); k:=_s(t);
  return (select coalesce(json_agg(json_build_object('id',e.id,'code',e.code,'title',e.title,'duration_min',e.duration_min,'starts_at',e.starts_at,'ends_at',e.ends_at,'status',e.status,'max_violations',e.max_violations,'created_at',e.created_at,
      'shuffle',e.shuffle,'lock_sections',e.lock_sections,'category',e.category,'mandatory',e.mandatory,
      'sections',(select count(*) from exam_sections where exam_id=e.id),'q_total',(select coalesce(sum(q_count),0) from exam_sections where exam_id=e.id),
      'q_loaded',(select count(*) from exam_questions where exam_id=e.id),'total_marks',_exam_total(e.id),
      'attempts',case when r<>'student' then (select count(*) from exam_attempts a where a.exam_id=e.id and a.status<>'in_progress') end,
      'mine',case when r='student' then (select json_build_object('id',a.id,'status',a.status,'score',a.score,'total',a.total,'can',(a.status='in_progress' and now()<=_exam_deadline(a.id))) from exam_attempts a where a.exam_id=e.id and a.student_id=k.user_id) end,
      'allowed',case when r='student' then exists(select 1 from exam_allow w where w.exam_id=e.id and w.student_id=k.user_id) and not exists(select 1 from exam_attempts a where a.exam_id=e.id and a.student_id=k.user_id) end
    ) order by e.created_at desc),'[]') from exams e where e.subject_id=sid and (r='admin' or (e.status<>'draft' and not _hid(sid,'exams')))); end $$;

create or replace function exam_history(t text) returns json language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  return (select coalesce(json_agg(json_build_object('id',e.id,'code',e.code,'title',e.title,'subject',s.code,'category',e.category,'status',e.status,'starts_at',e.starts_at,'ends_at',e.ends_at,'created_at',e.created_at,'duration_min',e.duration_min,
      'q_total',(select coalesce(sum(q_count),0) from exam_sections where exam_id=e.id),'total_marks',_exam_total(e.id),
      'students',(select count(*) from enrollments where subject_id=e.subject_id),
      'submitted',(select count(*) from exam_attempts a where a.exam_id=e.id and a.status<>'in_progress'),
      'avg',(select round(avg(a.score),2) from exam_attempts a where a.exam_id=e.id and a.status<>'in_progress'),
      'max',(select max(a.score) from exam_attempts a where a.exam_id=e.id and a.status<>'in_progress')) order by e.created_at desc),'[]')
    from exams e join subjects s on s.id=e.subject_id); end $$;

create or replace function exam_results(t text, eid uuid) returns json language plpgsql security definer set search_path=public as $$
declare e exams; begin perform _admin(t);
  select * into e from exams where id=eid; if e.id is null then raise exception 'Exam not found'; end if;
  return json_build_object('id',e.id,'code',e.code,'title',e.title,'subject',(select code from subjects where id=e.subject_id),'total_marks',_exam_total(e.id),'duration_min',e.duration_min,'lock_sections',e.lock_sections,'category',e.category,'q_total',(select count(*) from exam_questions where exam_id=e.id),
    'rows',(select coalesce(json_agg(json_build_object('attempt_id',a.id,'student_id',st.id,'name',st.name,'email',st.email,'regno',st.regno,'status',a.status,'saved_at',a.saved_at,'answered',(select count(*) from jsonb_object_keys(a.answers)),'pending',(a.status<>'in_progress' and a.score is null),'score',a.score,'total',a.total,'correct',a.correct,'wrong',a.wrong,'partial',a.partial,'skipped',a.skipped,
        'violations',a.violations,'started_at',a.started_at,'submitted_at',a.submitted_at,'reopens',a.reopens,'extra',(a.extra_min>0 or a.resume_until is not null or a.bypass),
        'seconds',case when a.submitted_at is not null then extract(epoch from (a.submitted_at-a.started_at))::int end) order by a.score desc nulls last, st.name),'[]')
      from exam_attempts a join students st on st.id=a.student_id where a.exam_id=e.id),
    'absent',(select coalesce(json_agg(json_build_object('student_id',st.id,'name',st.name,'email',st.email,'regno',st.regno,
        'allowed',(select w.extra_min from exam_allow w where w.exam_id=e.id and w.student_id=st.id)) order by st.name),'[]')
      from enrollments n join students st on st.id=n.student_id where n.subject_id=e.subject_id and not exists(select 1 from exam_attempts a where a.exam_id=e.id and a.student_id=st.id))); end $$;

create or replace function exam_my_results(t text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  if k.role<>'student' then raise exception 'Only for students'; end if;
  return (select coalesce(json_agg(json_build_object('attempt_id',a.id,'code',e.code,'title',e.title,'subject',s.code,'category',e.category,'pending',(a.score is null),'status',a.status,'score',a.score,'total',a.total,'correct',a.correct,'wrong',a.wrong,'partial',a.partial,'skipped',a.skipped,'submitted_at',a.submitted_at,
      'rank',(select count(*)+1 from exam_attempts b where b.exam_id=a.exam_id and b.status<>'in_progress' and b.score>a.score),'of',(select count(*) from exam_attempts b where b.exam_id=a.exam_id and b.status<>'in_progress')) order by a.submitted_at desc nulls last),'[]')
    from exam_attempts a join exams e on e.id=a.exam_id join subjects s on s.id=e.subject_id where a.student_id=k.user_id and a.status<>'in_progress'); end $$;

create or replace function exam_info(t text, x text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; e exams; begin k:=_s(t);
  if k.role<>'student' then raise exception 'Only students can take an exam. Log in with the student Gmail.'; end if;
  select * into e from exams where code=upper(btrim(coalesce(x,''))) and status in ('published','closed');
  if e.id is null then raise exception 'This exam was not found or is not published'; end if;
  if not exists(select 1 from enrollments where student_id=k.user_id and subject_id=e.subject_id) then raise exception 'This exam is not for your subject'; end if;
  return json_build_object('code',e.code,'title',e.title,'subject',(select code from subjects where id=e.subject_id),'instructions',e.instructions,'duration_min',e.duration_min,
    'starts_at',e.starts_at,'ends_at',e.ends_at,'max_violations',e.max_violations,'status',e.status,'now',now(),'shuffle',e.shuffle,'lock_sections',e.lock_sections,'category',e.category,'mandatory',e.mandatory,'lobby_min',5,'min_submit',_exam_min_submit(e.id),
    'total_marks',_exam_total(e.id),'student_name',(select name from students where id=k.user_id),
    'sections',(select coalesce(json_agg(json_build_object('pos',s.pos,'name',s.name,'q_count',s.q_count,'marks',s.marks,'negative',s.negative,'time_min',s.time_min) order by s.pos),'[]') from exam_sections s where s.exam_id=e.id),
    'kinds',(select coalesce(json_agg(distinct q.kind),'[]') from exam_questions q where q.exam_id=e.id),
    'allowed',exists(select 1 from exam_allow w where w.exam_id=e.id and w.student_id=k.user_id) and not exists(select 1 from exam_attempts a where a.exam_id=e.id and a.student_id=k.user_id),
    'my',(select json_build_object('id',a.id,'status',a.status,'score',a.score,'total',a.total,'can',(a.status='in_progress' and now()<=_exam_deadline(a.id))) from exam_attempts a where a.exam_id=e.id and a.student_id=k.user_id)); end $$;

create or replace function exam_start(t text, x text, em text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; s students; e exams; a exam_attempts; dl timestamptz; al exam_allow; ms int; cp int; begin k:=_s(t);
  if k.role<>'student' then raise exception 'Only students can take an exam'; end if;
  select * into s from students where id=k.user_id;
  select * into e from exams where code=upper(btrim(coalesce(x,''))) and status='published';
  if e.id is null then raise exception 'This exam is not open'; end if;
  if not exists(select 1 from enrollments where student_id=s.id and subject_id=e.subject_id) then raise exception 'This exam is not for your subject'; end if;
  if lower(btrim(coalesce(em,'')))<>lower(s.email) then raise exception 'The Gmail you typed does not match your login'; end if;
  perform pg_advisory_xact_lock(hashtextextended(e.id::text||s.id::text,2));      -- the same student pressing Start twice (double click / automatic retry) is served one after the other
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
  return json_build_object('now',now(),'attempt_id',a.id,'remaining',extract(epoch from (dl-now()))::int,'violations',a.violations,'answers',a.answers,'flags',a.flags,'qtime',a.qtime,'vlog',a.vlog,'name',s.name,'email',s.email,
    'submit_in',case when a.reopens>0 or a.resume_until is not null then 0 else greatest(0,extract(epoch from (a.started_at+(ms||' minutes')::interval-now()))::int) end,
    'min_submit',ms,'total_q',(select count(*) from exam_questions where exam_id=e.id),'sec',_exam_secinfo(a.id),
    'exam',json_build_object('category',e.category,'mandatory',e.mandatory,'code',e.code,'title',e.title,'subject',(select code from subjects where id=e.subject_id),'duration_min',e.duration_min,'max_violations',e.max_violations,'lock',e.lock_sections,'shuffle',e.shuffle),
    'sections',(select coalesce(json_agg(json_build_object('pos',x2.pos,'name',x2.name,'q_count',x2.q_count,'marks',x2.marks,'negative',x2.negative,'time_min',x2.time_min) order by x2.pos),'[]') from exam_sections x2 where x2.exam_id=e.id),
    'questions',_exam_qs(a.id,cp)); end $$;

create or replace function exam_review(t text, aid uuid) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; a exam_attempts; e exams; begin k:=_s(t);
  select * into a from exam_attempts where id=aid; if a.id is null then raise exception 'Result not found'; end if;
  if k.role='student' then if a.student_id<>k.user_id or a.status='in_progress' then raise exception 'Not allowed'; end if;
  elsif k.role<>'admin' then raise exception 'Not allowed'; end if;
  select * into e from exams where id=a.exam_id;
  return json_build_object('exam',json_build_object('category',e.category,'code',e.code,'title',e.title,'subject',(select code from subjects where id=e.subject_id),'duration_min',e.duration_min),
    'student',(select json_build_object('name',name,'email',email,'regno',regno) from students where id=a.student_id),
    'attempt',json_build_object('id',a.id,'status',a.status,'pending',(a.score is null),'score',a.score,'total',a.total,'correct',a.correct,'wrong',a.wrong,'partial',a.partial,'skipped',a.skipped,'violations',a.violations,'started_at',a.started_at,'submitted_at',a.submitted_at,
        'reopens',a.reopens,'vlog',case when k.role='admin' then a.vlog end,'grants',case when k.role='admin' then a.grants end),
    'questions',(select coalesce(json_agg(json_build_object('no',z.n,'section',z.sname,'kind',z.kind,'question',z.question,'image',z.image_url,'options',z.d_options,'your',a.answers->>(z.id::text),
        'qid',z.id,'answer',case when z.kind='lab' then (case when k.role='admin' then z.answer end) when z.kind in ('mcq','msq') then _disp_ans(z.answer,z.perm) else z.answer end,'result',case when z.kind='lab' then (case when coalesce(btrim(a.answers->>(z.id::text)),'')='' then 'skip' when a.lab->(z.id::text) is null then 'pending' when (a.lab->(z.id::text)->>'m')::numeric>=z.mk then 'correct' when (a.lab->(z.id::text)->>'m')::numeric>0 then 'partial' else 'wrong' end) else sc.res end,'marks',z.mk,'negative',z.ng,'explanation',case when z.kind='lab' and a.score is null and k.role<>'admin' then null else z.explanation end,'got',case when z.kind='lab' then coalesce((a.lab->(z.id::text)->>'m')::numeric,0) else sc.pts end,'remark',a.lab->(z.id::text)->>'r',
        'seconds',case when coalesce(a.qtime->>(z.id::text),'') ~ '^[0-9]{1,6}(\.[0-9]+)?$' then round((a.qtime->>(z.id::text))::numeric)::int end) order by z.n),'[]')
      from _exam_paper(a.id) z
      cross join lateral _q_score(z.kind,z.answer,z.tolerance,case when z.kind in ('mcq','msq') then _unperm(a.answers->>(z.id::text),z.perm) else a.answers->>(z.id::text) end,z.mk,z.ng,z.pt) sc)); end $$;

create or replace function _exam_grade(aid uuid) returns void language plpgsql security definer set search_path=public as $$
declare a exam_attempts; c int:=0; w int:=0; s int:=0; p int:=0; pend int:=0; sc numeric:=0; tt numeric:=0; r record; g text; v record; m numeric; begin
  select * into a from exam_attempts where id=aid; if a.id is null then return; end if;
  for r in select * from _exam_paper(aid) loop
    tt:=tt+r.mk; g:=a.answers->>(r.id::text);
    if r.kind='lab' then
      -- lab write-up: marked by the teacher.  Not answered = 0.  Answered but not marked yet = pending (the total stays empty until all are marked)
      if coalesce(btrim(g),'')='' then s:=s+1;
      elsif a.lab->(r.id::text) is not null and coalesce(a.lab->(r.id::text)->>'m','')<>'' then
        m:=least(greatest((a.lab->(r.id::text)->>'m')::numeric,0),r.mk); sc:=sc+m;
        if m>=r.mk then c:=c+1; elsif m>0 then p:=p+1; else w:=w+1; end if;
      else pend:=pend+1; end if;
      continue; end if;
    if r.kind in ('mcq','msq') then g:=_unperm(g,r.perm); end if;
    select * into v from _q_score(r.kind,r.answer,r.tolerance,g,r.mk,r.ng,r.pt);
    if v.res='correct' then c:=c+1; elsif v.res='partial' then p:=p+1; elsif v.res='wrong' then w:=w+1; else s:=s+1; end if;
    sc:=sc+v.pts;
  end loop;
  update exam_attempts set score=case when pend>0 then null else sc end, total=tt, correct=c, wrong=w, skipped=s, partial=p where id=aid; end $$;

create or replace function exam_save(t text, aid uuid, ans jsonb, fl jsonb, vi int, vl jsonb, qt jsonb) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; a exam_attempts; lk boolean; dl timestamptz; begin k:=_s(t);
  perform pg_advisory_xact_lock(hashtextextended(aid::text,1));      -- one request per attempt at a time (a late save can never overwrite a submitted exam)
  select * into a from exam_attempts where id=aid and student_id=k.user_id; if a.id is null then raise exception 'Not allowed'; end if;
  if a.status<>'in_progress' then return json_build_object('over',true); end if;
  select lock_sections into lk from exams where id=a.exam_id;
  if lk then perform _exam_sync(aid); select * into a from exam_attempts where id=aid; if a.status<>'in_progress' then return json_build_object('over',true); end if; end if;
  dl:=_exam_deadline(aid);
  if now()>dl+interval '30 seconds' then perform _exam_finish(aid,'auto_time'); return json_build_object('over',true); end if;
  if length(coalesce(ans,'{}'::jsonb)::text)>500000 or length(coalesce(fl,'{}'::jsonb)::text)>100000 or length(coalesce(qt,'{}'::jsonb)::text)>60000 or length(coalesce(vl,'[]'::jsonb)::text)>30000 then raise exception 'Too much data'; end if;
  update exam_attempts set saved_at=now(), answers=case when lk then _exam_merge(aid,ans,a.answers) when jsonb_typeof(ans)='object' then ans else a.answers end, flags=case when jsonb_typeof(fl)='object' then fl else '{}'::jsonb end, violations=greatest(violations,least(coalesce(vi,0),100)),
    qtime=_merge_max(a.qtime,qt), vlog=_vlog_merge(a.vlog,vl) where id=aid and status='in_progress';
  return json_build_object('over',false,'remaining',greatest(0,extract(epoch from (dl-now()))::int),'sec',case when lk then _exam_secinfo(aid) else json_build_object('lock',false) end); end $$;

create or replace function exam_submit(t text, aid uuid, ans jsonb, fl jsonb, vi int, why text, vl jsonb, qt jsonb) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; a exam_attempts; e exams; st text; ms int; left_s int; mg jsonb; dl timestamptz; begin k:=_s(t);
  perform pg_advisory_xact_lock(hashtextextended(aid::text,1));      -- a double / repeated Submit waits for the first one and then just returns the result
  select * into a from exam_attempts where id=aid and student_id=k.user_id; if a.id is null then raise exception 'Not allowed'; end if;
  if a.status='in_progress' then
    select * into e from exams where id=a.exam_id;
    if e.lock_sections then perform _exam_sync(aid); select * into a from exam_attempts where id=aid; end if;
  end if;
  if a.status='in_progress' then
    ms:=_exam_min_submit(a.exam_id); dl:=_exam_deadline(aid);
    if coalesce(why,'manual') not in ('time','violations') and a.reopens=0 and a.resume_until is null and now()<a.started_at+(ms||' minutes')::interval-interval '5 seconds' then
      left_s:=ceil(extract(epoch from (a.started_at+(ms||' minutes')::interval-now())))::int;
      raise exception 'You can submit only after % minutes from the start. Please wait % min % sec.', ms, left_s/60, left_s%60; end if;
    if length(coalesce(ans,'{}'::jsonb)::text)>500000 then raise exception 'Too much data'; end if;
    mg:=case when now()<=dl+interval '5 minutes' then _exam_merge(aid,ans,a.answers) else a.answers end;
    -- every question compulsory: a manual submit is refused while a question is empty (time up / warnings always submit)
    if e.mandatory and coalesce(why,'manual') not in ('time','violations') and exists(select 1 from exam_questions q where q.exam_id=a.exam_id and coalesce(btrim(mg->>(q.id::text)),'')='') then
      raise exception 'All questions are compulsory. Answer every question before you submit.'; end if;
    if now()<=dl+interval '5 minutes' then
      update exam_attempts set answers=mg, flags=case when jsonb_typeof(fl)='object' then fl else flags end, qtime=_merge_max(a.qtime,qt), vlog=_vlog_merge(a.vlog,vl) where id=aid; end if;
    update exam_attempts set violations=greatest(violations,least(coalesce(vi,0),100)) where id=aid;
    st:=case when now()>dl+interval '5 minutes' or why='time' then 'auto_time' when why='violations' then 'auto_violations' else 'submitted' end;
    perform _exam_finish(aid,st);
    insert into activity(msg) values('Exam submitted: '||(select name from students where id=k.user_id)||' · '||(select code from exams where id=a.exam_id));
    select * into a from exam_attempts where id=aid;
    insert into notifications(role,user_id,subject_id,kind,title,body,link)
      values('student',k.user_id,e.subject_id,'exam_result',(select code from subjects where id=e.subject_id)||' · result: '||e.title,
        case when a.score is null then 'Submitted. Your teacher will check your write-up and give the marks.' else 'Marks '||trim(trailing '.' from trim(trailing '0' from a.score::text))||' / '||trim(trailing '.' from trim(trailing '0' from a.total::text)) end,'exams');
  end if;
  select * into a from exam_attempts where id=aid;
  return json_build_object('attempt_id',a.id,'status',a.status,'pending',(a.score is null),'score',a.score,'total',a.total,'correct',a.correct,'wrong',a.wrong,'partial',a.partial,'skipped',a.skipped); end $$;

create or replace function exam_new(t text, sid uuid, cat text, ti text, ins text, dur int, st text, en text, mv int, nq int, mk numeric, ng numeric, mand boolean, shuf boolean) returns json language plpgsql security definer set search_path=public as $$
declare eid uuid; cd text; s1 timestamptz; e1 timestamptz; begin perform _admin(t);
  if coalesce(cat,'') not in ('theory','lab') then raise exception 'Choose the exam type: Theory or Lab'; end if;
  if not exists(select 1 from subjects where id=sid) then raise exception 'Subject not found'; end if;
  if length(trim(coalesce(ti,'')))<2 then raise exception 'Enter the exam title'; end if;
  if length(coalesce(ins,''))>5000 then raise exception 'The instructions are too long'; end if;
  mv:=coalesce(mv,3); if mv not between 1 and 20 then raise exception 'Allowed warnings must be 1 to 20'; end if;
  if coalesce(nq,0) not between 1 and 200 then raise exception 'Number of questions: 1 to 200'; end if;
  if coalesce(mk,0)<=0 or mk>999 then raise exception 'Marks per question must be more than 0'; end if;
  ng:=case when cat='lab' then 0 else coalesce(ng,0) end; if ng<0 or ng>999 then raise exception 'Negative marks must be 0 or more'; end if;
  s1:=nullif(btrim(coalesce(st,'')),'')::timestamptz; e1:=nullif(btrim(coalesce(en,'')),'')::timestamptz;
  if s1 is null or e1 is null then raise exception 'Set the exam date: when it starts and when the exam room closes'; end if;
  if e1<=s1 then raise exception 'The end time must be after the start time'; end if;
  if coalesce(dur,0) not between 1 and 600 then raise exception 'Duration must be 1 to 600 minutes'; end if;
  if e1-s1 < (dur||' minutes')::interval then raise exception 'The time between the start and "room closes at" must be at least the duration (% minutes)', dur; end if;
  cd:=_exam_code();
  insert into exams(code,subject_id,category,title,instructions,duration_min,starts_at,ends_at,max_violations,shuffle,lock_sections,min_submit_min,mandatory)
    values(cd,sid,cat,trim(ti),nullif(trim(coalesce(ins,'')),''),dur,s1,e1,mv,coalesce(shuf,true),false,null,coalesce(mand,true)) returning id into eid;
  insert into exam_sections(exam_id,pos,name,q_count,marks,negative) values(eid,1,case when cat='lab' then 'Lab write-up' else 'Theory (MCQ)' end,nq,mk,ng);
  insert into activity(msg) values('Exam '||cd||' ('||cat||') created in '||(select code from subjects where id=sid));
  return json_build_object('id',eid,'code',cd); end $$;

create or replace function exam_settings(t text, eid uuid, ti text, ins text, dur int, st text, en text, mv int, nq int, mk numeric, ng numeric, mand boolean, shuf boolean) returns void language plpgsql security definer set search_path=public as $$
declare e exams; s exam_sections; s1 timestamptz; e1 timestamptz; att boolean; begin perform _admin(t);
  select * into e from exams where id=eid; if e.id is null then raise exception 'Exam not found'; end if;
  if (select count(*) from exam_sections where exam_id=eid)<>1 then raise exception 'This older exam has several sections. Change it in the old settings form.'; end if;
  select * into s from exam_sections where exam_id=eid;
  att:=exists(select 1 from exam_attempts where exam_id=eid);
  if length(trim(coalesce(ti,'')))<2 then raise exception 'Enter the exam title'; end if;
  mv:=coalesce(mv,3); if mv not between 1 and 20 then raise exception 'Allowed warnings must be 1 to 20'; end if;
  if coalesce(nq,0) not between 1 and 200 then raise exception 'Number of questions: 1 to 200'; end if;
  if coalesce(mk,0)<=0 or mk>999 then raise exception 'Marks per question must be more than 0'; end if;
  ng:=case when e.category='lab' then 0 else coalesce(ng,0) end; if ng<0 or ng>999 then raise exception 'Negative marks must be 0 or more'; end if;
  s1:=nullif(btrim(coalesce(st,'')),'')::timestamptz; e1:=nullif(btrim(coalesce(en,'')),'')::timestamptz;
  if s1 is null or e1 is null then raise exception 'Set the exam date: when it starts and when the exam room closes'; end if;
  if e1<=s1 then raise exception 'The end time must be after the start time'; end if;
  if coalesce(dur,0) not between 1 and 600 then raise exception 'Duration must be 1 to 600 minutes'; end if;
  if e1-s1 < (dur||' minutes')::interval then raise exception 'The time between the start and "room closes at" must be at least the duration (% minutes)', dur; end if;
  if att and (nq<>s.q_count or coalesce(shuf,true)<>e.shuffle) then raise exception 'Students already attempted this exam. The number of questions and shuffle cannot change now.'; end if;
  update exams set title=trim(ti), instructions=nullif(trim(coalesce(ins,'')),''), duration_min=dur, starts_at=s1, ends_at=e1, max_violations=mv, shuffle=coalesce(shuf,true), mandatory=coalesce(mand,true), min_submit_min=null where id=eid;
  update exam_sections set q_count=nq, marks=mk, negative=ng where id=s.id;
  if att then perform _exam_regrade(eid); end if; end $$;

create or replace function exam_lab_mark(t text, aid uuid, marks jsonb) returns json language plpgsql security definer set search_path=public as $$
declare a exam_attempts; e exams; r record; x jsonb; nl jsonb; mv text; was boolean; begin perform _admin(t);
  perform pg_advisory_xact_lock(hashtextextended(aid::text,1));
  select * into a from exam_attempts where id=aid; if a.id is null then raise exception 'Attempt not found'; end if;
  if a.status='in_progress' then raise exception 'The student is still writing this exam'; end if;
  select * into e from exams where id=a.exam_id; if e.category<>'lab' then raise exception 'Only a lab exam is marked by hand'; end if;
  if jsonb_typeof(marks)<>'object' then raise exception 'No marks received'; end if;
  was:=(a.score is not null); nl:=coalesce(a.lab,'{}'::jsonb);
  for r in select z.id, z.mk from _exam_paper(aid) z where z.kind='lab' loop
    x:=marks->(r.id::text); continue when x is null;
    mv:=btrim(coalesce(x->>'m',''));
    if mv='' then nl:=nl-(r.id::text); continue; end if;
    if mv !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' then raise exception 'Marks must be a number like 3 or 2.5'; end if;
    if mv::numeric>r.mk then raise exception 'Marks cannot be more than % for one question', r.mk; end if;
    nl:=jsonb_set(nl,array[r.id::text],jsonb_build_object('m',mv::numeric,'r',left(coalesce(x->>'r',''),500)),true);
  end loop;
  update exam_attempts set lab=nl where id=aid; perform _exam_grade(aid);
  select * into a from exam_attempts where id=aid;
  if not was and a.score is not null then
    insert into notifications(role,user_id,subject_id,kind,title,body,link)
      values('student',a.student_id,e.subject_id,'exam_result',(select code from subjects where id=e.subject_id)||' · result: '||e.title,
        'Marks '||trim(trailing '.' from trim(trailing '0' from a.score::text))||' / '||trim(trailing '.' from trim(trailing '0' from a.total::text)),'exams'); end if;
  return json_build_object('score',a.score,'total',a.total,'pending',(a.score is null)); end $$;

create or replace function exam_lab_export(t text, eid uuid) returns json language plpgsql security definer set search_path=public as $$
declare e exams; begin perform _admin(t);
  select * into e from exams where id=eid; if e.id is null then raise exception 'Exam not found'; end if;
  if e.category<>'lab' then raise exception 'Only for a lab exam'; end if;
  return json_build_object('code',e.code,'title',e.title,'rows',(select coalesce(json_agg(json_build_object('regno',s.regno,'name',s.name,'email',s.email,'status',a.status,'score',a.score,'total',a.total,
      'qs',(select json_agg(json_build_object('no',z.n,'question',z.question,'marks',z.mk,'your',a.answers->>(z.id::text),'got',a.lab->(z.id::text)->>'m','remark',a.lab->(z.id::text)->>'r') order by z.n) from _exam_paper(a.id) z)) order by s.name),'[]')
    from exam_attempts a join students s on s.id=a.student_id where a.exam_id=eid and a.status<>'in_progress')); end $$;

grant execute on function exam_new(text,uuid,text,text,text,int,text,text,int,int,numeric,numeric,boolean,boolean) to anon, authenticated;
grant execute on function exam_settings(text,uuid,text,text,int,text,text,int,int,numeric,numeric,boolean,boolean) to anon, authenticated;
grant execute on function exam_lab_mark(text,uuid,jsonb) to anon, authenticated;
grant execute on function exam_lab_export(text,uuid) to anon, authenticated;
revoke all on function _exam_grade(uuid) from public, anon, authenticated;
revoke all on function _exam_q_put(uuid, uuid, jsonb) from public, anon, authenticated;
notify pgrst, 'reload schema';
