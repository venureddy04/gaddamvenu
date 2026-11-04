-- =====================================================================================================
-- 01_tables.sql      Gaddam Venu portal (v40)       FILE 1 of 3  ->  run 01, then 02, then 03   (Supabase > SQL Editor)
--
-- NEW INSTALL.  This file first DELETES every table of the portal and creates all of them again (empty).
-- Do NOT run it on a database that holds data you want to keep.
--
-- Subject types: theory | lab (theory + lab) | mini (Mini Project) | major (Major Project)
-- Students log in with Gmail + password.  Required: name, Gmail, password, mobile.  Optional: Reg No, parent mobile.
-- Tasks:  every subject = ONE Google Drive link (viewed inside the site, never shown).   Projects = teams, formats, Drive-link tasks and work posts.
-- =====================================================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---- 1. remove everything from the old versions ----
do $$ declare r record; begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f' loop
    execute 'drop function if exists ' || r.sig || ' cascade';
  end loop; end $$;

drop table if exists exam_allow, exam_attempts, exam_questions, exam_sections, exams, work_posts, formats, team_members, teams, timetables, task_submissions, tasks, lab_batch_members, mark_values, mark_sheets, notifications, leaves, videos, email_log, login_attempts, hidden, shares, activity, sessions, labs, notices,
  materials, enrollments, cr_subjects, crs, students, classes, subjects, admins cascade;

drop policy if exists mat_ins on storage.objects;

drop policy if exists mat_del on storage.objects;

-- ---- 2. tables ----
create table admins(
  id uuid primary key default gen_random_uuid(),
  username text unique not null,                 -- admin login (e-mail, lower-case)
  name text, password_hash text not null,
  photo text);

                                   -- profile photo (small JPEG as data URL)
create table subjects(                           -- one row per  SUBJECT + ACADEMIC YEAR,  e.g. DS-2026-2027
  id uuid primary key default gen_random_uuid(),
  code text unique not null,                     -- DS-2026-2027
  name text not null,                            -- DS
  year int not null,                             -- 2026  (the academic year starts in 2026 and ends in 2027)
  full_name text,                                -- Data Structures (optional)
  kind text not null default 'theory' check (kind in ('theory','lab','mini','major')),   -- theory = theory only, lab = theory + lab, mini = Mini Project, major = Major Project
  hidden_tabs text[] not null default '{}',      -- v41: tabs the admin switched off (visible = false)
  created_at timestamptz default now());

create table students(
  id uuid primary key default gen_random_uuid(),
  regno text unique check (regno ~ '^[A-Z0-9]{5,15}$'),      -- OPTIONAL (students log in with their Gmail)
  name text not null,
  email text not null,
  year smallint not null check (year between 1 and 4),   -- study year 1-4
  password_hash text not null,
  pw text not null,                              -- readable copy: only admin functions return it
  semester smallint check (semester between 1 and 8),   -- semester 1-8 (empty only for old students)
  mobile text, parent_mobile text,               -- 10-digit mobile numbers
  photo text,                                    -- profile photo (small JPEG as data URL)
  created_by text default 'admin',               -- admin / cr
  created_at timestamptz default now());

create unique index students_email_uq on students (lower(email));

   -- one account per Gmail
create table crs(                                -- class representatives, e.g. CSE-CR
  id uuid primary key default gen_random_uuid(),
  username text unique not null,
  name text, email text,
  password_hash text not null, pw text not null,
  photo text,
  created_at timestamptz default now());

create table cr_subjects(
  cr_id uuid references crs(id) on delete cascade,
  subject_id uuid references subjects(id) on delete cascade,
  primary key(cr_id, subject_id));

create table enrollments(                        -- which students belong to which subject
  subject_id uuid references subjects(id) on delete cascade,
  student_id uuid references students(id) on delete cascade,
  primary key(subject_id, student_id));

create table materials(                          -- Google Drive links
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  category text not null check (category in ('Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks')),
  title text not null, link text not null,
  visible boolean not null default true,         -- v41
  created_at timestamptz default now());

create table videos(                             -- video lessons (links)
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  title text not null, link text not null,
  visible boolean not null default true,         -- v41
  created_at timestamptz default now());

create table notices(
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  title text not null, message text, due_date date, due_time time,
  visible boolean not null default true,         -- v41
  created_at timestamptz default now());

create table labs(                               -- lab experiments / assignments (Drive link and/or program text)
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  exp_no text, title text not null, task text, program text,
  lab_date date, lab_time time, link text,
  visible boolean not null default true,         -- v41
  created_at timestamptz default now());

create table tasks(                              -- a task posted by the admin (notice format). Theory / Lab: students answer with ONE Word file. Projects: a team answers with a Drive link.
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  title text not null, message text, due_date date,
  max_marks numeric(6,2),                        -- optional: marks are checked against it
  submit_mode text not null default 'link' check (submit_mode in ('link','button')),   -- v41: 'link' = Drive link, 'button' = one press
  deadline timestamptz,                          -- v41: ONE deadline field (date + time)
  visible boolean not null default true,         -- v41: false = hidden from students
  link text,                                     -- v44: the admin posts the task as ONE Google Drive link
  created_at timestamptz default now());

create table teams(                              -- project teams (Mini Project / Major Project)
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  name text not null, title text, guide text,    -- team name, project title, guide
  created_at timestamptz default now());

create table team_members(
  team_id uuid not null references teams(id) on delete cascade,
  subject_id uuid not null references subjects(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  leader boolean not null default false,
  primary key(team_id, student_id),
  unique(subject_id, student_id));

               -- a student is in ONE team of a project
create table formats(                            -- formats / templates the admin gives to a project (Drive link)
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  title text not null, note text, link text not null,
  visible boolean not null default true,         -- v41
  created_at timestamptz default now());

create table work_posts(                         -- work posted by students / teams to the admin: code, report, PPT ... (Drive link only)
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  team_id uuid references teams(id) on delete set null,
  student_id uuid not null references students(id) on delete cascade,
  kind text not null check (kind in ('Code','Report','PPT','Other')),
  title text not null, link text not null, note text,
  created_at timestamptz default now(), updated_at timestamptz default now());

create index work_sub on work_posts(subject_id, created_at desc);

create table task_submissions(                   -- Theory / Lab: ONE Word file per student.  Project: ONE Drive link per team.
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references tasks(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  team_id uuid references teams(id) on delete cascade,
  file_name text, file_data text, file_size int, -- the .doc / .docx as base64 text
  link text,                                     -- project: Google Drive link
  via_button boolean not null default false,     -- v41: submitted with the Submit button (no link, no file)
  status text not null default 'submitted' check (status in ('submitted','verified','redo')),   -- verified = admin pressed OK
  marks numeric(6,2), remark text,
  submitted_at timestamptz default now(), updated_at timestamptz default now(), verified_at timestamptz,
  constraint task_sub_has_answer check (file_data is not null or link is not null or via_button));

create unique index task_sub_one  on task_submissions(task_id, student_id) where team_id is null;

create unique index task_sub_team on task_submissions(task_id, team_id) where team_id is not null;

create index task_sub_task on task_submissions(task_id);

alter table tasks enable row level security;

alter table teams enable row level security;

alter table team_members enable row level security;

alter table formats enable row level security;

alter table work_posts enable row level security;

alter table task_submissions enable row level security;

create table notifications(                      -- in-app bell notifications
  id bigint generated always as identity primary key,
  role text not null, user_id uuid not null,
  subject_id uuid references subjects(id) on delete cascade,
  kind text, title text, body text, link text,
  seen boolean not null default false,
  created_at timestamptz default now());

create index notif_user on notifications(role, user_id, id desc);

create table sessions(
  token text primary key,
  role text not null check (role in ('admin','cr','student')),
  user_id uuid not null,
  expires_at timestamptz not null default now() + interval '3 days');

create table email_log(
  id bigint generated always as identity primary key,
  kind text, to_email text, name text, subject text, status text, error text, message text,
  created_at timestamptz default now());

create table activity(id bigint generated always as identity primary key, msg text, created_at timestamptz default now());

create table login_attempts(key text primary key, fails int not null default 0,
  first_fail timestamptz not null default now(), locked_until timestamptz);

-- ---- 3. lock every table: the website can only use the functions in 02 ----
alter table admins enable row level security;

alter table subjects enable row level security;

alter table students enable row level security;

alter table crs enable row level security;

alter table cr_subjects enable row level security;

alter table enrollments enable row level security;

alter table materials enable row level security;

alter table notices enable row level security;

alter table labs enable row level security;

alter table sessions enable row level security;

alter table email_log enable row level security;

alter table activity enable row level security;

alter table login_attempts enable row level security;

alter table videos enable row level security;

alter table notifications enable row level security;

--
-- NOTICES   : the "time" field is gone (date only). The message can now be formatted text
--             (bold, italic, underline, alignment, bullets, numbers). It is stored as safe HTML in notices.message;
--             old plain-text notices still display correctly.
-- LAB PROGRAMS : new columns  slot (9.00-11.30 / 11.30-2.00 / 2.00-4.30)  and  location (lab room).
--             Lab number is a number / "Lab 1 ... Lab 50" (any text up to 10 characters is accepted).
--             The program is a Drive link and / or code (at least one). Title is optional now.
alter table public.labs add column if not exists slot text;

alter table public.labs add column if not exists location text;

-- MARKS SHARE (Theory Marks) and LAB MARKS, one sheet per subject
--   mark_sheets : the columns of the sheet (name, type 'marks' or 'formula', formula text, optional max marks) + Lab row colors
--   mark_values : one row per student, all his / her marks as JSON { columnId : number or "AB" }
-- ADMIN  : create / edit / delete columns, enter / edit / clear every row, row colors (Lab), download Excel / PDF / Word
-- CR     : sees the marks of every student of the assigned subjects (view only)
-- STUDENT: sees ONLY his / her own row
-- Theory Marks must always have the column "AAT 1".  A mark is a number (0 to the column maximum) or the text AB (absent).
create table if not exists public.mark_sheets(
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  kind text not null check (kind in ('theory','lab')),          -- theory = Marks Share, lab = Lab Marks
  cols jsonb not null default '[]'::jsonb,                      -- [{id,name,type:'marks'|'formula',f:'=SUM([A],[B])',max:10}]
  row_colors jsonb,                                             -- Lab Marks row colors (v28): {on,col,rows:[{from,color}]}  empty = defaults
  updated_at timestamptz default now(),
  unique(subject_id, kind));

create table if not exists public.mark_values(
  sheet_id uuid not null references public.mark_sheets(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  vals jsonb not null default '{}'::jsonb,                      -- { columnId : number }
  updated_at timestamptz default now(),
  primary key(sheet_id, student_id));

alter table public.mark_sheets enable row level security;

       -- the website can only use the functions below
alter table public.mark_values enable row level security;

-- Run it AFTER 08 (and the other files up to 15).   Old SQL files are NOT changed.
--
-- LAB BATCHES (Theory + Lab subjects only)
--   * The admin splits the students of a subject into Batch 1 and Batch 2 (by Reg No) and gives each batch a color.
--   * A lab program is posted for ONE batch.  A student sees only the lab programs of his / her own batch
--     (lab programs posted before v30 have no batch and stay visible to everybody).  Admin and CR see all.
--   * Lab Marks can be shown batch-wise (the website reads the batch of every student with batches_get).
--
-- What this file does
--   1. labs.batch            : new column (1 or 2, empty = old lab program for everybody)
--   2. subjects.batch_colors : the two batch colors, e.g. {"1":"#2563eb","2":"#f59e0b"}
--   3. lab_batch_members     : new table, which student is in which batch of a subject
--   4. batches_get / batches_save : NEW functions (read / save the batches)
--   5. subject_content       : same as before, but a student gets only his / her batch's lab programs
--   6. lab_add               : new last parameter  bt  (the batch, 1 or 2); the bell notification goes to that batch only
alter table public.labs     add column if not exists batch smallint;

alter table public.labs     drop constraint if exists labs_batch_check;

alter table public.labs     add  constraint labs_batch_check check (batch is null or batch in (1,2));

alter table public.subjects add column if not exists batch_colors jsonb;

create table if not exists public.lab_batch_members(
  subject_id uuid not null references public.subjects(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  batch smallint not null check (batch in (1,2)),
  primary key(subject_id, student_id));

                       -- one student is in ONE batch of a subject
alter table public.lab_batch_members enable row level security;

--
-- 1. MARKS PUBLISH:  every Theory Marks / Lab Marks sheet gets a  published  flag.
--      - Sheets that already exist stay VISIBLE (published = true), nothing changes for them.
--      - A NEW sheet starts as NOT published: the students (and the CR) see nothing until the admin presses "Publish".
--      - The admin always sees everything.  Publishing sends a bell notification to the students of the subject.
--    marks_get      : changed (returns  published ; hides columns + rows from students / CR while not published)
--    marks_publish  : new (admin) - publish or unpublish a sheet
-- 2. TIMETABLE:  one timetable for every  Year + Semester  (Monday to Saturday, 9 periods, merged cells, lab blocks).
--    timetables     : new table
--    timetable_get  : a student gets the timetable of his / her own year + semester;  admin / CR choose year + semester
--    timetable_save : new (admin)      timetable_del : new (admin)
alter table public.mark_sheets add column if not exists published boolean;

update public.mark_sheets set published=true where published is null;

           -- old sheets stay visible
alter table public.mark_sheets alter column published set default false;

        -- new sheets start hidden
alter table public.mark_sheets alter column published set not null;

-- ---------- timetable ----------
create table if not exists public.timetables(
  year smallint not null check (year between 1 and 4),
  semester smallint not null check (semester between 1 and 8),
  data jsonb not null default '{}'::jsonb,                  -- { periods:[[start,end]...9], days:{ Monday:[{n:1,t:'DS',k:'t'}...] ... } }
  updated_at timestamptz default now(),
  primary key(year,semester));

alter table public.timetables enable row level security;

-- ===================================================== EXAMS =====================================================
create table exams(                              -- an online exam of a subject (created by the admin)
  id uuid primary key default gen_random_uuid(),
  code text not null unique,                     -- the Exam ID people search with, e.g. EX-7K3Q2M
  subject_id uuid not null references subjects(id) on delete cascade,
  title text not null, instructions text,
  duration_min int not null check (duration_min between 1 and 600),
  starts_at timestamptz, ends_at timestamptz,    -- optional exam window
  max_violations int not null default 3 check (max_violations between 1 and 20),   -- full-screen exits / tab switches before auto-submit
  shuffle boolean not null default true,         -- every student gets the questions and the options in his / her own order
  lock_sections boolean not null default false,  -- sectional (NPTEL style): sections one by one, no going back; a section may have its own time
  min_submit_min int check (min_submit_min between 0 and 600),   -- earliest minute (from the student's start) when Submit works; empty = half of the duration
  category text not null default 'theory' check (category in ('theory','lab')),   -- theory = MCQ exam | lab = write-up exam marked by the admin
  mandatory boolean not null default true,        -- every question compulsory (a manual Submit needs all answered)
  status text not null default 'draft' check (status in ('draft','published','closed')),
  created_at timestamptz default now(), published_at timestamptz);
create table exam_sections(                      -- sections with their own marking: + marks for a correct answer, - negative marks for a wrong one
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references exams(id) on delete cascade,
  pos int not null, name text not null,
  q_count int not null check (q_count between 1 and 200),
  marks numeric(6,2) not null default 1 check (marks > 0),
  negative numeric(6,2) not null default 0 check (negative >= 0),
  time_min int check (time_min between 1 and 600),   -- optional time of this section (sectional exams)
  unique(exam_id, pos));
create table exam_questions(                     -- mcq = single correct, msq = several correct, num = numerical, fill = fill in the blank
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references exams(id) on delete cascade,
  section_id uuid not null references exam_sections(id) on delete cascade,
  pos int not null,
  kind text not null check (kind in ('mcq','msq','num','fill','lab')),
  question text not null,                        -- plain text; formulas are written between $ signs, e.g. $x^2 + \frac{a}{b}$
  image_url text,                                -- optional picture (https link)
  options jsonb,                                 -- mcq / msq: ["option A","option B",...]
  answer text not null,                          -- mcq: letter | msq: letters like A,C | num: number | fill: accepted answers separated by |
  tolerance numeric(12,6) not null default 0,    -- num: allowed difference
  marks numeric(6,2) check (marks > 0),          -- marks of THIS question; empty = the marks of its section
  negative numeric(6,2) check (negative >= 0),   -- negative marks of THIS question; empty = the section's negative marks
  partial boolean not null default false,        -- msq: partial marks for a part of the right options (no wrong option picked)
  explanation text);
create index exam_q_exam on exam_questions(exam_id, section_id, pos);
create table exam_attempts(                      -- one attempt per student per exam. NO camera data is ever stored.
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references exams(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  started_at timestamptz not null default now(), submitted_at timestamptz,
  answers jsonb not null default '{}'::jsonb,    -- {question id: answer}
  flags jsonb not null default '{}'::jsonb,      -- {question id: true}  marked for review
  violations int not null default 0,
  status text not null default 'in_progress' check (status in ('in_progress','submitted','auto_time','auto_violations')),
  score numeric(8,2), total numeric(8,2), correct int, wrong int, skipped int, partial int not null default 0,
  perm jsonb not null default '{}'::jsonb,       -- {question id: [original option index in the order this student saw them]}
  qorder jsonb not null default '{}'::jsonb,     -- {section no: [question ids in the order this student saw them]}
  qtime jsonb not null default '{}'::jsonb,      -- {question id: seconds spent}
  vlog jsonb not null default '[]'::jsonb,       -- warning log [{at, why}]
  sec jsonb not null default '{}'::jsonb,        -- sectional exam: {cur, st:{section: start time}, done:[...]}
  extra_min int not null default 0,              -- extra minutes (late start / re-exam)
  bypass boolean not null default false,         -- allowed to start outside the exam window
  resume_until timestamptz,                      -- admin gave extra time: the attempt may continue until this time
  reopens int not null default 0, grants jsonb not null default '[]'::jsonb,   -- how often the admin reopened it, and the log of it
  saved_at timestamptz,                          -- last time the answers reached the server
  lab jsonb not null default '{}'::jsonb,        -- lab exam: marks given by the admin {question id: {m: marks, r: remark}}
  unique(exam_id, student_id));
create index exam_att_exam on exam_attempts(exam_id);
create table exam_allow(                         -- a student the admin allowed to start although the exam window is over (late start / re-exam)
  exam_id uuid not null references exams(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  extra_min int not null default 0 check (extra_min between 0 and 600),
  created_at timestamptz default now(), primary key(exam_id, student_id));
alter table exam_allow enable row level security;
alter table exams enable row level security;          alter table exam_sections enable row level security;
alter table exam_questions enable row level security; alter table exam_attempts enable row level security;
