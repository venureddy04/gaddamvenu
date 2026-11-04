-- =====================================================================================================
-- 02_functions.sql   Gaddam Venu portal (v40)       FILE 2 of 3  ->  run AFTER 01_tables.sql
-- Every function of the portal (login, subjects, students, notices, tasks, teams, formats, work posts, marks, labs,
-- batches, timetable, e-mail log ...).  Safe to run again at any time: it keeps all data.
-- =====================================================================================================

set check_function_bodies = off;      -- the functions may call each other in any order

create or replace function _s(t text) returns sessions language plpgsql security definer set search_path=public as $$
declare k sessions; begin select * into k from sessions where token=t and expires_at>now();
  if k.token is null then raise exception 'unauthorized'; end if; return k; end $$;

create or replace function _admin(t text) returns uuid language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t); if k.role<>'admin' then raise exception 'Only the admin can do this'; end if; return k.user_id; end $$;

-- returns 'admin' | 'cr' | 'student' if this login may open the subject, else raises
create or replace function _access(t text, sid uuid) returns text language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  if k.role='admin' then return 'admin'; end if;
  if k.role='cr' and exists(select 1 from cr_subjects where cr_id=k.user_id and subject_id=sid) then return 'cr'; end if;
  if k.role='student' and exists(select 1 from enrollments where student_id=k.user_id and subject_id=sid) then return 'student'; end if;
  raise exception 'Not allowed'; end $$;

create or replace function _mysubs(k sessions) returns setof uuid language sql stable security definer set search_path=public as $$
  select id from subjects where k.role='admin'
  union select subject_id from cr_subjects where k.role='cr' and cr_id=k.user_id
  union select subject_id from enrollments where k.role='student' and student_id=k.user_id $$;

create or replace function _taken(u text) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from admins where upper(username)=upper(u)) or exists(select 1 from crs where upper(username)=upper(u))
      or exists(select 1 from students where upper(regno)=upper(u)) $$;

create or replace function _cleanup() returns void language sql security definer set search_path=public as $$
  delete from sessions where expires_at<now()
     or (role='student' and user_id not in (select id from students))
     or (role='cr' and user_id not in (select id from crs));
  delete from notifications where created_at < now()-interval '90 days'
     or (role='student' and user_id not in (select id from students))
     or (role='cr' and user_id not in (select id from crs)) $$;

-- notify every student and CR of a subject (the bell icon)
create or replace function _notify_subject(sid uuid, kd text, ti text, bd text, lk text) returns void language sql security definer set search_path=public as $$
  insert into notifications(role,user_id,subject_id,kind,title,body,link)
  select 'student', e.student_id, sid, kd, ti, bd, lk from enrollments e where e.subject_id=sid
  union all select 'cr', c.cr_id, sid, kd, ti, bd, lk from cr_subjects c where c.subject_id=sid $$;

-- login lock: 5 wrong tries within 15 minutes lock that ID for 15 minutes
create or replace function _throttle_check(k text) returns void language plpgsql security definer set search_path=public as $$
declare l login_attempts; begin select * into l from login_attempts where key=k;
  if l.locked_until is not null and l.locked_until>now() then
    raise exception 'Too many wrong attempts. Try again in % minute(s).', ceil(extract(epoch from (l.locked_until-now()))/60); end if; end $$;

create or replace function _throttle_fail(k text) returns void language plpgsql security definer set search_path=public as $$
declare l login_attempts; begin select * into l from login_attempts where key=k;
  if l.key is null or l.first_fail < now()-interval '15 minutes' then
    insert into login_attempts(key,fails,first_fail,locked_until) values(k,1,now(),null)
      on conflict (key) do update set fails=1, first_fail=now(), locked_until=null;
  else update login_attempts set fails=fails+1, locked_until=case when fails+1>=5 then now()+interval '15 minutes' end where key=k; end if; end $$;

create or replace function _throttle_ok(k text) returns void language sql security definer set search_path=public as $$ delete from login_attempts where key=k $$;

-- ---------- login (admin e-mail, CR id or student Reg No in ONE box) ----------
-- Student password = Reg No: typing it in CAPS, small or Mixed letters all work.
-- Forgot password (login page): Reg No only. The password becomes the Reg No again (no e-mail, no random password).
create or replace function logout(t text) returns void language sql security definer set search_path=public as $$ delete from sessions where token=t $$;

-- ---------- subjects ----------
-- k = 'theory' (theory only) or 'lab' (theory + lab).  The code is NAME-YEAR-NEXTYEAR, e.g. DS-2026-2027
create or replace function subject_add(t text, n text, y int, f text, k text) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); n:=upper(trim(coalesce(n,'')));
  if n !~ '^[A-Z0-9]{1,12}$' then raise exception 'Subject name: 1-12 letters/digits, no spaces (example: DS)'; end if;
  if coalesce(y,0) not between 2000 and 2100 then raise exception 'Enter a valid year (example: 2026)'; end if;
  if coalesce(k,'') not in ('theory','lab','mini','major') then raise exception 'Choose: Theory only, Theory + Lab, Mini Project or Major Project'; end if;
  insert into subjects(code,name,year,full_name,kind) values(n||'-'||y||'-'||(y+1), n, y, nullif(trim(f),''), k);
  insert into activity(msg) values('Subject '||n||'-'||y||'-'||(y+1)||' created ('||case k when 'lab' then 'theory + lab' when 'mini' then 'mini project' when 'major' then 'major project' else 'theory only' end||')');
exception when unique_violation then raise exception 'This subject and year already exist'; end $$;

create or replace function subject_edit(t text, sid uuid, n text, y int, f text, k text) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); n:=upper(trim(coalesce(n,'')));
  if n !~ '^[A-Z0-9]{1,12}$' then raise exception 'Subject name: 1-12 letters/digits, no spaces (example: DS)'; end if;
  if coalesce(y,0) not between 2000 and 2100 then raise exception 'Enter a valid year (example: 2026)'; end if;
  if coalesce(k,'') not in ('theory','lab','mini','major') then raise exception 'Choose: Theory only, Theory + Lab, Mini Project or Major Project'; end if;
  update subjects set name=n, year=y, code=n||'-'||y||'-'||(y+1), full_name=nullif(trim(coalesce(f,'')),''), kind=k where id=sid;
  if not found then raise exception 'Subject not found'; end if;
  insert into activity(msg) values('Subject '||n||'-'||y||'-'||(y+1)||' edited');
exception when unique_violation then raise exception 'This subject and year already exist'; end $$;

create or replace function subject_del(t text, sid uuid) returns void language plpgsql security definer set search_path=public as $$
declare ss uuid[]; cc uuid[]; cd text; begin perform _admin(t);
  select array_agg(student_id) into ss from enrollments where subject_id=sid;
  select array_agg(cr_id) into cc from cr_subjects where subject_id=sid;
  select code into cd from subjects where id=sid;
  delete from subjects where id=sid;
  delete from students where id=any(ss) and not exists(select 1 from enrollments e where e.student_id=students.id);
  delete from crs where id=any(cc) and not exists(select 1 from cr_subjects x where x.cr_id=crs.id);
  perform _cleanup(); insert into activity(msg) values('Subject '||coalesce(cd,'')||' deleted'); end $$;

-- ---------- students (admin and CR can add; only admin can see passwords / change anything) ----------
-- Password of a new student: the one the admin / Excel gives, or empty = the Reg No (capitals). No random passwords.
-- The student can change it later (password_change). A password chosen by the student is NOT readable by the admin.
create or replace function subject_students(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; begin r:=_access(t,sid); if r='student' then raise exception 'Not allowed'; end if;
  return (select coalesce(json_agg(json_build_object('id',s.id,'regno',s.regno,'name',s.name,'email',s.email,'year',s.year,'semester',s.semester,'mobile',s.mobile,'parent_mobile',s.parent_mobile,
      'pw',case when r='admin' then s.pw end,'photo',s.photo) order by s.regno),'[]')
    from students s join enrollments e on e.student_id=s.id where e.subject_id=sid); end $$;

-- mobile number check: 10 digits (6-9 first). "+91", "91", "0", spaces and dashes in front are ignored. Returns the clean 10 digits.
create or replace function _mobile(m text, lbl text) returns text language plpgsql immutable as $$
declare d text; begin d:=regexp_replace(coalesce(m,''),'[^0-9]','','g');
  if length(d)=12 and left(d,2)='91' then d:=substr(d,3); elsif length(d)=11 and left(d,1)='0' then d:=substr(d,2); end if;
  if d !~ '^[6-9][0-9]{9}$' then raise exception '% must be a 10-digit mobile number', lbl; end if;
  return d; end $$;

-- p = the new password; send the Reg No itself to reset it to the default
-- p = the new password; send the Reg No itself to reset it to the default
-- removes the student from this subject; the account is deleted when no subject is left
create or replace function student_remove(t text, sid uuid, ids uuid[]) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  delete from team_members where subject_id=sid and student_id=any(ids);
  delete from enrollments where subject_id=sid and student_id=any(ids);
  delete from students where id=any(ids) and not exists(select 1 from enrollments e where e.student_id=students.id);
  perform _cleanup(); end $$;

create or replace function students_all(t text) returns json language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  return (select coalesce(json_agg(json_build_object('id',s.id,'regno',s.regno,'name',s.name,'email',s.email,'year',s.year,'semester',s.semester,'mobile',s.mobile,'parent_mobile',s.parent_mobile,'pw',s.pw,'photo',s.photo,
      'created_by',s.created_by,'created_at',s.created_at,
      'subjects',(select coalesce(json_agg(json_build_object('id',sb.id,'code',sb.code) order by sb.code),'[]')
                  from enrollments e join subjects sb on sb.id=e.subject_id where e.student_id=s.id)) order by s.regno),'[]')
    from students s); end $$;

create or replace function student_delete(t text, ids uuid[]) returns int language plpgsql security definer set search_path=public as $$
declare n int; begin perform _admin(t);
  delete from students where id=any(ids); get diagnostics n = row_count;
  perform _cleanup(); insert into activity(msg) values(n||' student account(s) deleted'); return n; end $$;

-- ---------- CR accounts (admin only). Password: set by admin; the form suggests the CR ID itself ----------
create or replace function cr_list(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  return (select coalesce(json_agg(json_build_object('id',c.id,'username',c.username,'name',c.name,'email',c.email,'pw',c.pw,'photo',c.photo) order by c.username),'[]')
    from crs c join cr_subjects x on x.cr_id=c.id where x.subject_id=sid); end $$;

create or replace function cr_add(t text, sid uuid, u text, n text, e text, p text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare c crs; ex boolean:=false; begin perform _admin(t); u:=upper(trim(coalesce(u,'')));
  if u !~ '^[A-Z0-9-]{3,20}$' then raise exception 'CR ID: 3-20 letters, digits or - (example: CSE-CR)'; end if;
  select * into c from crs where username=u;
  if c.id is not null then ex:=true;     -- same CR for one more subject
  else
    if _taken(u) then raise exception 'This ID is already used'; end if;
    p:=coalesce(nullif(btrim(coalesce(p,'')),''),u);
    if length(p)<3 then raise exception 'Password must be at least 3 characters'; end if;
    if trim(coalesce(e,''))<>'' and trim(e) !~ '^\S+@\S+\.\S+$' then raise exception 'Enter a valid email'; end if;
    insert into crs(username,name,email,password_hash,pw) values(u,nullif(trim(n),''),nullif(trim(e),''),crypt(p,gen_salt('bf',8)),p) returning * into c;
  end if;
  insert into cr_subjects(cr_id,subject_id) values(c.id,sid) on conflict do nothing;
  insert into activity(msg) values('CR '||u||' assigned to '||(select code from subjects where id=sid));
  return json_build_object('username',c.username,'name',c.name,'email',c.email,'password',c.pw,'existing',ex); end $$;

-- edit a CR: ID, name, e-mail, password
create or replace function cr_edit(t text, i uuid, u text, n text, e text, p text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare c crs; o crs; begin perform _admin(t); u:=upper(trim(coalesce(u,'')));
  select * into o from crs where id=i; if o.id is null then raise exception 'CR not found'; end if;
  if u !~ '^[A-Z0-9-]{3,20}$' then raise exception 'CR ID: 3-20 letters, digits or - (example: CSE-CR)'; end if;
  if u<>o.username and _taken(u) then raise exception 'This ID is already used'; end if;
  p:=btrim(coalesce(p,''));
  if length(p)<3 then raise exception 'Password must be at least 3 characters'; end if;
  if trim(coalesce(e,''))<>'' and trim(e) !~ '^\S+@\S+\.\S+$' then raise exception 'Enter a valid email'; end if;
  update crs set username=u, name=nullif(trim(coalesce(n,'')),''), email=nullif(trim(coalesce(e,'')),'') where id=i;
  if p<>o.pw then update crs set password_hash=crypt(p,gen_salt('bf',8)), pw=p where id=i; delete from sessions where user_id=i; end if;
  select * into c from crs where id=i;
  insert into activity(msg) values('CR '||c.username||' edited');
  return json_build_object('username',c.username,'name',c.name,'email',c.email,'password',c.pw);
exception when unique_violation then raise exception 'This ID is already used'; end $$;

-- reset a CR password to p (the form sends the CR ID itself)
create or replace function cr_reset(t text, i uuid, p text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare c crs; begin perform _admin(t);
  p:=btrim(coalesce(p,''));
  if length(p)<3 then raise exception 'Password must be at least 3 characters'; end if;
  update crs set password_hash=crypt(p,gen_salt('bf',8)), pw=p where id=i returning * into c;
  if c.id is null then raise exception 'CR not found'; end if;
  delete from sessions where user_id=i;
  return json_build_object('username',c.username,'name',c.name,'email',c.email,'password',c.pw); end $$;

create or replace function cr_remove(t text, sid uuid, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from cr_subjects where subject_id=sid and cr_id=i;
  delete from crs where id=i and not exists(select 1 from cr_subjects x where x.cr_id=crs.id); perform _cleanup(); end $$;

-- ---------- posting (admin) – every post also creates a bell notification; the website e-mails the students ----------
create or replace function material_add(t text, sid uuid, rw jsonb) returns int language plpgsql security definer set search_path=public as $$
declare x jsonb; n int:=0; ti text; cd text; kd text; begin perform _admin(t);
  select kind into kd from subjects where id=sid; if kd is null then raise exception 'Subject not found'; end if;
  for x in select * from jsonb_array_elements(rw) loop
    if x->>'category' in ('Lab Marks','Lab Syllabus','Lab Lesson Plan') and kd<>'lab' then raise exception 'Lab Syllabus, Lab Lesson Plan and Lab Sheet are only for Theory + Lab subjects'; end if;
    if coalesce(x->>'category','') <> all(array['Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks']) then raise exception 'Choose a valid category'; end if;
    if coalesce(x->>'link','') !~* '^https?://\S+$' then raise exception 'Every row needs a valid link (starting with https://)'; end if;
    ti:=coalesce(nullif(trim(x->>'title'),''), x->>'category');
    insert into materials(subject_id,category,title,link) values(sid,x->>'category',ti,trim(x->>'link')); n:=n+1;
  end loop;
  select code into cd from subjects where id=sid;
  insert into activity(msg) values(n||' material(s) added to '||cd);
  perform _notify_subject(sid,'material',cd||' · new upload',n||' item(s) added',
    'subject/'||cd||'/'||case when (rw->0->>'category') in ('Theory Syllabus','Lab Syllabus') then 'syllabus' when (rw->0->>'category') in ('Theory Lesson Plan','Lab Lesson Plan') then 'lessonplan' when (rw->0->>'category') in ('Mid 1','Mid 2','AAT1','AAT2') then 'marks' when (rw->0->>'category')='Lab Marks' then 'labsheet' else 'materials' end); return n; end $$;

create or replace function material_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from materials where id=i; end $$;

create or replace function video_add(t text, sid uuid, rw jsonb) returns int language plpgsql security definer set search_path=public as $$
declare x jsonb; n int:=0; cd text; begin perform _admin(t);
  for x in select * from jsonb_array_elements(rw) loop
    if coalesce(x->>'link','') !~* '^https?://\S+$' then raise exception 'Every row needs a valid video link (starting with https://)'; end if;
    insert into videos(subject_id,title,link) values(sid,coalesce(nullif(trim(x->>'title'),''),'Lesson'),trim(x->>'link')); n:=n+1;
  end loop;
  select code into cd from subjects where id=sid;
  insert into activity(msg) values(n||' video lesson(s) added to '||cd);
  perform _notify_subject(sid,'video',cd||' · new video lesson',n||' video(s) added','subject/'||cd||'/videos'); return n; end $$;

create or replace function video_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from videos where id=i; end $$;

create or replace function notice_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from notices where id=i; end $$;

create or replace function lab_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from labs where id=i; end $$;

-- ---------- e-mail ----------
-- students (with a valid e-mail) of the given subjects; sids = null means every subject
create or replace function email_recipients(t text, sids uuid[]) returns json language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  return (select coalesce(json_agg(x),'[]') from (select distinct on (lower(s.email)) s.name, s.email, coalesce(s.regno,s.email) as regno
    from students s join enrollments e on e.student_id=s.id
    where (sids is null or e.subject_id=any(sids)) and s.email ~ '^\S+@\S+\.\S+$' order by lower(s.email)) x); end $$;

create or replace function email_log_add(t text, rw jsonb) returns void language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t); if k.role='student' then raise exception 'Not allowed'; end if;
  insert into email_log(kind,to_email,name,subject,status,error,message)
  select x->>'kind',x->>'to_email',x->>'name',x->>'subject',x->>'status',x->>'error',x->>'message' from jsonb_array_elements(rw) x; end $$;

create or replace function email_log(t text, n int) returns json language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  return (select coalesce(json_agg(x),'[]') from (select id,created_at,to_email,name,kind,subject,status,error,message from email_log order by id desc limit n) x); end $$;

create or replace function email_log_del(t text, ids bigint[]) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from email_log where id=any(ids); end $$;

create or replace function email_log_clear(t text) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from email_log; end $$;

-- ---------- profile photo + own password ----------
-- the photo is a small JPEG (about 5-10 KB) stored as a data URL; p = null removes it
create or replace function profile_photo_set(t text, p text) returns void language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  if p is not null and (p !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(p)>120000) then raise exception 'This photo cannot be used. Choose another one.'; end if;
  if k.role='admin' then update admins set photo=p where id=k.user_id;
  elsif k.role='cr' then update crs set photo=p where id=k.user_id;
  else update students set photo=p where id=k.user_id; end if; end $$;

-- a STUDENT changes his / her own password (CR and admin passwords are changed only by the admin)
-- ---------- notifications (bell icon, for whoever is logged in) ----------
create or replace function notif_list(t text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  return (select coalesce(json_agg(x),'[]') from (select id,kind,title,body,link,seen,created_at from notifications
    where role=k.role and user_id=k.user_id order by id desc limit 60) x); end $$;

create or replace function notif_count(t text) returns int language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  return (select count(*) from notifications where role=k.role and user_id=k.user_id and not seen); end $$;

create or replace function notif_read(t text, ids bigint[]) returns void language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  update notifications set seen=true where role=k.role and user_id=k.user_id and (ids is null or id=any(ids)); end $$;

-- v37: student login by Gmail, optional Reg No, required mobile, TASKS (Word file submissions)
-- ---------- login: admin e-mail, CR id, or STUDENT GMAIL + password (Reg No is no longer used to log in) ----------
create or replace function unified_login(u text, p text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare a admins; c crs; s students; k text; kk text; ident text;
begin
  ident:=lower(trim(coalesce(u,'')));
  kk:='login:'||ident; perform _throttle_check(kk); perform _cleanup();
  k:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','');

  select * into a from admins where username=ident;
  if a.id is not null and a.password_hash=crypt(p,a.password_hash) then
    perform _throttle_ok(kk); insert into sessions(token,role,user_id,expires_at) values(k,'admin',a.id,now()+interval '8 hours');
    return json_build_object('role','admin','token',k,'name',coalesce(a.name,'Admin'),'sub','Admin','photo',a.photo); end if;

  select * into c from crs where username=upper(trim(u));
  if c.id is not null and (c.password_hash=crypt(p,c.password_hash) or c.password_hash=crypt(upper(btrim(p)),c.password_hash)) then
    perform _throttle_ok(kk); insert into sessions(token,role,user_id,expires_at) values(k,'cr',c.id,now()+interval '2 days');
    return json_build_object('role','cr','token',k,'name',coalesce(nullif(c.name,''),c.username),'sub','CR · '||c.username,'photo',c.photo); end if;

  select * into s from students where lower(email)=ident;
  if s.id is not null and s.password_hash=crypt(p,s.password_hash) then
    perform _throttle_ok(kk); insert into sessions(token,role,user_id,expires_at) values(k,'student',s.id,now()+interval '3 days');
    return json_build_object('role','student','token',k,'name',s.name,'sub','Student · Year '||s.year,'photo',s.photo); end if;

  perform _throttle_fail(kk); return json_build_object('error','Invalid Gmail or password'); end $$;

create or replace function forgot_password(em text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare s students; e text; kk text;
begin e:=lower(btrim(coalesce(em,''))); kk:='forgot:'||e; perform _throttle_check(kk);
  select * into s from students where lower(email)=e;
  if s.id is null then perform _throttle_fail(kk); return json_build_object('error','This Gmail is not registered. Check it, or ask your admin.'); end if;
  if coalesce(s.mobile,'')='' then return json_build_object('error','No mobile number is saved for this account. Ask your admin to reset the password.'); end if;
  update students set password_hash=crypt(s.mobile,gen_salt('bf',8)), pw=s.mobile where id=s.id;
  delete from sessions where user_id=s.id;
  perform _throttle_ok(kk);
  return json_build_object('ok',true,'name',s.name); end $$;

-- ---------- add students.  REQUIRED: Gmail, name, password (6+ characters), student mobile.  OPTIONAL: Reg No, parent mobile ----------
create or replace function students_add(t text, sid uuid, rw jsonb) returns json language plpgsql security definer set search_path=public,extensions as $$
declare r text; x jsonb; rg text; nm text; em text; pwd text; ex students; nid uuid; sm int; mb text; pm text;
        added jsonb:='[]'; had jsonb:='[]'; bad jsonb:='[]';
begin r:=_access(t,sid); if r='student' then raise exception 'Not allowed'; end if;
  for x in select * from jsonb_array_elements(rw) loop
    em:=lower(trim(coalesce(x->>'email','')));
    begin
      if em !~ '^\S+@\S+\.\S+$' then raise exception 'A valid Gmail is required'; end if;
      select * into ex from students where lower(email)=em;
      if ex.id is not null then            -- already has an account: only add to this subject
        insert into enrollments(subject_id,student_id) values(sid,ex.id) on conflict do nothing;
        had:=had||jsonb_build_array(em);
      else
        if exists(select 1 from admins where lower(username)=em) then raise exception 'This Gmail is reserved'; end if;
        nm:=trim(coalesce(x->>'name','')); if length(nm)<2 then raise exception 'Name is required'; end if;
        pwd:=btrim(coalesce(x->>'password','')); if length(pwd)<6 then raise exception 'Password is required (at least 6 characters)'; end if;
        mb:=_mobile(x->>'mobile','Student mobile number');
        pm:=case when btrim(coalesce(x->>'parent_mobile',''))='' then null else _mobile(x->>'parent_mobile','Parent mobile number') end;
        rg:=upper(trim(coalesce(x->>'regno',''))); if rg='' then rg:=null; end if;
        if rg is not null and rg !~ '^[A-Z0-9]{5,15}$' then raise exception 'Reg No (optional) must be 5-15 letters/digits'; end if;
        if rg is not null and (exists(select 1 from admins where upper(username)=rg) or exists(select 1 from crs where username=rg)) then raise exception 'This Reg No is reserved'; end if;
        if coalesce(x->>'year','') !~ '^[1-4]$' then raise exception 'Year must be 1, 2, 3 or 4'; end if;
        if coalesce(x->>'semester','') !~ '^[1-8]$' then raise exception 'Semester must be 1 to 8'; end if;
        sm:=(x->>'semester')::int;
        insert into students(regno,name,email,year,semester,mobile,parent_mobile,password_hash,pw,created_by)
          values(rg,nm,em,(x->>'year')::int,sm,mb,pm,crypt(pwd,gen_salt('bf',8)),pwd,case when r='admin' then 'admin' else 'cr' end) returning id into nid;
        insert into enrollments(subject_id,student_id) values(sid,nid);
        added:=added||jsonb_build_array(jsonb_build_object('email',em,'name',nm,'regno',rg));
      end if;
    exception when unique_violation then bad:=bad||jsonb_build_array(jsonb_build_object('email',em,'why','This Gmail or Reg No is already used'));
              when others then bad:=bad||jsonb_build_array(jsonb_build_object('email',em,'why',sqlerrm)); end;
  end loop;
  if jsonb_array_length(added)>0 then insert into activity(msg) values(jsonb_array_length(added)||' student(s) added to '||(select code from subjects where id=sid)||' by '||r); end if;
  return json_build_object('added',added,'existing',had,'skipped',bad); end $$;

create or replace function student_edit(t text, i uuid, rg text, n text, e text, y int, sm int, mb text, pm text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare s students; begin perform _admin(t); rg:=upper(trim(coalesce(rg,''))); if rg='' then rg:=null; end if;
  if rg is not null and rg !~ '^[A-Z0-9]{5,15}$' then raise exception 'Reg No (optional) must be 5-15 letters/digits'; end if;
  if rg is not null and (exists(select 1 from admins where upper(username)=rg) or exists(select 1 from crs where username=rg)) then raise exception 'This Reg No is reserved'; end if;
  if length(trim(coalesce(n,'')))<2 then raise exception 'Name is required'; end if;
  e:=lower(trim(coalesce(e,'')));
  if e !~ '^\S+@\S+\.\S+$' then raise exception 'A valid Gmail is required'; end if;
  if exists(select 1 from admins where lower(username)=e) then raise exception 'This Gmail is reserved'; end if;
  if coalesce(y,0) not between 1 and 4 then raise exception 'Year must be 1-4'; end if;
  if coalesce(sm,0) not between 1 and 8 then raise exception 'Semester must be 1 to 8'; end if;
  mb:=_mobile(mb,'Student mobile number');
  pm:=case when btrim(coalesce(pm,''))='' then null else _mobile(pm,'Parent mobile number') end;
  update students set regno=rg, name=trim(n), email=e, year=y, semester=sm, mobile=mb, parent_mobile=pm where id=i returning * into s;
  if s.id is null then raise exception 'Student not found'; end if;
  return json_build_object('regno',s.regno,'name',s.name,'email',s.email,'year',s.year,'semester',s.semester,'mobile',s.mobile,'parent_mobile',s.parent_mobile,'password',s.pw);
exception when unique_violation then raise exception 'That Gmail or Reg No is already used'; end $$;

-- p = the new password (6+ characters)
create or replace function student_reset(t text, i uuid, p text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare s students; begin perform _admin(t);
  select * into s from students where id=i; if s.id is null then raise exception 'Student not found'; end if;
  p:=btrim(coalesce(p,''));
  if length(p)<6 then raise exception 'Password must be at least 6 characters'; end if;
  update students set password_hash=crypt(p,gen_salt('bf',8)), pw=p where id=i returning * into s;
  delete from sessions where user_id=i;
  return json_build_object('regno',s.regno,'name',s.name,'email',s.email,'year',s.year,'password',s.pw); end $$;

create or replace function password_change(t text, old text, nw text) returns void language plpgsql security definer set search_path=public,extensions as $$
declare k sessions; s students; kk text; begin k:=_s(t);
  if k.role<>'student' then raise exception 'Only the admin can change this password'; end if;
  select * into s from students where id=k.user_id; kk:='pwchg:'||s.email; perform _throttle_check(kk);
  if not (s.password_hash=crypt(coalesce(old,''),s.password_hash)) then
    perform _throttle_fail(kk); raise exception 'The current password is wrong'; end if;
  perform _throttle_ok(kk);
  nw:=btrim(coalesce(nw,''));
  if length(nw)<6 then raise exception 'New password must be at least 6 characters'; end if;
  update students set password_hash=crypt(nw,gen_salt('bf',8)), pw='(set by the student)' where id=s.id;
  delete from sessions where user_id=s.id and token<>t; end $$;

create or replace function profile_get(t text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  if k.role='admin' then return (select json_build_object('role','admin','name',coalesce(name,'Admin'),'id',username,'photo',photo) from admins where id=k.user_id); end if;
  if k.role='cr' then return (select json_build_object('role','cr','name',coalesce(nullif(name,''),username),'id',username,'photo',photo) from crs where id=k.user_id); end if;
  return (select json_build_object('role','student','name',name,'id',email,'photo',photo) from students where id=k.user_id); end $$;

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
      (select count(*) from exams x where x.subject_id=s.id and (k.role='admin' or x.status<>'draft')) as exams,
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
        select 'Exam', e.title, s.code, (e.starts_at at time zone 'Asia/Kolkata')::date, (e.starts_at at time zone 'Asia/Kolkata')::time from exams e join subjects s on s.id=e.subject_id
          where e.status='published' and e.starts_at is not null and e.subject_id in (select * from _mysubs(k)) and (k.role='admin' or not _hid(e.subject_id,'exams'))
        union all
        select 'Lab', trim('Exp '||coalesce(l.exp_no,'')||' '||l.title), s.code, l.lab_date, l.lab_time from labs l join subjects s on s.id=l.subject_id
          where l.lab_date is not null and l.subject_id in (select * from _mysubs(k)) and (k.role='admin' or (l.visible and not _hid(l.subject_id,'labs')))) e),
    'stats',case when k.role='admin' then json_build_object(
        'subjects',(select count(*) from subjects),'students',(select count(*) from students),'crs',(select count(*) from crs),
        'materials',(select count(*) from materials where category not in ('Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan')),'videos',(select count(*) from videos),'notices',(select count(*) from notices),'labs',(select count(*) from labs),
        'tasks',(select count(*) from tasks),'exams',(select count(*) from exams),'teams',(select count(*) from teams),'work',(select count(*) from work_posts),'to_check',(select count(*) from task_submissions where status='submitted'),
        'emails_sent',(select count(*) from email_log where status='sent'),'emails_failed',(select count(*) from email_log where status='failed')) end,
    'exams',(select coalesce(json_agg(json_build_object('code',e.code,'title',e.title,'subject',s.code,'starts_at',e.starts_at,'ends_at',e.ends_at,'duration_min',e.duration_min,
        'mine',(select a.status from exam_attempts a where a.exam_id=e.id and a.student_id=k.user_id and k.role='student')) order by coalesce(e.starts_at,e.created_at) desc),'[]')
      from (select * from exams where status='published' and subject_id in (select * from _mysubs(k)) and (k.role='admin' or not _hid(subject_id,'exams')) order by created_at desc limit 12) e join subjects s on s.id=e.subject_id),
    'activity',case when k.role='admin' then (select coalesce(json_agg(a),'[]') from (select msg,created_at from activity order by id desc limit 8) a) end); end $$;

-- ---------- helpers ----------
drop function if exists task_submit(text,uuid,text,text);
create or replace function _isproj(sid uuid) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from subjects where id=sid and kind in ('mini','major')) $$;

create or replace function _myteam(uid uuid, sid uuid) returns uuid language sql stable security definer set search_path=public as $$
  select team_id from team_members where student_id=uid and subject_id=sid $$;

-- only a Google Drive / Docs link is accepted
create or replace function _drive(lk text) returns text language plpgsql immutable as $$
declare v text; begin v:=btrim(coalesce(lk,''));
  if v !~* '^https://(drive|docs)\.google\.com/\S+$' then raise exception 'Only a Google Drive link is accepted (it must start with https://drive.google.com/ or https://docs.google.com/)'; end if;
  if length(v)>500 then raise exception 'The link is too long'; end if;
  return v; end $$;

-- a Drive FILE link (Word / PPT / PDF ...) that can be shown in the viewer: not a folder
create or replace function _drive_file(lk text) returns text language plpgsql immutable as $$
declare v text; begin v:=_drive(lk);
  if v !~ '(/d/[A-Za-z0-9_-]{10,}|[?&]id=[A-Za-z0-9_-]{10,})' then raise exception 'Paste the link of the FILE (Word / PPT / PDF), not of a folder. In Drive: right-click the file > Share > Copy link.'; end if;
  return v; end $$;

-- ---------- VISIBLE = true / false (v41) ----------
-- is this tab of the subject switched off by the admin?
create or replace function _hid(sid uuid, tb text) returns boolean language sql stable security definer set search_path=public as $$
  select coalesce(tb = any(hidden_tabs), false) from subjects where id=sid $$;

-- the tab where a Drive-link category is shown
create or replace function _mat_tab(cat text) returns text language sql immutable as $$
  select case when cat in ('Theory Syllabus','Lab Syllabus') then 'syllabus'
              when cat in ('Theory Lesson Plan','Lab Lesson Plan') then 'lessonplan'
              when cat like 'Unit %' then 'materials'
              when cat='Lab Marks' then 'labsheet' else 'marks' end $$;

-- admin: show (true) or hide (false) a whole TAB of one subject for the students and the CR
create or replace function tab_visible_set(t text, sid uuid, tb text, vis boolean) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  if tb is null or tb not in ('syllabus','lessonplan','materials','videos','marks','notices','tasks','exams','labs','labsheet','teams','formats','work') then raise exception 'This tab cannot be hidden'; end if;
  if vis is null then raise exception 'Type true or false'; end if;
  update subjects set hidden_tabs = case when vis then array_remove(hidden_tabs,tb) else array_remove(hidden_tabs,tb) || tb end where id=sid;
  if not found then raise exception 'Subject not found'; end if; end $$;

-- admin: show (true) or hide (false) ONE card.  kd = material | video | notice | lab | task | format
create or replace function item_visible_set(t text, kd text, i uuid, vis boolean) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  if vis is null then raise exception 'Type true or false'; end if;
  if    kd='material' then update materials set visible=vis where id=i;
  elsif kd='video'    then update videos    set visible=vis where id=i;
  elsif kd='notice'   then update notices   set visible=vis where id=i;
  elsif kd='lab'      then update labs      set visible=vis where id=i;
  elsif kd='task'     then update tasks     set visible=vis where id=i;
  elsif kd='format'   then update formats   set visible=vis where id=i;
  else raise exception 'Wrong item'; end if;
  if not found then raise exception 'Item not found'; end if; end $$;

-- ---------- TASKS ----------
-- v41: the deadline is ONE field (date + time) and the admin chooses how students submit:  sm = 'link' (Google Drive link) | 'button' (one press)
drop function if exists task_add(text,uuid,text,text,text,text);
create or replace function task_add(t text, sid uuid, ti text, msg text, dl text, mx text, sm text) returns void language plpgsql security definer set search_path=public as $$
declare cd text; m numeric; d timestamptz; md text; begin perform _admin(t);
  if length(trim(coalesce(ti,'')))<1 then raise exception 'Enter a title'; end if;
  if length(coalesce(msg,''))>30000 then raise exception 'The task text is too long'; end if;
  md:=coalesce(nullif(btrim(coalesce(sm,'')),''),'link');
  if md not in ('link','button') then raise exception 'Choose how the students submit: Drive link or Button'; end if;
  if btrim(coalesce(dl,''))<>'' then
    begin d:=btrim(dl)::timestamptz; exception when others then raise exception 'The deadline is not a valid date and time'; end; end if;
  if btrim(coalesce(mx,''))<>'' then
    if btrim(mx) !~ '^[0-9]{1,4}(\.[0-9]{1,2})?$' then raise exception 'Maximum marks must be a number'; end if; m:=btrim(mx)::numeric; end if;
  insert into tasks(subject_id,title,message,due_date,deadline,max_marks,submit_mode)
    values(sid,trim(ti),nullif(trim(coalesce(msg,'')),''),(d at time zone 'Asia/Kolkata')::date,d,m,md);
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Task posted in '||cd);
  perform _notify_subject(sid,'task',cd||' · new task: '||trim(ti),
    case when d is not null then 'Deadline: '||to_char(d at time zone 'Asia/Kolkata','DD Mon YYYY, HH12:MI AM') end,'subject/'||cd||'/tasks'); end $$;

create or replace function task_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from tasks where id=i; end $$;

-- v44: admin posts a task with ONE Google Drive link (students open it); optional note, deadline, visible true / false
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

-- v44: admin edits a posted task
create or replace function task_edit(t text, i uuid, ti text, lk text, nt text, dl text, vis boolean) returns void language plpgsql security definer set search_path=public as $$
declare d timestamptz; begin perform _admin(t);
  if length(trim(coalesce(ti,'')))<1 then raise exception 'Enter a title'; end if;
  if length(coalesce(nt,''))>2000 then raise exception 'The note is too long (2000 characters)'; end if;
  if btrim(coalesce(dl,''))<>'' then begin d:=btrim(dl)::timestamptz; exception when others then raise exception 'The deadline is not a valid date and time'; end; end if;
  update tasks set title=trim(ti), message=nullif(trim(coalesce(nt,'')),''), link=_drive(lk), due_date=(d at time zone 'Asia/Kolkata')::date, deadline=d, visible=coalesce(vis,visible) where id=i;
  if not found then raise exception 'Task not found'; end if; end $$;

-- the tasks of a subject. A student gets his / her own submission (Theory / Lab) or the team's submission (project).
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

-- admin: Theory / Lab = every student with his / her file;  Project = every team with its Drive link
create or replace function task_subs(t text, tid uuid) returns json language plpgsql security definer set search_path=public as $$
declare sid uuid; begin perform _admin(t);
  select subject_id into sid from tasks where id=tid; if sid is null then raise exception 'Task not found'; end if;
  if _isproj(sid) then
    return (select coalesce(json_agg(json_build_object('team_id',tm.id,'regno',null,'mobile',null,'name',tm.name,
        'email',coalesce((select string_agg(st.name,', ' order by st.name) from team_members m join students st on st.id=m.student_id where m.team_id=tm.id),'no members'),
        'sub_id',s.id,'file_name',s.file_name,'file_size',s.file_size,'has_link',(s.link is not null),'via_button',s.via_button,'by',(select name from students where id=s.student_id),
        'status',s.status,'marks',s.marks,'remark',s.remark,'submitted_at',s.submitted_at,'updated_at',s.updated_at) order by tm.name),'[]')
      from teams tm left join task_submissions s on s.task_id=tid and s.team_id=tm.id where tm.subject_id=sid);
  end if;
  return (select coalesce(json_agg(json_build_object('student_id',st.id,'regno',st.regno,'name',st.name,'email',st.email,'mobile',st.mobile,
      'sub_id',s.id,'file_name',s.file_name,'file_size',s.file_size,'has_link',(s.link is not null),'via_button',s.via_button,'status',s.status,'marks',s.marks,'remark',s.remark,'submitted_at',s.submitted_at,'updated_at',s.updated_at) order by st.name),'[]')
    from enrollments e join students st on st.id=e.student_id left join task_submissions s on s.task_id=tid and s.student_id=st.id and s.team_id is null where e.subject_id=sid); end $$;

-- download of an OLD Word file (sent with an older version): the admin, or the student who owns it
create or replace function task_file(t text, i uuid) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; s task_submissions; begin k:=_s(t);
  select * into s from task_submissions where id=i; if s.id is null or s.file_data is null then raise exception 'Submission not found'; end if;
  if not (k.role='admin' or (k.role='student' and s.student_id=k.user_id)) then raise exception 'Not allowed'; end if;
  return json_build_object('file_name',s.file_name,'file_data',s.file_data); end $$;

-- student: submit (or replace) ONE Google Drive link for the task.  Theory / Lab subject: every student;  Project: the team (any member can do it).
-- The link is never shown on the site: everybody opens it with "View" inside the site (see task_link).  The Word upload of the older versions was removed.
create or replace function task_submit_link(t text, tid uuid, lk text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; tk tasks; s task_submissions; mt uuid; nid uuid; begin k:=_s(t);
  if k.role<>'student' then raise exception 'Only a student can submit a task'; end if;
  select * into tk from tasks where id=tid; if tk.id is null then raise exception 'Task not found'; end if;
  if not exists(select 1 from enrollments where student_id=k.user_id and subject_id=tk.subject_id) then raise exception 'Not allowed'; end if;
  if not tk.visible or _hid(tk.subject_id,'tasks') then raise exception 'Task not found'; end if;
  if tk.submit_mode<>'link' then raise exception 'This task is submitted with the Submit button, not with a link'; end if;
  lk:=_drive_file(lk);
  if _isproj(tk.subject_id) then
    mt:=_myteam(k.user_id,tk.subject_id); if mt is null then raise exception 'You are not in a team yet. The admin will add you to a team.'; end if;
    select * into s from task_submissions where task_id=tid and team_id=mt;
    if s.id is not null and s.status='verified' then raise exception 'The admin already marked this as OK. It cannot be changed now.'; end if;
    insert into task_submissions(task_id,student_id,team_id,link) values(tid,k.user_id,mt,lk)
      on conflict (task_id, team_id) where team_id is not null do update set link=excluded.link, file_name=null, file_data=null, file_size=null, student_id=excluded.student_id,
        status='submitted', marks=null, remark=null, verified_at=null, updated_at=now()
      returning id into nid;
  else
    select * into s from task_submissions where task_id=tid and student_id=k.user_id and team_id is null;
    if s.id is not null and s.status='verified' then raise exception 'The admin already marked this as OK. It cannot be changed now.'; end if;
    insert into task_submissions(task_id,student_id,link) values(tid,k.user_id,lk)
      on conflict (task_id, student_id) where team_id is null do update set link=excluded.link, file_name=null, file_data=null, file_size=null,
        status='submitted', marks=null, remark=null, verified_at=null, updated_at=now()
      returning id into nid;
  end if;
  return json_build_object('id',nid); end $$;

-- student: submit a BUTTON task with one press (no link, no file).  Theory / Lab: every student;  Project: the team (any member can do it).
create or replace function task_submit_button(t text, tid uuid) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; tk tasks; s task_submissions; mt uuid; nid uuid; begin k:=_s(t);
  if k.role<>'student' then raise exception 'Only a student can submit a task'; end if;
  select * into tk from tasks where id=tid; if tk.id is null then raise exception 'Task not found'; end if;
  if not exists(select 1 from enrollments where student_id=k.user_id and subject_id=tk.subject_id) then raise exception 'Not allowed'; end if;
  if not tk.visible or _hid(tk.subject_id,'tasks') then raise exception 'Task not found'; end if;
  if tk.submit_mode<>'button' then raise exception 'This task needs a Google Drive link, not the Submit button'; end if;
  if _isproj(tk.subject_id) then
    mt:=_myteam(k.user_id,tk.subject_id); if mt is null then raise exception 'You are not in a team yet. The admin will add you to a team.'; end if;
    select * into s from task_submissions where task_id=tid and team_id=mt;
    if s.id is null then insert into task_submissions(task_id,student_id,team_id,via_button) values(tid,k.user_id,mt,true) returning id into nid; end if;
  else
    select * into s from task_submissions where task_id=tid and student_id=k.user_id and team_id is null;
    if s.id is null then insert into task_submissions(task_id,student_id,via_button) values(tid,k.user_id,true) returning id into nid; end if;
  end if;
  if s.id is not null then                                     -- already there: a "send again" (redo) is submitted again, anything else stays as it is
    if s.status='redo' then
      update task_submissions set status='submitted', marks=null, remark=null, verified_at=null, student_id=k.user_id, via_button=true, updated_at=now() where id=s.id; end if;
    nid:=s.id; end if;
  return json_build_object('id',nid); end $$;

-- the Drive link of a submission, ONLY for viewing it inside the site: the admin, or the student / team member who sent it.  The pages never print the link.
create or replace function task_link(t text, i uuid) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; s task_submissions; tk tasks; begin k:=_s(t);
  select * into s from task_submissions where id=i; if s.id is null or s.link is null then raise exception 'Submission not found'; end if;
  select * into tk from tasks where id=s.task_id;
  if not (k.role='admin' or (k.role='student' and (s.student_id=k.user_id or (s.team_id is not null and s.team_id=_myteam(k.user_id,tk.subject_id))))) then raise exception 'Not allowed'; end if;
  return json_build_object('link',s.link,'title',tk.title); end $$;

-- delete a submission: the student / a team member (until it is verified) or the admin
create or replace function task_sub_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
declare k sessions; s task_submissions; sid uuid; begin k:=_s(t);
  select * into s from task_submissions where id=i; if s.id is null then raise exception 'Submission not found'; end if;
  select subject_id into sid from tasks where id=s.task_id;
  if k.role='student' then
    if not (s.student_id=k.user_id or (s.team_id is not null and s.team_id=_myteam(k.user_id,sid))) then raise exception 'Not allowed'; end if;
    if s.status='verified' then raise exception 'The admin already marked this as OK. It cannot be deleted now.'; end if;
  elsif k.role<>'admin' then raise exception 'Not allowed'; end if;
  delete from task_submissions where id=i; end $$;

-- admin: review.  st = 'verified' (OK) | 'redo' (send again) | 'submitted' | null (keep).  mk = marks ('' clears, null keeps).  rm = remark.
-- Marks can only be given to a verified (OK) submission.
create or replace function task_review(t text, i uuid, st text, mk text, rm text) returns void language plpgsql security definer set search_path=public as $$
declare s task_submissions; tk tasks; m numeric; ns text; cd text; begin perform _admin(t);
  select * into s from task_submissions where id=i; if s.id is null then raise exception 'Submission not found'; end if;
  select * into tk from tasks where id=s.task_id;
  ns:=coalesce(nullif(btrim(coalesce(st,'')),''),s.status);
  if ns not in ('submitted','verified','redo') then raise exception 'Wrong status'; end if;
  if mk is null then m:=s.marks;
  elsif btrim(mk)='' then m:=null;
  else
    if btrim(mk) !~ '^[0-9]{1,4}(\.[0-9]{1,2})?$' then raise exception 'Marks must be a number'; end if;
    m:=btrim(mk)::numeric;
    if tk.max_marks is not null and m>tk.max_marks then raise exception 'Marks cannot be more than %', tk.max_marks; end if;
    if ns<>'verified' then raise exception 'Mark the task as OK (verified) first, then update the marks'; end if;
  end if;
  if length(coalesce(rm,''))>500 then raise exception 'The remark is too long (500 characters)'; end if;
  update task_submissions set status=ns, marks=case when ns='verified' then m else null end,
    remark=case when rm is null then remark else nullif(btrim(rm),'') end,
    verified_at=case when ns='verified' then coalesce(verified_at,now()) else null end, updated_at=now() where id=i;
  if ns<>s.status and ns in ('verified','redo') then
    select code into cd from subjects where id=tk.subject_id;
    insert into notifications(role,user_id,subject_id,kind,title,body,link)
      select 'student', u, tk.subject_id,'task',cd||' · '||tk.title,case ns when 'verified' then 'Your task was marked OK' else 'Please correct your task and submit again' end,'subject/'||cd||'/tasks'
      from unnest(case when s.team_id is null then array[s.student_id] else array(select student_id from team_members where team_id=s.team_id) end) as u;
  end if; end $$;

-- ---------- TEAMS (projects) ----------
create or replace function teams_get(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; begin r:=_access(t,sid); k:=_s(t);
  if not _isproj(sid) then raise exception 'Teams are only for project subjects'; end if;
  return json_build_object('my',case when r='student' then _myteam(k.user_id,sid) end,
    'teams',(select coalesce(json_agg(json_build_object('id',tm.id,'name',tm.name,'title',tm.title,'guide',tm.guide,'created_at',tm.created_at,
        'members',(select coalesce(json_agg(json_build_object('student_id',st.id,'name',st.name,'regno',st.regno,'leader',m.leader,
            'email',case when r<>'student' then st.email end,'mobile',case when r<>'student' then st.mobile end) order by m.leader desc, st.name),'[]')
          from team_members m join students st on st.id=m.student_id where m.team_id=tm.id)) order by tm.name),'[]') from teams tm where tm.subject_id=sid),
    'free',case when r<>'student' then (select coalesce(json_agg(json_build_object('student_id',st.id,'name',st.name,'regno',st.regno,'email',st.email) order by st.name),'[]')
        from students st join enrollments e on e.student_id=st.id and e.subject_id=sid where not exists(select 1 from team_members m where m.subject_id=sid and m.student_id=st.id)) end); end $$;

-- admin: create (tid null) or edit a team.  mem = [{student_id, leader}]
create or replace function team_save(t text, sid uuid, tid uuid, nm text, ti text, gd text, mem jsonb) returns void language plpgsql security definer set search_path=public as $$
declare id2 uuid; x jsonb; sx uuid; cd text; begin perform _admin(t);
  if not _isproj(sid) then raise exception 'Teams are only for project subjects'; end if;
  nm:=trim(coalesce(nm,'')); if length(nm)<1 or length(nm)>60 then raise exception 'Enter the team name (up to 60 characters)'; end if;
  if tid is null then insert into teams(subject_id,name,title,guide) values(sid,nm,nullif(trim(coalesce(ti,'')),''),nullif(trim(coalesce(gd,'')),'')) returning id into id2;
  else update teams set name=nm, title=nullif(trim(coalesce(ti,'')),''), guide=nullif(trim(coalesce(gd,'')),'') where id=tid and subject_id=sid returning id into id2;
    if id2 is null then raise exception 'Team not found'; end if; end if;
  delete from team_members where team_id=id2;
  for x in select * from jsonb_array_elements(coalesce(mem,'[]'::jsonb)) loop
    sx:=(x->>'student_id')::uuid;
    if not exists(select 1 from enrollments where subject_id=sid and student_id=sx) then raise exception 'A selected student is not in this project'; end if;
    delete from team_members where subject_id=sid and student_id=sx;                 -- moved from another team
    insert into team_members(team_id,subject_id,student_id,leader) values(id2,sid,sx,coalesce((x->>'leader')::boolean,false));
  end loop;
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Team '||nm||' saved in '||cd);
exception when unique_violation then raise exception 'A team with this name already exists or a student is in two teams'; end $$;

create or replace function team_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from teams where id=i; end $$;

-- admin: put the students that have no team into new teams of n students (the first of each team is the leader)
create or replace function teams_auto(t text, sid uuid, n int) returns int language plpgsql security definer set search_path=public as $$
declare ids uuid[]; i int:=1; made int:=0; tn int; nt uuid; begin perform _admin(t);
  if not _isproj(sid) then raise exception 'Teams are only for project subjects'; end if;
  if coalesce(n,0) not between 1 and 20 then raise exception 'Team size must be between 1 and 20'; end if;
  select coalesce(max(substring(name from '^Team ([0-9]+)$')::int),0) into tn from teams where subject_id=sid;
  select array_agg(st.id order by coalesce(st.regno,st.email)) into ids from students st join enrollments e on e.student_id=st.id and e.subject_id=sid
    where not exists(select 1 from team_members m where m.subject_id=sid and m.student_id=st.id);
  if ids is null then raise exception 'Every student is already in a team'; end if;
  while i<=array_length(ids,1) loop
    if (i-1)%n=0 then tn:=tn+1; made:=made+1; insert into teams(subject_id,name) values(sid,'Team '||tn) returning id into nt; end if;
    insert into team_members(team_id,subject_id,student_id,leader) values(nt,sid,ids[i],(i-1)%n=0); i:=i+1;
  end loop;
  return made; end $$;

-- ---------- FORMATS (projects): templates the admin gives, Drive link ----------
create or replace function formats_get(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; begin r:=_access(t,sid);
  if r<>'admin' and _hid(sid,'formats') then return '[]'::json; end if;
  return (select coalesce(json_agg(f order by f.created_at desc),'[]') from (select id,title,note,link,visible,created_at from formats where subject_id=sid and (r='admin' or visible)) f); end $$;

create or replace function format_add(t text, sid uuid, ti text, nt text, lk text) returns void language plpgsql security definer set search_path=public as $$
declare cd text; begin perform _admin(t);
  if not _isproj(sid) then raise exception 'Formats are only for project subjects'; end if;
  if length(trim(coalesce(ti,'')))<1 then raise exception 'Enter a title'; end if;
  if length(coalesce(nt,''))>500 then raise exception 'The note is too long (500 characters)'; end if;
  insert into formats(subject_id,title,note,link) values(sid,trim(ti),nullif(trim(coalesce(nt,'')),''),_drive(lk));
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Format posted in '||cd);
  perform _notify_subject(sid,'format',cd||' · new format: '||trim(ti),null,'subject/'||cd||'/formats'); end $$;

create or replace function format_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from formats where id=i; end $$;

-- ---------- WORK posted by students / teams to the admin (Drive link only) ----------
create or replace function work_get(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; mt uuid; begin r:=_access(t,sid); k:=_s(t); mt:=_myteam(k.user_id,sid);
  return (select coalesce(json_agg(json_build_object('id',w.id,'kind',w.kind,'title',w.title,'link',w.link,'note',w.note,'created_at',w.created_at,'updated_at',w.updated_at,
      'student_id',w.student_id,'team_id',w.team_id,'team',(select name from teams where id=w.team_id),'by',st.name,'regno',st.regno,
      'mine',(r='student' and (w.student_id=k.user_id or (w.team_id is not null and w.team_id=mt)))) order by w.created_at desc),'[]')
    from work_posts w join students st on st.id=w.student_id
    where w.subject_id=sid and (r<>'student' or w.student_id=k.user_id or (mt is not null and w.team_id=mt))); end $$;

create or replace function work_add(t text, sid uuid, kd text, ti text, lk text, nt text) returns void language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  if k.role<>'student' then raise exception 'Only a student can post work'; end if;
  if not exists(select 1 from enrollments where student_id=k.user_id and subject_id=sid) then raise exception 'Not allowed'; end if;
  if coalesce(kd,'') not in ('Code','Report','PPT','Other') then raise exception 'Choose what you are posting: Code, Report, PPT or Other'; end if;
  if length(coalesce(nt,''))>500 then raise exception 'The note is too long (500 characters)'; end if;
  insert into work_posts(subject_id,team_id,student_id,kind,title,link,note)
    values(sid,_myteam(k.user_id,sid),k.user_id,kd,coalesce(nullif(trim(coalesce(ti,'')),''),kd),_drive(lk),nullif(trim(coalesce(nt,'')),'')); end $$;

create or replace function work_edit(t text, i uuid, kd text, ti text, lk text, nt text) returns void language plpgsql security definer set search_path=public as $$
declare k sessions; w work_posts; begin k:=_s(t);
  select * into w from work_posts where id=i; if w.id is null then raise exception 'Post not found'; end if;
  if k.role<>'student' or not (w.student_id=k.user_id or (w.team_id is not null and w.team_id=_myteam(k.user_id,w.subject_id))) then raise exception 'Not allowed'; end if;
  if coalesce(kd,'') not in ('Code','Report','PPT','Other') then raise exception 'Choose Code, Report, PPT or Other'; end if;
  if length(coalesce(nt,''))>500 then raise exception 'The note is too long (500 characters)'; end if;
  update work_posts set kind=kd, title=coalesce(nullif(trim(coalesce(ti,'')),''),kd), link=_drive(lk), note=nullif(trim(coalesce(nt,'')),''), updated_at=now() where id=i; end $$;

create or replace function work_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
declare k sessions; w work_posts; begin k:=_s(t);
  select * into w from work_posts where id=i; if w.id is null then raise exception 'Post not found'; end if;
  if k.role='admin' or (k.role='student' and (w.student_id=k.user_id or (w.team_id is not null and w.team_id=_myteam(k.user_id,w.subject_id)))) then delete from work_posts where id=i;
  else raise exception 'Not allowed'; end if; end $$;

create or replace function notice_add(t text, sid uuid, ti text, msg text, d text) returns void language plpgsql security definer set search_path=public as $$
declare cd text; begin perform _admin(t);
  if length(trim(coalesce(ti,'')))<1 then raise exception 'Enter a title'; end if;
  if length(coalesce(msg,''))>30000 then raise exception 'The notice is too long'; end if;
  insert into notices(subject_id,title,message,due_date,due_time)
    values(sid,trim(ti),nullif(trim(coalesce(msg,'')),''),nullif(trim(coalesce(d,'')),'')::date,null);
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Notice posted in '||cd);
  perform _notify_subject(sid,'notice',cd||' · '||trim(ti),null,'subject/'||cd||'/notices'); end $$;

-- admin: save the columns (create / rename / delete / formulas / maximum marks / description)
create or replace function marks_cols_save(t text, sid uuid, kd text, cols jsonb) returns void language plpgsql security definer set search_path=public as $$
declare sh uuid; keep text[]; c jsonb; ids text[]:='{}'; nm text; has_aat boolean:=false; begin perform _admin(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  if kd='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  if jsonb_typeof(cols)<>'array' or jsonb_array_length(cols)>60 then raise exception 'Too many columns (maximum 60)'; end if;
  for c in select * from jsonb_array_elements(cols) loop
    if jsonb_typeof(c)<>'object' then raise exception 'Wrong column data'; end if;
    if coalesce(c->>'id','') !~ '^[A-Za-z0-9]{1,20}$' or (c->>'id')=any(ids) then raise exception 'Wrong column id'; end if;
    ids:=ids||(c->>'id');
    nm:=btrim(coalesce(c->>'name',''));
    if length(nm) not between 1 and 40 or nm ~ '[\[\]]' then raise exception 'Column name: 1-40 characters, without [ or ]'; end if;
    if coalesce(c->>'type','') not in ('marks','formula') then raise exception 'Column type must be marks or formula'; end if;
    if c ? 'desc' and (jsonb_typeof(c->'desc')<>'string' or length(c->>'desc')>200) then raise exception 'Description of column "%" must be text of at most 200 characters', nm; end if;
    if c->>'type'='formula' then
      if coalesce(c->>'f','') !~ '^\s*=' then raise exception 'Formula of column "%" must start with =', nm; end if;
      if length(c->>'f')>300 then raise exception 'Formula of column "%" is too long (maximum 300 characters)', nm; end if;
      if (c->>'f') !~ '^[A-Za-z0-9_ \[\]()+\-*/^%,:.$<>=\"&]*$' then raise exception 'Formula of column "%" has a character that is not allowed', nm; end if;
    else
      if c ? 'max' and (jsonb_typeof(c->'max')<>'number' or (c->>'max')::numeric <= 0 or (c->>'max')::numeric > 1000) then
        raise exception 'Maximum marks of column "%" must be a number from 1 to 1000', nm; end if;
      if kd='theory' and lower(nm)='aat 1' then has_aat:=true; end if;
    end if;
  end loop;
  if kd='theory' and not has_aat then raise exception 'The column "AAT 1" is mandatory in Theory Marks'; end if;
  insert into mark_sheets(subject_id,kind,cols) values(sid,kd,cols)
    on conflict (subject_id,kind) do update set cols=excluded.cols, updated_at=now() returning id into sh;
  select array_agg(x->>'id') into keep from jsonb_array_elements(cols) x;       -- marks of deleted columns are removed
  update mark_values set vals=(select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(mark_values.vals) where key=any(coalesce(keep,'{}'))) where sheet_id=sh; end $$;

-- admin: save marks.  rw = [{student_id, vals:{colId:number or "AB"}}]   (only students of this subject)
create or replace function marks_save(t text, sid uuid, kd text, rw jsonb) returns int language plpgsql security definer set search_path=public as $$
declare sh uuid; x jsonb; n int:=0; cl jsonb; e record; begin perform _admin(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  insert into mark_sheets(subject_id,kind) values(sid,kd) on conflict (subject_id,kind) do nothing;
  select id, cols into sh, cl from mark_sheets where subject_id=sid and kind=kd;
  for x in select * from jsonb_array_elements(rw) loop
    if jsonb_typeof(x->'vals')<>'object' or length((x->'vals')::text)>6000 then raise exception 'Wrong marks data'; end if;
    for e in select key, value from jsonb_each(x->'vals') loop
      if jsonb_typeof(e.value)='string' then
        if upper(btrim(e.value#>>'{}'))<>'AB' then raise exception 'A mark must be a number or AB (absent)'; end if;
      elsif jsonb_typeof(e.value)<>'number' or (e.value#>>'{}')::numeric < 0 then raise exception 'Marks must be numbers (or AB), not negative';
      elsif exists(select 1 from jsonb_array_elements(coalesce(cl,'[]'::jsonb)) k where k->>'id'=e.key and k ? 'max' and (k->>'max')::numeric < (e.value#>>'{}')::numeric) then
        raise exception 'A mark is above the maximum marks of its column';
      end if;
    end loop;
    if exists(select 1 from enrollments where subject_id=sid and student_id=(x->>'student_id')::uuid) then
      insert into mark_values(sheet_id,student_id,vals) values(sh,(x->>'student_id')::uuid,x->'vals')
        on conflict (sheet_id,student_id) do update set vals=excluded.vals, updated_at=now(); n:=n+1; end if;
  end loop; return n; end $$;

-- admin: delete the marks of one student row
create or replace function marks_row_clear(t text, sid uuid, kd text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  delete from mark_values where student_id=i and sheet_id=(select id from mark_sheets where subject_id=sid and kind=kd); end $$;

-- admin: delete the whole sheet (columns + all marks)
create or replace function marks_sheet_del(t text, sid uuid, kd text) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from mark_sheets where subject_id=sid and kind=kd; end $$;

-- admin: Lab Marks row colors  (null = back to the default colors)
create or replace function marks_rules_save(t text, sid uuid, kd text, rc jsonb) returns void language plpgsql security definer set search_path=public as $$
declare x jsonb; froms numeric[]:='{}'; f numeric; begin perform _admin(t);
  if kd<>'lab' then raise exception 'Row colors are only for Lab Marks'; end if;
  if (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  if rc is not null and jsonb_typeof(rc)<>'null' then
    if jsonb_typeof(rc)<>'object' or coalesce(jsonb_typeof(rc->'on'),'')<>'boolean' then raise exception 'Wrong color data'; end if;
    if coalesce(rc->>'col','') !~ '^[A-Za-z0-9]{1,20}$' then raise exception 'Choose the column that decides the color'; end if;
    if coalesce(jsonb_typeof(rc->'rows'),'')<>'array' then raise exception 'Give 1 to 10 color ranges'; end if;
    if jsonb_array_length(rc->'rows') not between 1 and 10 then raise exception 'Give 1 to 10 color ranges'; end if;
    for x in select * from jsonb_array_elements(rc->'rows') loop
      if jsonb_typeof(x)<>'object' then raise exception 'Wrong color data'; end if;
      if coalesce(jsonb_typeof(x->'from'),'')<>'number' then raise exception 'Every color range needs a "from" number'; end if;
      f:=(x->>'from')::numeric;
      if f<0 or f>1000 then raise exception 'A "from" mark must be between 0 and 1000'; end if;
      if f=any(froms) then raise exception 'Two color ranges start at the same mark (%)', f; end if;
      froms:=froms||f;
      if coalesce(x->>'color','') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'A color must look like #16a34a'; end if;
    end loop;
  else rc:=null; end if;
  insert into mark_sheets(subject_id,kind,row_colors) values(sid,kd,rc)
    on conflict (subject_id,kind) do update set row_colors=excluded.row_colors, updated_at=now(); end $$;

     -- the website can only use the functions below
-- read: admin / CR = every student of the subject that is in a batch;  student = only his / her own batch
create or replace function batches_get(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; begin r:=_access(t,sid); k:=_s(t);
  return json_build_object(
    'colors',coalesce((select batch_colors from subjects where id=sid),'{}'::jsonb),
    'rows',(select coalesce(json_agg(json_build_object('student_id',m.student_id,'regno',coalesce(s.regno,s.email),'batch',m.batch) order by s.regno),'[]')
        from lab_batch_members m join students s on s.id=m.student_id
        join enrollments e on e.student_id=m.student_id and e.subject_id=sid
        where m.subject_id=sid and (r in ('admin','cr') or m.student_id=k.user_id))); end $$;

-- admin: save the batches.  rw = [{student_id, batch:1|2}]  (ALL students that are in a batch; the rest are in none)
--                           colors = {"1":"#rrggbb","2":"#rrggbb"}  (or null = keep the colors as they are)
create or replace function batches_save(t text, sid uuid, rw jsonb, colors jsonb) returns int language plpgsql security definer set search_path=public as $$
declare x jsonb; n int:=0; cd text; begin perform _admin(t);
  if (select kind from subjects where id=sid)<>'lab' then raise exception 'Batches are only for Theory + Lab subjects'; end if;
  if jsonb_typeof(rw)<>'array' then raise exception 'Wrong batch data'; end if;
  if colors is not null and jsonb_typeof(colors)<>'null' then
    if jsonb_typeof(colors)<>'object' or coalesce(colors->>'1','') !~ '^#[0-9A-Fa-f]{6}$' or coalesce(colors->>'2','') !~ '^#[0-9A-Fa-f]{6}$' then
      raise exception 'A batch color must look like #2563eb'; end if;
    update subjects set batch_colors=jsonb_build_object('1',colors->>'1','2',colors->>'2') where id=sid;
  end if;
  delete from lab_batch_members where subject_id=sid;
  for x in select * from jsonb_array_elements(rw) loop
    if coalesce(x->>'batch','') not in ('1','2') then raise exception 'The batch must be 1 or 2'; end if;
    if exists(select 1 from enrollments where subject_id=sid and student_id=(x->>'student_id')::uuid) then
      insert into lab_batch_members(subject_id,student_id,batch) values(sid,(x->>'student_id')::uuid,(x->>'batch')::smallint)
        on conflict (subject_id,student_id) do update set batch=excluded.batch; n:=n+1; end if;
  end loop;
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Lab batches saved in '||cd);
  return n; end $$;

-- subject_content: same as before; only 'labs' changed (a student sees his / her batch + the old lab programs without a batch)
create or replace function subject_content(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; mb smallint; hid text[]; begin r:=_access(t,sid); k:=_s(t);
  if r='student' then select batch into mb from lab_batch_members where subject_id=sid and student_id=k.user_id; end if;
  select hidden_tabs into hid from subjects where id=sid;                          -- v41: tabs switched off by the admin (visible = false)
  return json_build_object('role',r,'tasks',(select count(*) from tasks where subject_id=sid and (r='admin' or (visible and not ('tasks'=any(hid))))),
    'subject',(select json_build_object('id',id,'code',code,'name',name,'year',year,'full_name',full_name,'kind',kind,'hidden_tabs',hidden_tabs) from subjects where id=sid),
    'materials',(select coalesce(json_agg(json_build_object('id',m.id,'category',m.category,'title',m.title,'link',m.link,'visible',m.visible,'created_at',m.created_at)
        order by array_position(array['Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks'],m.category), m.created_at),'[]') from materials m
        where m.subject_id=sid and (r='admin' or (m.visible and not (_mat_tab(m.category)=any(hid))))),
    'videos',(select coalesce(json_agg(v order by v.created_at desc),'[]') from videos v where v.subject_id=sid and (r='admin' or (v.visible and not ('videos'=any(hid))))),
    'notices',(select coalesce(json_agg(n order by n.created_at desc),'[]') from notices n where n.subject_id=sid and (r='admin' or (n.visible and not ('notices'=any(hid))))),
    'labs',(select coalesce(json_agg(l order by l.lab_date nulls last, l.lab_time nulls last, l.created_at),'[]') from labs l
        where l.subject_id=sid and (r<>'student' or l.batch is null or l.batch=mb) and (r='admin' or (l.visible and not ('labs'=any(hid))))),
    'admin',(select json_build_object('name',coalesce(nullif(name,''),'Admin'),'photo',photo) from admins order by username limit 1),
    'crs',(select coalesce(json_agg(json_build_object('name',coalesce(nullif(c.name,''),c.username),'photo',c.photo) order by c.username),'[]') from crs c join cr_subjects x on x.cr_id=c.id where x.subject_id=sid)); end $$;

create or replace function lab_add(t text, sid uuid, ex text, ti text, task text, prog text, d text, slot text, loc text, lk text, bt int) returns void language plpgsql security definer set search_path=public as $$
declare cd text; n text; begin perform _admin(t);
  if (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab programs are only for Theory + Lab subjects'; end if;
  if bt is null or bt not in (1,2) then raise exception 'Choose the batch (Batch 1 or Batch 2)'; end if;
  if not exists(select 1 from lab_batch_members m join enrollments e on e.student_id=m.student_id and e.subject_id=sid where m.subject_id=sid and m.batch=bt) then
    raise exception 'Batch % has no students yet. Create the batches first.', bt; end if;
  n:=nullif(trim(coalesce(ex,'')),'');
  if n is null then raise exception 'Choose the lab number'; end if;
  if length(n)>10 then raise exception 'Lab number is too long'; end if;
  if coalesce(trim(prog),'')='' and coalesce(trim(lk),'')='' then raise exception 'Add a Drive link or paste the code (at least one of the two)'; end if;
  if coalesce(trim(lk),'')<>'' and trim(lk) !~* '^https?://\S+$' then raise exception 'The link must start with https://'; end if;
  if length(coalesce(prog,''))>30000 then raise exception 'The code is too long (use a Drive link)'; end if;
  insert into labs(subject_id,exp_no,title,task,program,lab_date,lab_time,link,slot,location,batch)
    values(sid,n,coalesce(nullif(trim(ti),''),'Lab '||n),nullif(trim(task),''),nullif(trim(prog),''),nullif(trim(coalesce(d,'')),'')::date,null,nullif(trim(lk),''),nullif(trim(slot),''),nullif(trim(loc),''),bt);
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Lab program posted in '||cd||' for batch '||bt);
  insert into notifications(role,user_id,subject_id,kind,title,body,link)           -- bell: only the students of that batch + the CRs
    select 'student', m.student_id, sid, 'lab', cd||' · Lab '||n||' (Batch '||bt||')', nullif(trim(task),''), 'subject/'||cd||'/labs'
      from lab_batch_members m join enrollments e on e.student_id=m.student_id and e.subject_id=sid where m.subject_id=sid and m.batch=bt
    union all select 'cr', c.cr_id, sid, 'lab', cd||' · Lab '||n||' (Batch '||bt||')', nullif(trim(task),''), 'subject/'||cd||'/labs' from cr_subjects c where c.subject_id=sid; end $$;

create or replace function marks_get(t text, sid uuid, kd text) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; sh mark_sheets; show boolean; begin r:=_access(t,sid); k:=_s(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  if kd='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  select * into sh from mark_sheets where subject_id=sid and mark_sheets.kind=kd;
  show := (r='admin') or (coalesce(sh.published,false) and not _hid(sid, case when kd='lab' then 'labsheet' else 'marks' end));                            -- students and CR: only after Publish
  return json_build_object('published',coalesce(sh.published,false),
    'cols',case when show then coalesce(sh.cols,'[]'::jsonb) else '[]'::jsonb end,'row_colors',case when show then sh.row_colors else null end,
    'rows',case when not show then '[]'::json else (select coalesce(json_agg(json_build_object('student_id',s.id,'regno',coalesce(s.regno,s.email),'name',s.name,'vals',coalesce(v.vals,'{}'::jsonb)) order by s.regno),'[]')
        from students s join enrollments e on e.student_id=s.id and e.subject_id=sid
        left join mark_values v on v.student_id=s.id and v.sheet_id=sh.id
        where r in ('admin','cr') or s.id=k.user_id) end); end $$;

create or replace function marks_publish(t text, sid uuid, kd text, pub boolean) returns void language plpgsql security definer set search_path=public as $$
declare was boolean; cd text; begin perform _admin(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  if kd='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  insert into mark_sheets(subject_id,kind) values(sid,kd) on conflict (subject_id,kind) do nothing;
  select published into was from mark_sheets where subject_id=sid and kind=kd;
  update mark_sheets set published=coalesce(pub,false), updated_at=now() where subject_id=sid and kind=kd;
  if coalesce(pub,false) and not was then
    select code into cd from subjects where id=sid;
    perform _notify_subject(sid,'marks',cd||' · '||case when kd='lab' then 'Lab Marks' else 'Theory Marks' end||' published','Your marks are now available.',
      'subject/'||cd||'/'||case when kd='lab' then 'labsheet' else 'marks' end);
  end if; end $$;

    -- the website can only use the functions below
create or replace function timetable_get(t text, yr int default null, sm int default null) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; s students; x timetables; begin k:=_s(t);
  if k.role='student' then
    select * into s from students where id=k.user_id; yr:=s.year; sm:=s.semester;
    select * into x from timetables where year=yr and (sm is null or semester=sm) order by semester desc limit 1;
  else
    select * into x from timetables where year=yr and semester=sm;
  end if;
  return json_build_object('year',coalesce(x.year,yr),'semester',coalesce(x.semester,sm),'data',x.data,
    'list',case when k.role='student' then '[]'::json else (select coalesce(json_agg(json_build_object('year',year,'semester',semester) order by year,semester),'[]') from timetables) end); end $$;

create or replace function timetable_save(t text, yr int, sm int, d jsonb) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  if yr is null or yr not between 1 and 4 or sm is null or sm not between 1 and 8 then raise exception 'Choose the year (1-4) and the semester (1-8)'; end if;
  if jsonb_typeof(d)<>'object' or length(d::text)>40000 then raise exception 'Wrong timetable data'; end if;
  insert into timetables(year,semester,data) values(yr,sm,d) on conflict (year,semester) do update set data=excluded.data, updated_at=now(); end $$;

create or replace function timetable_del(t text, yr int, sm int) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from timetables where year=yr and semester=sm; end $$;


-- ===================================================== EXAMS (functions) v40 =====================================================
-- old versions with other argument lists are removed first (otherwise the database sees two functions with one name)
drop function if exists exam_create(text,uuid,text,text,int,text,text,int,jsonb);
drop function if exists exam_update(text,uuid,text,text,int,text,text,int,jsonb);
drop function if exists exam_save(text,uuid,jsonb,jsonb,int);
drop function if exists exam_submit(text,uuid,jsonb,jsonb,int,text);
drop function if exists _q_eval(text,text,numeric,text);

create or replace function _exam_code() returns text language plpgsql security definer set search_path=public as $$
declare c text; begin
  loop c:='EX-'||upper(substr(md5(random()::text||clock_timestamp()::text),1,6)); exit when not exists(select 1 from exams where code=c); end loop;
  return c; end $$;

-- marks of ONE question.  res = correct | partial | wrong | skip,  pts = marks got (negative for a wrong answer)
-- mcq = one right option;  msq = several right options (all right = full marks, only right ones picked = partial marks if allowed, any wrong one = negative);  num = number;  fill = text
create or replace function _q_score(kd text, ans text, tol numeric, given text, mk numeric, ng numeric, pt boolean) returns table(res text, pts numeric) language plpgsql immutable as $$
declare g text; a text; ok boolean:=false; ga text[]; aa text[]; begin
  g:=btrim(coalesce(given,''));
  if g='' then return query select 'skip'::text, 0::numeric; return; end if;
  if kd='mcq' then
    if upper(g)=upper(btrim(ans)) then return query select 'correct'::text, mk; else return query select 'wrong'::text, -ng; end if; return; end if;
  if kd='msq' then
    ga:=(select coalesce(array_agg(distinct x order by x),'{}') from regexp_split_to_table(upper(regexp_replace(g,'[^A-Fa-f]','','g')),'') x where x<>'');
    aa:=(select coalesce(array_agg(distinct x order by x),'{}') from regexp_split_to_table(upper(regexp_replace(ans,'[^A-Fa-f]','','g')),'') x where x<>'');
    if cardinality(ga)=0 then return query select 'skip'::text, 0::numeric;
    elsif ga=aa then return query select 'correct'::text, mk;
    elsif pt and ga <@ aa then return query select 'partial'::text, round(mk*cardinality(ga)/cardinality(aa),2);
    else return query select 'wrong'::text, -ng; end if; return; end if;
  if kd='num' then
    if length(g)>20 or g !~ '^[-+]?[0-9]*\.?[0-9]+$' then return query select 'wrong'::text, -ng; return; end if;
    if abs(g::numeric-btrim(ans)::numeric)<=coalesce(tol,0)+0.0000001 then return query select 'correct'::text, mk; else return query select 'wrong'::text, -ng; end if; return; end if;
  g:=lower(regexp_replace(g,'\s+',' ','g'));
  foreach a in array string_to_array(ans,'|') loop
    if g=lower(regexp_replace(btrim(a),'\s+',' ','g')) then ok:=true; end if; end loop;
  if ok then return query select 'correct'::text, mk; else return query select 'wrong'::text, -ng; end if; end $$;

-- ----- option shuffling helpers.  perm = [original index shown 1st, shown 2nd, ...]  (stored per student and per question) -----
-- the letters the student saw (A,B,C..) -> the letters of the ORIGINAL options (sorted, no comma)
create or replace function _unperm(given text, perm jsonb) returns text language plpgsql immutable as $$
declare c text; r text:=''; i int; begin
  if perm is null or jsonb_typeof(perm)<>'array' then return given; end if;
  for c in select regexp_split_to_table(upper(coalesce(given,'')),'') loop
    if c ~ '^[A-F]$' then i:=ascii(c)-65; if i<jsonb_array_length(perm) then r:=r||chr(65+(perm->>i)::int); end if; end if; end loop;
  return coalesce((select string_agg(x,'' order by x) from (select distinct x from regexp_split_to_table(r,'') x where x<>'') y),''); end $$;

-- options in the order this student saw them
create or replace function _disp_opts(opts jsonb, perm jsonb) returns jsonb language sql immutable as $$
  select case when opts is null or perm is null then opts
    else (select jsonb_agg(opts->(p.v::int) order by p.ord) from jsonb_array_elements_text(perm) with ordinality p(v,ord)) end $$;

-- the right answer as letters of the shuffled options (A / A,C)
create or replace function _disp_ans(ans text, perm jsonb) returns text language sql immutable as $$
  select case when perm is null then ans
    else coalesce((select string_agg(chr(64+p.ord::int),',' order by p.ord) from jsonb_array_elements_text(perm) with ordinality p(v,ord) where position(chr(65+p.v::int) in upper(ans))>0),'') end $$;

-- keep the bigger number per key (time spent per question only grows)
create or replace function _merge_max(old jsonb, nw jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(k, to_jsonb(greatest(
      case when coalesce(old->>k,'') ~ '^[0-9]{1,6}(\.[0-9]+)?$' then (old->>k)::numeric else 0 end,
      case when coalesce(nw->>k,'')  ~ '^[0-9]{1,6}(\.[0-9]+)?$' then (nw->>k)::numeric else 0 end))),'{}'::jsonb)
  from (select jsonb_object_keys(case when jsonb_typeof(coalesce(old,'{}'::jsonb))='object' then coalesce(old,'{}'::jsonb) else '{}'::jsonb end) k
        union select jsonb_object_keys(case when jsonb_typeof(coalesce(nw,'{}'::jsonb))='object' then coalesce(nw,'{}'::jsonb) else '{}'::jsonb end)) z
  where k ~ '^[0-9a-f-]{36}$' $$;

-- the warning log: [{at, why}].  The longer list from the student's page replaces the stored one.
create or replace function _vlog_merge(old jsonb, nw jsonb) returns jsonb language sql immutable as $$
  select case when nw is null or jsonb_typeof(nw)<>'array' then coalesce(old,'[]'::jsonb)
    else case when jsonb_array_length(nw)<=jsonb_array_length(coalesce(old,'[]'::jsonb)) or jsonb_array_length(nw)>100 then coalesce(old,'[]'::jsonb)
      else (select coalesce(jsonb_agg(jsonb_build_object('at',left(coalesce(z->>'t',''),40),'why',left(coalesce(z->>'w',''),160))),'[]'::jsonb) from jsonb_array_elements(nw) z) end end $$;

-- the paper of ONE attempt in the order that student saw: section, then the shuffled order.  Contains the answers -> NEVER callable from the website (revoked below)
create or replace function _exam_paper(aid uuid) returns table(id uuid, spos int, sname text, kind text, question text, image_url text, options jsonb, d_options jsonb, answer text, tolerance numeric, explanation text, mk numeric, ng numeric, pt boolean, n int, perm jsonb)
language sql stable security definer set search_path=public as $$
  select q.id, x.pos, x.name, q.kind, q.question, q.image_url, q.options, _disp_opts(q.options, pp.pm), q.answer, q.tolerance, q.explanation,
         coalesce(q.marks,x.marks), coalesce(q.negative,x.negative), q.partial,
         (row_number() over (order by x.pos, coalesce(o.ord,100000+q.pos), q.pos))::int, pp.pm
  from exam_attempts a
  join exam_questions q on q.exam_id=a.exam_id
  join exam_sections x on x.id=q.section_id
  left join lateral (select t.ord from jsonb_array_elements_text(case when jsonb_typeof(a.qorder->(x.pos::text))='array' then a.qorder->(x.pos::text) else '[]'::jsonb end) with ordinality t(v,ord) where t.v=q.id::text) o on true
  cross join lateral (select case when jsonb_typeof(a.perm->(q.id::text))='array' then
        case when jsonb_array_length(a.perm->(q.id::text))=coalesce(jsonb_array_length(case when jsonb_typeof(q.options)='array' then q.options end),-1) then a.perm->(q.id::text) end end pm) pp
  where a.id=aid
  order by 15 $$;

create or replace function _exam_total(eid uuid) returns numeric language sql stable security definer set search_path=public as $$
  select coalesce(sum(coalesce((select sum(coalesce(q.marks,s.marks)) from exam_questions q where q.section_id=s.id),0)
    + greatest(s.q_count-(select count(*) from exam_questions q where q.section_id=s.id),0)*s.marks),0) from exam_sections s where s.exam_id=eid $$;

-- marks of one attempt
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

create or replace function _exam_regrade(eid uuid) returns void language plpgsql security definer set search_path=public as $$
declare r record; begin for r in select id from exam_attempts where exam_id=eid and status<>'in_progress' loop perform _exam_grade(r.id); end loop; end $$;

-- the end of the writing time of an attempt: start + duration + extra time (a student who was allowed late has no window limit);  an admin "extra time" (resume_until) can only make it later
create or replace function _exam_deadline(aid uuid) returns timestamptz language sql stable security definer set search_path=public as $$
  select greatest(
    least(a.started_at+((e.duration_min+a.extra_min)||' minutes')::interval,
          case when a.bypass then 'infinity'::timestamptz else coalesce(e.ends_at,'infinity'::timestamptz)+(a.extra_min||' minutes')::interval end),
    coalesce(a.resume_until,'-infinity'::timestamptz))
  from exam_attempts a join exams e on e.id=a.exam_id where a.id=aid $$;

-- earliest minute a student may press Submit (default: half of the duration)
create or replace function _exam_min_submit(eid uuid) returns int language sql stable security definer set search_path=public as $$
  select coalesce(min_submit_min, duration_min/2) from exams where id=eid $$;

create or replace function _exam_finish(aid uuid, st text) returns void language plpgsql security definer set search_path=public as $$
begin update exam_attempts set status=st, submitted_at=now() where id=aid and status='in_progress'; perform _exam_grade(aid); end $$;

-- when the attempt is created: the shuffled order of questions (per section) and of the options (per question)
create or replace function _exam_init(aid uuid) returns void language plpgsql security definer set search_path=public as $$
declare a exam_attempts; e exams; r record; pm jsonb:='{}'; qo jsonb:='{}'; fp int; begin
  select * into a from exam_attempts where id=aid; select * into e from exams where id=a.exam_id;
  for r in select x.pos, (select jsonb_agg(q.id order by case when e.shuffle then random() else q.pos end) from exam_questions q where q.section_id=x.id) ids from exam_sections x where x.exam_id=e.id loop
    qo:=qo||jsonb_build_object(r.pos::text, coalesce(r.ids,'[]'::jsonb)); end loop;
  if e.shuffle then
    for r in select q.id, jsonb_array_length(q.options) n from exam_questions q where q.exam_id=e.id and q.kind in ('mcq','msq') and jsonb_typeof(q.options)='array' loop
      pm:=pm||jsonb_build_object(r.id::text,(select jsonb_agg(i order by random()) from generate_series(0,r.n-1) i)); end loop; end if;
  select min(pos) into fp from exam_sections where exam_id=e.id;
  update exam_attempts set perm=pm, qorder=qo,
    sec=case when e.lock_sections then jsonb_build_object('cur',fp,'st',jsonb_build_object(fp::text,now()),'done','[]'::jsonb) else '{}'::jsonb end where id=aid; end $$;

-- sectional exams (sections one by one, no going back, optional time per section): close the sections whose time is over.  Finishes the exam after the last one.
create or replace function _exam_sync(aid uuid) returns void language plpgsql security definer set search_path=public as $$
declare a exam_attempts; e exams; s jsonb; cp int; sx exam_sections; st timestamptz; nx int; changed boolean:=false; n int:=0; begin
  select * into a from exam_attempts where id=aid; select * into e from exams where id=a.exam_id;
  if not e.lock_sections or a.status<>'in_progress' then return; end if;
  s:=a.sec; if s is null or s='{}'::jsonb then return; end if;
  loop n:=n+1; exit when n>20;
    cp:=(s->>'cur')::int; exit when cp is null;
    select * into sx from exam_sections where exam_id=e.id and pos=cp;
    exit when sx.time_min is null;
    st:=(s->'st'->>(cp::text))::timestamptz;
    exit when now()<=st+(sx.time_min||' minutes')::interval;
    select min(pos) into nx from exam_sections where exam_id=e.id and pos>cp;
    s:=jsonb_set(s,'{done}',coalesce(s->'done','[]'::jsonb)||to_jsonb(cp)); changed:=true;
    if nx is null then s:=jsonb_set(s,'{cur}','null'::jsonb); exit; end if;
    s:=jsonb_set(s,'{cur}',to_jsonb(nx)); s:=jsonb_set(s,'{st}',(s->'st')||jsonb_build_object(nx::text, st+(sx.time_min||' minutes')::interval));
  end loop;
  if changed then update exam_attempts set sec=s where id=aid; end if;
  if (s->>'cur') is null then perform _exam_finish(aid,'auto_time'); end if; end $$;

create or replace function _exam_secinfo(aid uuid) returns json language plpgsql security definer set search_path=public as $$
declare a exam_attempts; e exams; sx exam_sections; cp int; rem int; begin
  select * into a from exam_attempts where id=aid; select * into e from exams where id=a.exam_id;
  if not e.lock_sections then return json_build_object('lock',false); end if;
  cp:=(a.sec->>'cur')::int; select * into sx from exam_sections where exam_id=e.id and pos=cp;
  if sx.time_min is not null then rem:=greatest(0,extract(epoch from ((a.sec->'st'->>(cp::text))::timestamptz+(sx.time_min||' minutes')::interval-now()))::int); end if;
  return json_build_object('lock',true,'cur',cp,'name',sx.name,'time_min',sx.time_min,'remaining',rem,'last',not exists(select 1 from exam_sections where exam_id=e.id and pos>cp)); end $$;

-- the questions the student may see (section sp, or every section when sp is null) - with the options already shuffled, NO answers
create or replace function _exam_qs(aid uuid, sp int) returns json language sql stable security definer set search_path=public as $$
  select coalesce(json_agg(json_build_object('id',p.id,'no',p.n,'section',p.spos,'kind',p.kind,'question',p.question,'image',p.image_url,'options',p.d_options,'marks',p.mk,'negative',p.ng,'partial',p.pt) order by p.n),'[]'::json)
  from _exam_paper(aid) p where sp is null or p.spos=sp $$;

-- in a sectional exam only the answers of the CURRENT section can change; closed sections keep what was saved
create or replace function _exam_merge(aid uuid, newj jsonb, oldj jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare e exams; a exam_attempts; cp int; ids text[]; begin
  select * into a from exam_attempts where id=aid; select * into e from exams where id=a.exam_id;
  newj:=case when jsonb_typeof(newj)='object' then newj else '{}'::jsonb end; oldj:=case when jsonb_typeof(oldj)='object' then oldj else '{}'::jsonb end;
  if not e.lock_sections then return newj; end if;
  cp:=(a.sec->>'cur')::int;
  select coalesce(array_agg(q.id::text),'{}') into ids from exam_questions q join exam_sections x on x.id=q.section_id where q.exam_id=e.id and x.pos=cp;
  return coalesce((select jsonb_object_agg(k,v) from (select key k, value v from jsonb_each(oldj) where not key=any(ids) union all select key, value from jsonb_each(newj) where key=any(ids)) z),'{}'::jsonb); end $$;

-- add (qid null) or change one question.
-- x = {section, kind, question, image, options[], answer, tolerance, marks, negative, partial, explanation}   marks / negative empty = the section's marks
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

-- admin: create an exam.   secs = [{name, q_count, marks, negative, time_min}]   opt = {shuffle, lock, minsub}
-- The exam date is compulsory: it can be started only between "opens" and "closes".
create or replace function exam_create(t text, sid uuid, ti text, ins text, dur int, st text, en text, mv int, secs jsonb, opt jsonb) returns json language plpgsql security definer set search_path=public as $$
declare x jsonb; i int:=0; tot int:=0; eid uuid; cd text; s1 timestamptz; e1 timestamptz; sh boolean; lk boolean; ms int; tsum int:=0; tn int:=0; begin perform _admin(t);
  if length(trim(coalesce(ti,'')))<2 then raise exception 'Enter the exam title'; end if;
  mv:=coalesce(mv,3); if mv not between 1 and 20 then raise exception 'Allowed warnings must be 1 to 20'; end if;
  if length(coalesce(ins,''))>5000 then raise exception 'The instructions are too long'; end if;
  s1:=nullif(btrim(coalesce(st,'')),'')::timestamptz; e1:=nullif(btrim(coalesce(en,'')),'')::timestamptz;
  if s1 is null or e1 is null then raise exception 'Set the exam date: the time it opens and the time it closes'; end if;
  if e1<=s1 then raise exception 'The end time must be after the start time'; end if;
  if jsonb_typeof(secs)<>'array' or jsonb_array_length(secs) not between 1 and 10 then raise exception 'An exam needs 1 to 10 sections'; end if;
  for x in select * from jsonb_array_elements(secs) loop
    if coalesce(x->>'q_count','') !~ '^[0-9]{1,3}$' or (x->>'q_count')::int not between 1 and 200 then raise exception 'Questions in a section: 1 to 200'; end if;
    if coalesce(x->>'marks','') !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' or (x->>'marks')::numeric<=0 then raise exception 'Marks for a correct answer must be more than 0'; end if;
    if coalesce(x->>'negative','0') !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' then raise exception 'Negative marks must be 0 or more'; end if;
    if nullif(btrim(coalesce(x->>'time_min','')),'') is not null then
      if btrim(x->>'time_min') !~ '^[0-9]{1,3}$' or (x->>'time_min')::int not between 1 and 600 then raise exception 'Time of a section: 1 to 600 minutes'; end if; tsum:=tsum+(x->>'time_min')::int; tn:=tn+1; end if;
    tot:=tot+(x->>'q_count')::int; end loop;
  if tot>300 then raise exception 'An exam can have 300 questions at most'; end if;
  sh:=coalesce((opt->>'shuffle')::boolean,true); lk:=coalesce((opt->>'lock')::boolean,false) or tn>0;
  if lk and tn=jsonb_array_length(secs) then dur:=tsum; end if;
  if coalesce(dur,0) not between 1 and 600 then raise exception 'Duration must be 1 to 600 minutes'; end if;
  if e1-s1 < (dur||' minutes')::interval then raise exception 'The time between "opens" and "closes" must be at least the duration (% minutes)', dur; end if;
  ms:=nullif(btrim(coalesce(opt->>'minsub','')),'')::int;
  if ms is not null and ms not between 0 and dur then raise exception 'The earliest submit time must be between 0 and % minutes', dur; end if;
  cd:=_exam_code();
  insert into exams(code,subject_id,title,instructions,duration_min,starts_at,ends_at,max_violations,shuffle,lock_sections,min_submit_min)
    values(cd,sid,trim(ti),nullif(trim(coalesce(ins,'')),''),dur,s1,e1,mv,sh,lk,ms) returning id into eid;
  for x in select * from jsonb_array_elements(secs) loop i:=i+1;
    insert into exam_sections(exam_id,pos,name,q_count,marks,negative,time_min) values(eid,i,coalesce(nullif(btrim(x->>'name'),''),'Section '||i),(x->>'q_count')::int,(x->>'marks')::numeric,coalesce(nullif(x->>'negative',''),'0')::numeric,nullif(btrim(coalesce(x->>'time_min','')),'')::int); end loop;
  insert into activity(msg) values('Exam '||cd||' created in '||(select code from subjects where id=sid));
  return json_build_object('id',eid,'code',cd); end $$;

create or replace function exam_update(t text, eid uuid, ti text, ins text, dur int, st text, en text, mv int, secs jsonb, opt jsonb) returns void language plpgsql security definer set search_path=public as $$
declare x jsonb; p int; s1 timestamptz; e1 timestamptz; att boolean; sh boolean; lk boolean; ms int; tsum int:=0; tn int:=0; tc int:=0; begin perform _admin(t);
  if not exists(select 1 from exams where id=eid) then raise exception 'Exam not found'; end if;
  att:=exists(select 1 from exam_attempts where exam_id=eid);
  if length(trim(coalesce(ti,'')))<2 then raise exception 'Enter the exam title'; end if;
  if coalesce(mv,0) not between 1 and 20 then raise exception 'Allowed warnings must be 1 to 20'; end if;
  s1:=nullif(btrim(coalesce(st,'')),'')::timestamptz; e1:=nullif(btrim(coalesce(en,'')),'')::timestamptz;
  if s1 is null or e1 is null then raise exception 'Set the exam date: the time it opens and the time it closes'; end if;
  if e1<=s1 then raise exception 'The end time must be after the start time'; end if;
  for x in select * from jsonb_array_elements(coalesce(secs,'[]'::jsonb)) loop tc:=tc+1;
    if coalesce(x->>'q_count','') !~ '^[0-9]{1,3}$' or (x->>'q_count')::int not between 1 and 200 then raise exception 'Questions in a section: 1 to 200'; end if;
    if coalesce(x->>'marks','') !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' or (x->>'marks')::numeric<=0 then raise exception 'Marks for a correct answer must be more than 0'; end if;
    if coalesce(x->>'negative','0') !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' then raise exception 'Negative marks must be 0 or more'; end if;
    if nullif(btrim(coalesce(x->>'time_min','')),'') is not null then
      if btrim(x->>'time_min') !~ '^[0-9]{1,3}$' or (x->>'time_min')::int not between 1 and 600 then raise exception 'Time of a section: 1 to 600 minutes'; end if; tsum:=tsum+(x->>'time_min')::int; tn:=tn+1; end if;
    p:=(x->>'pos')::int;
    if att and exists(select 1 from exam_sections where exam_id=eid and pos=p and q_count<>(x->>'q_count')::int) then raise exception 'Students already attempted this exam. The number of questions cannot change.'; end if;
  end loop;
  sh:=coalesce((opt->>'shuffle')::boolean,true); lk:=coalesce((opt->>'lock')::boolean,false) or tn>0;
  if att and exists(select 1 from exams where id=eid and (lock_sections<>lk or shuffle<>sh)) then raise exception 'Students already attempted this exam. Shuffle and sectional mode cannot change now.'; end if;
  if lk and tn=tc and tc>0 then dur:=tsum; end if;
  if coalesce(dur,0) not between 1 and 600 then raise exception 'Duration must be 1 to 600 minutes'; end if;
  if e1-s1 < (dur||' minutes')::interval then raise exception 'The time between "opens" and "closes" must be at least the duration (% minutes)', dur; end if;
  ms:=nullif(btrim(coalesce(opt->>'minsub','')),'')::int;
  if ms is not null and ms not between 0 and dur then raise exception 'The earliest submit time must be between 0 and % minutes', dur; end if;
  update exams set title=trim(ti), instructions=nullif(trim(coalesce(ins,'')),''), duration_min=dur, starts_at=s1, ends_at=e1, max_violations=mv, shuffle=sh, lock_sections=lk, min_submit_min=ms where id=eid;
  for x in select * from jsonb_array_elements(coalesce(secs,'[]'::jsonb)) loop
    p:=(x->>'pos')::int;
    update exam_sections set name=coalesce(nullif(btrim(x->>'name'),''),name), q_count=(x->>'q_count')::int, marks=(x->>'marks')::numeric, negative=coalesce(nullif(x->>'negative',''),'0')::numeric,
      time_min=nullif(btrim(coalesce(x->>'time_min','')),'')::int where exam_id=eid and pos=p;
  end loop;
  if att then perform _exam_regrade(eid); end if; end $$;

create or replace function exam_questions_save(t text, eid uuid, qs jsonb) returns json language plpgsql security definer set search_path=public as $$
declare x jsonb; n int:=0; begin perform _admin(t);
  if not exists(select 1 from exams where id=eid) then raise exception 'Exam not found'; end if;
  if exists(select 1 from exam_attempts where exam_id=eid) then raise exception 'Students already attempted this exam. Edit single questions instead.'; end if;
  if jsonb_typeof(qs)<>'array' then raise exception 'No questions received'; end if;
  if jsonb_array_length(qs)>500 then raise exception 'At most 500 questions can be uploaded'; end if;
  delete from exam_questions where exam_id=eid;
  for x in select * from jsonb_array_elements(qs) loop perform _exam_q_put(eid,null,x); n:=n+1; end loop;
  return json_build_object('saved',n,'total_marks',_exam_total(eid)); end $$;

create or replace function exam_question_save(t text, eid uuid, qid uuid, q jsonb) returns uuid language plpgsql security definer set search_path=public as $$
declare nid uuid; begin perform _admin(t);
  nid:=_exam_q_put(eid,qid,q);
  if exists(select 1 from exam_attempts where exam_id=eid) then perform _exam_regrade(eid); end if;
  return nid; end $$;

create or replace function exam_question_del(t text, qid uuid) returns void language plpgsql security definer set search_path=public as $$
declare eid uuid; begin perform _admin(t);
  select exam_id into eid from exam_questions where id=qid; if eid is null then raise exception 'Question not found'; end if;
  if exists(select 1 from exam_attempts where exam_id=eid) then raise exception 'Students already attempted this exam. A question cannot be deleted now.'; end if;
  delete from exam_questions where id=qid; end $$;

create or replace function exam_publish(t text, eid uuid, st text) returns void language plpgsql security definer set search_path=public as $$
declare e exams; r record; bad text:=''; cd text; begin perform _admin(t);
  select * into e from exams where id=eid; if e.id is null then raise exception 'Exam not found'; end if;
  if st not in ('draft','published','closed') then raise exception 'Wrong status'; end if;
  if st='published' then
    if e.starts_at is null or e.ends_at is null then raise exception 'Set the exam date (opens at and closes at) in Settings before publishing.'; end if;
    for r in select s.pos, s.q_count, (select count(*) from exam_questions q where q.section_id=s.id) n from exam_sections s where s.exam_id=eid order by s.pos loop
      if r.n<>r.q_count then bad:=bad||' Section '||r.pos||' needs '||r.q_count||' questions but has '||r.n||'.'; end if; end loop;
    if bad<>'' then raise exception 'The exam cannot be published.%', bad; end if;
  end if;
  update exams set status=st, published_at=case when st='published' then coalesce(published_at,now()) else published_at end where id=eid;
  if st='published' and e.status='draft' and e.published_at is null then
    select code into cd from subjects where id=e.subject_id;
    perform _notify_subject(e.subject_id,'exam',cd||' · new exam: '||e.title,'Exam ID '||e.code,'subject/'||cd||'/exams'); end if; end $$;

create or replace function exam_del(t text, eid uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from exams where id=eid; end $$;

-- the exams of a subject (students: only published ones, with their own result)
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

-- admin: one exam with sections and ALL questions (with answers) for the editor
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

-- admin: HISTORY of all exams (table)
create or replace function exam_history(t text) returns json language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  return (select coalesce(json_agg(json_build_object('id',e.id,'code',e.code,'title',e.title,'subject',s.code,'category',e.category,'status',e.status,'starts_at',e.starts_at,'ends_at',e.ends_at,'created_at',e.created_at,'duration_min',e.duration_min,
      'q_total',(select coalesce(sum(q_count),0) from exam_sections where exam_id=e.id),'total_marks',_exam_total(e.id),
      'students',(select count(*) from enrollments where subject_id=e.subject_id),
      'submitted',(select count(*) from exam_attempts a where a.exam_id=e.id and a.status<>'in_progress'),
      'avg',(select round(avg(a.score),2) from exam_attempts a where a.exam_id=e.id and a.status<>'in_progress'),
      'max',(select max(a.score) from exam_attempts a where a.exam_id=e.id and a.status<>'in_progress')) order by e.created_at desc),'[]')
    from exams e join subjects s on s.id=e.subject_id); end $$;

-- admin: results of one exam: every student who started + the students who did not
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

-- admin: ANALYTICS of one exam - topper list, questions most students got wrong, marks histogram data, time per question
create or replace function exam_analytics(t text, eid uuid) returns json language plpgsql security definer set search_path=public as $$
declare e exams; begin perform _admin(t);
  select * into e from exams where id=eid; if e.id is null then raise exception 'Exam not found'; end if;
  return json_build_object('code',e.code,'title',e.title,'total_marks',_exam_total(e.id),
    'scores',(select coalesce(json_agg(a.score order by a.score desc),'[]') from exam_attempts a where a.exam_id=e.id and a.status<>'in_progress'),
    'toppers',(select coalesce(json_agg(z),'[]') from (select json_build_object('attempt_id',a.id,'name',st.name,'regno',st.regno,'email',st.email,'score',a.score,'total',a.total,
        'seconds',extract(epoch from (a.submitted_at-a.started_at))::int) z from exam_attempts a join students st on st.id=a.student_id
        where a.exam_id=e.id and a.status<>'in_progress' order by a.score desc nulls last, (a.submitted_at-a.started_at) limit 10) y),
    'questions',(select coalesce(json_agg(json_build_object('no',m.no,'section',m.sname,'kind',m.kind,'question',left(m.question,160),'attempted',m.att,'correct',m.c,'partial',m.p,'wrong',m.w,'skipped',m.s,
        'wrong_pct',case when m.att>0 then round(100.0*m.w/m.att,1) end,'avg_time',m.avg_t) order by m.no),'[]') from (
      select row_number() over (order by x.pos,q.pos) no, x.name sname, q.kind, q.question, count(a.id) att,
        count(*) filter (where sc.res='correct') c, count(*) filter (where sc.res='partial') p, count(*) filter (where sc.res='wrong') w, count(*) filter (where sc.res='skip') s,
        round(avg(nullif(case when coalesce(a.qtime->>(q.id::text),'') ~ '^[0-9]{1,6}(\.[0-9]+)?$' then (a.qtime->>(q.id::text))::numeric else 0 end,0)),0) avg_t
      from exam_questions q join exam_sections x on x.id=q.section_id
      left join exam_attempts a on a.exam_id=q.exam_id and a.status<>'in_progress'
      left join lateral _q_score(q.kind,q.answer,q.tolerance,case when q.kind in ('mcq','msq') then _unperm(a.answers->>(q.id::text),a.perm->(q.id::text)) else a.answers->>(q.id::text) end,1,0,q.partial) sc on a.id is not null
      where q.exam_id=e.id group by x.pos,q.pos,x.name,q.kind,q.question,q.id) m),
    'qlist',(select coalesce(json_agg(json_build_object('id',q.id,'no',q.no) order by q.no),'[]') from (select q0.id, row_number() over (order by x0.pos,q0.pos) no from exam_questions q0 join exam_sections x0 on x0.id=q0.section_id where q0.exam_id=e.id) q),
    'times',(select coalesce(json_agg(json_build_object('attempt_id',a.id,'name',st.name,'regno',st.regno,'score',a.score,'qtime',a.qtime) order by st.name),'[]')
      from exam_attempts a join students st on st.id=a.student_id where a.exam_id=e.id and a.status<>'in_progress')); end $$;

-- admin: EXTRA TIME / RE-EXAM of one student (for example after a power cut).  The attempt and the answers are KEPT.
--   a finished attempt is opened again; a running one gets more time.  The student opens the same exam link and continues.
create or replace function exam_grant(t text, aid uuid, mins int, rw boolean) returns void language plpgsql security definer set search_path=public as $$
declare a exam_attempts; e exams; dl timestamptz; s jsonb; cp int; lp int; sx exam_sections; begin perform _admin(t);
  select * into a from exam_attempts where id=aid; if a.id is null then raise exception 'Attempt not found'; end if;
  select * into e from exams where id=a.exam_id;
  if coalesce(mins,0) not between 1 and 600 then raise exception 'Extra time must be 1 to 600 minutes'; end if;
  dl:=_exam_deadline(aid);
  update exam_attempts set resume_until=greatest(dl,now())+(mins||' minutes')::interval, status='in_progress', submitted_at=null,
    reopens=reopens+case when a.status<>'in_progress' then 1 else 0 end, violations=case when coalesce(rw,false) then 0 else violations end,
    grants=grants||jsonb_build_array(jsonb_build_object('at',now(),'mins',mins,'was',a.status,'warnings_reset',coalesce(rw,false))) where id=aid;
  if e.lock_sections then
    s:=a.sec; cp:=(s->>'cur')::int;
    if s is not null and s<>'{}'::jsonb then
      if cp is null then   -- the exam had ended in the last section: open that section again
        select max(pos) into lp from exam_sections where exam_id=e.id; cp:=lp;
        s:=jsonb_set(s,'{cur}',to_jsonb(cp)); s:=jsonb_set(s,'{done}',coalesce((select jsonb_agg(v) from jsonb_array_elements(coalesce(s->'done','[]'::jsonb)) v where v::text<>cp::text),'[]'::jsonb));
        select * into sx from exam_sections where exam_id=e.id and pos=cp;
        s:=jsonb_set(s,'{st}',(s->'st')||jsonb_build_object(cp::text, case when sx.time_min is not null then now()-((sx.time_min-least(mins,sx.time_min))||' minutes')::interval else now() end));
      else
        select * into sx from exam_sections where exam_id=e.id and pos=cp;
        if sx.time_min is not null then s:=jsonb_set(s,'{st}',(s->'st')||jsonb_build_object(cp::text,(s->'st'->>(cp::text))::timestamptz+(mins||' minutes')::interval)); end if;
      end if;
      update exam_attempts set sec=s where id=aid; end if; end if;
  insert into activity(msg) values('Exam '||e.code||': '||mins||' extra minutes given to '||(select name from students where id=a.student_id)); end $$;

-- admin: let a student who has NOT started write the exam even after it closed (late start / re-exam).  mins = extra minutes on top of the duration (0 = just the duration)
create or replace function exam_allow_set(t text, eid uuid, stid uuid, mins int) returns void language plpgsql security definer set search_path=public as $$
declare e exams; begin perform _admin(t);
  select * into e from exams where id=eid; if e.id is null then raise exception 'Exam not found'; end if;
  if not exists(select 1 from enrollments where student_id=stid and subject_id=e.subject_id) then raise exception 'This student is not in the subject'; end if;
  if exists(select 1 from exam_attempts where exam_id=eid and student_id=stid) then raise exception 'This student already has an attempt. Use "Extra time" on the attempt.'; end if;
  if coalesce(mins,0) not between 0 and 600 then raise exception 'Extra minutes must be 0 to 600'; end if;
  insert into exam_allow(exam_id,student_id,extra_min) values(eid,stid,mins) on conflict (exam_id,student_id) do update set extra_min=excluded.extra_min;
  insert into notifications(role,user_id,subject_id,kind,title,body,link) values('student',stid,e.subject_id,'exam',(select code from subjects where id=e.subject_id)||' · you may write the exam: '||e.title,'Exam ID '||e.code,'subject/'||(select code from subjects where id=e.subject_id)||'/exams'); end $$;

create or replace function exam_allow_del(t text, eid uuid, stid uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from exam_allow where exam_id=eid and student_id=stid; end $$;

-- the answer sheet: every question in the order that student saw it, the answer given, the right answer, marks and the TIME spent.  Admin, or the student who wrote it.
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

-- student: what the exam looks like before starting (no questions)
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

-- student: START (or continue) the exam.  v44: the name comes from the login; only the Gmail is typed and it must match the logged-in account.  The paper has NO answers in it.
drop function if exists exam_start(text,text,text,text);
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

-- student: autosave (answers, marked-for-review flags, warnings, warning log, time per question)
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

-- student (sectional exam): finish the section fpos and open the next one.  Cannot go back.  finished=true after the last section (the page then submits).
create or replace function exam_advance(t text, aid uuid, fpos int, ans jsonb, fl jsonb, qt jsonb) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; a exam_attempts; e exams; cp int; nx int; s jsonb; begin k:=_s(t);
  select * into a from exam_attempts where id=aid and student_id=k.user_id; if a.id is null then raise exception 'Not allowed'; end if;
  if a.status<>'in_progress' then return json_build_object('over',true); end if;
  select * into e from exams where id=a.exam_id; if not e.lock_sections then raise exception 'This exam is not sectional'; end if;
  perform _exam_sync(aid); select * into a from exam_attempts where id=aid;
  if a.status<>'in_progress' then return json_build_object('over',true); end if;
  cp:=(a.sec->>'cur')::int;
  if cp=fpos then
    if length(coalesce(ans,'{}'::jsonb)::text)>300000 then raise exception 'Too much data'; end if;
    update exam_attempts set answers=_exam_merge(aid,ans,a.answers), flags=case when jsonb_typeof(fl) ='object' then fl else flags end, qtime=_merge_max(a.qtime,qt) where id=aid;
    select min(pos) into nx from exam_sections where exam_id=e.id and pos>cp;
    if nx is null then return json_build_object('over',false,'finished',true); end if;
    s:=jsonb_set(a.sec,'{done}',coalesce(a.sec->'done','[]'::jsonb)||to_jsonb(cp)); s:=jsonb_set(s,'{cur}',to_jsonb(nx)); s:=jsonb_set(s,'{st}',(s->'st')||jsonb_build_object(nx::text,now()));
    update exam_attempts set sec=s where id=aid;
  end if;
  select * into a from exam_attempts where id=aid; cp:=(a.sec->>'cur')::int;
  return json_build_object('over',false,'finished',false,'sec',_exam_secinfo(aid),'questions',_exam_qs(aid,cp),'answers',a.answers,'flags',a.flags,'remaining',greatest(0,extract(epoch from (_exam_deadline(aid)-now()))::int)); end $$;

-- student: SUBMIT.  why = 'manual' | 'time' | 'violations'.  A manual submit is possible only after the earliest-submit time (default: half of the duration).  The marks are calculated here, on the server.
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

-- student: all my results
create or replace function exam_my_results(t text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  if k.role<>'student' then raise exception 'Only for students'; end if;
  return (select coalesce(json_agg(json_build_object('attempt_id',a.id,'code',e.code,'title',e.title,'subject',s.code,'category',e.category,'pending',(a.score is null),'status',a.status,'score',a.score,'total',a.total,'correct',a.correct,'wrong',a.wrong,'partial',a.partial,'skipped',a.skipped,'submitted_at',a.submitted_at,
      'rank',(select count(*)+1 from exam_attempts b where b.exam_id=a.exam_id and b.status<>'in_progress' and b.score>a.score),'of',(select count(*) from exam_attempts b where b.exam_id=a.exam_id and b.status<>'in_progress')) order by a.submitted_at desc nulls last),'[]')
    from exam_attempts a join exams e on e.id=a.exam_id join subjects s on s.id=e.subject_id where a.student_id=k.user_id and a.status<>'in_progress'); end $$;


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


-- ---------- permissions (the website may only call the public functions; the _helpers stay private) ----------
grant usage on schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;
revoke all on function _s(text) from public, anon, authenticated;
revoke all on function _admin(text) from public, anon, authenticated;
revoke all on function _access(text, uuid) from public, anon, authenticated;
revoke all on function _mysubs(sessions) from public, anon, authenticated;
revoke all on function _taken(text) from public, anon, authenticated;
revoke all on function _cleanup() from public, anon, authenticated;
revoke all on function _notify_subject(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function _throttle_check(text) from public, anon, authenticated;
revoke all on function _throttle_fail(text) from public, anon, authenticated;
revoke all on function _throttle_ok(text) from public, anon, authenticated;
revoke all on function _mobile(text, text) from public, anon, authenticated;
revoke all on function _isproj(uuid) from public, anon, authenticated;
revoke all on function _myteam(uuid, uuid) from public, anon, authenticated;
revoke all on function _drive(text) from public, anon, authenticated;
revoke all on function _exam_code() from public, anon, authenticated;
revoke all on function _exam_grade(uuid) from public, anon, authenticated;
revoke all on function _exam_regrade(uuid) from public, anon, authenticated;
revoke all on function _exam_deadline(uuid) from public, anon, authenticated;
revoke all on function _exam_finish(uuid, text) from public, anon, authenticated;
revoke all on function _exam_q_put(uuid, uuid, jsonb) from public, anon, authenticated;
revoke all on function _drive_file(text) from public, anon, authenticated;
revoke all on function _q_score(text, text, numeric, text, numeric, numeric, boolean) from public, anon, authenticated;
revoke all on function _unperm(text, jsonb) from public, anon, authenticated;
revoke all on function _disp_opts(jsonb, jsonb) from public, anon, authenticated;
revoke all on function _disp_ans(text, jsonb) from public, anon, authenticated;
revoke all on function _merge_max(jsonb, jsonb) from public, anon, authenticated;
revoke all on function _vlog_merge(jsonb, jsonb) from public, anon, authenticated;
revoke all on function _exam_paper(uuid) from public, anon, authenticated;
revoke all on function _exam_total(uuid) from public, anon, authenticated;
revoke all on function _exam_min_submit(uuid) from public, anon, authenticated;
revoke all on function _exam_init(uuid) from public, anon, authenticated;
revoke all on function _exam_sync(uuid) from public, anon, authenticated;
revoke all on function _exam_secinfo(uuid) from public, anon, authenticated;
revoke all on function _exam_qs(uuid, int) from public, anon, authenticated;
revoke all on function _exam_merge(uuid, jsonb, jsonb) from public, anon, authenticated;

notify pgrst, 'reload schema';
