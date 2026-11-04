-- =====================================================================================================
-- 04_upgrade_v40.sql   Gaddam Venu portal v40   -> for an EXISTING database (v39 or older).  Keeps ALL data.
-- Run it ONCE, then run  02_functions.sql  again (it is safe to run again).
-- (A NEW install does not need this file: 01_tables.sql already contains everything.)
-- =====================================================================================================
alter table exams          add column if not exists shuffle boolean not null default true;
alter table exams          add column if not exists lock_sections boolean not null default false;
alter table exams          add column if not exists min_submit_min int;
alter table exam_sections  add column if not exists time_min int;
alter table exam_questions add column if not exists image_url text;
alter table exam_questions add column if not exists marks numeric(6,2);
alter table exam_questions add column if not exists negative numeric(6,2);
alter table exam_questions add column if not exists partial boolean not null default false;
alter table exam_attempts  add column if not exists partial int not null default 0;
alter table exam_attempts  add column if not exists perm jsonb not null default '{}'::jsonb;
alter table exam_attempts  add column if not exists qorder jsonb not null default '{}'::jsonb;
alter table exam_attempts  add column if not exists qtime jsonb not null default '{}'::jsonb;
alter table exam_attempts  add column if not exists vlog jsonb not null default '[]'::jsonb;
alter table exam_attempts  add column if not exists sec jsonb not null default '{}'::jsonb;
alter table exam_attempts  add column if not exists extra_min int not null default 0;
alter table exam_attempts  add column if not exists bypass boolean not null default false;
alter table exam_attempts  add column if not exists resume_until timestamptz;
alter table exam_attempts  add column if not exists reopens int not null default 0;
alter table exam_attempts  add column if not exists grants jsonb not null default '[]'::jsonb;

-- new checks (the old kind check only knew mcq / num / fill)
alter table exam_questions drop constraint if exists exam_questions_kind_check;
alter table exam_questions add  constraint exam_questions_kind_check check (kind in ('mcq','msq','num','fill'));
alter table exams          drop constraint if exists exams_min_submit_min_check;
alter table exams          add  constraint exams_min_submit_min_check check (min_submit_min between 0 and 600);
alter table exam_sections  drop constraint if exists exam_sections_time_min_check;
alter table exam_sections  add  constraint exam_sections_time_min_check check (time_min between 1 and 600);
alter table exam_questions drop constraint if exists exam_questions_marks_check;
alter table exam_questions add  constraint exam_questions_marks_check check (marks > 0);
alter table exam_questions drop constraint if exists exam_questions_negative_check;
alter table exam_questions add  constraint exam_questions_negative_check check (negative >= 0);

create table if not exists exam_allow(
  exam_id uuid not null references exams(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  extra_min int not null default 0 check (extra_min between 0 and 600),
  created_at timestamptz default now(), primary key(exam_id, student_id));
alter table exam_allow enable row level security;

-- NOTE: exams created before v40 without a date keep working as they are.  The exam date becomes compulsory when you edit the exam Settings or publish it again.
notify pgrst, 'reload schema';
