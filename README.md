# Gaddam Venu – Classroom portal (v47)

## v48 update (e-mail aligned with the working Nagarjuna app)
- E-mail uses the SAME request as the working app: admin in "To", students in BCC, one Brevo request (up to 95 students each). The 4-second delivery re-check was removed. See DEPLOY-NETLIFY.md (top) for why it works there and the exact deploy steps.
- Optional database route: `sql/10_upgrade_v48.sql` (re-run it if you already ran the first version: it replaces `mail_send`).

## v47 update (Syllabus "Other", exams / lab manual open inside the site)
**Existing database: run `sql/09_upgrade_v47.sql` once** in Supabase (after 08). Upload the whole folder again.
- **Syllabus**: choose **Other**, type the heading + name, paste the Drive link.
- **Exams**: exam / login-ID links open inside this website (full-screen frame + Close). `_headers` now has `frame-src https:`.
- **Lab Manual**: opens inside this website (protected viewer).
- **E-mail (v48)**: run `sql/10_upgrade_v48.sql` once, then Email > E-mail settings: paste the Brevo key + sender. E-mail is then sent through the database and works on ANY address (no Netlify function). The old function route stays as fallback.
- **E-mail**: Email page -> **Check e-mail setup** shows what is missing (function, variables, Brevo key, verified sender). Clear error messages. Open `/.netlify/functions/send-email` to test that the function is deployed. See DEPLOY-NETLIFY.md section D.


## Setup (NEW install: 4 SQL files, in this order: 01, 02, 03, then 08_upgrade_v46.sql)
1. Supabase > SQL Editor > run `sql/01_tables.sql`   (NEW INSTALL: it deletes every portal table first, then creates all tables empty)
2. run `sql/02_functions.sql`   (all functions; safe to run again)
3. run `sql/03_admin_seed.sql`  (admin login; edit the e-mail / password inside the file first)
Then put your Supabase URL + key (and Brevo key for e-mails) in `config.js` and upload the folder to your hosting.

## What is new in v46  (exams by link, Lab Manual, Zoom Meeting, Materials "Other", simpler Tasks)
**Existing database: run ONLY `sql/08_upgrade_v46.sql` once** (safe to run again; keeps all data). Do NOT run `02_functions.sql` after it (it would bring back the old exam functions). Upload the whole folder again.

* **Exams = links.** The exam builder (Theory MCQ, Lab write-up, templates, marking, exam room) is removed. Subject > **Exams**: choose **Lab exam / Theory exam / Login IDs**, type a title, paste a link. Students press **Open** and it opens in a new page.
* **Lab Manual tab** (Theory + Lab subjects): Name + Google Drive link + optional note. Optional batch: All students / Batch 1 / Batch 2 (create batches from the same tab or from Lab Programs).
* **Materials:** category **Other**: type the name (for example Previous papers); it becomes its own heading.
* **Tasks:** Title + Google Drive link + Deadline only.
* **Zoom Meeting tab:** Title + meeting link + optional date and time. Students press **Join** (new page). Students are notified and e-mailed.
* The old exam tables and results stay in the database. To delete them, remove the two dashes in front of the `drop table` line at the end of the SQL file.
* Right-click (phone: press and hold) works on the new tabs and cards for visible = true / false.

## What is new in v45  (Theory + Lab exams, exam room, compulsory questions, no more "check internet")
**Existing database: run ONLY `sql/07_upgrade_v45.sql` once** (safe to run again; keeps all data; no need to run 02 again). Upload the whole folder again. New install: the 3 files as before (01 and 02 already contain v45).

### 1. Create exam = 3 steps, two types
Subject > Exams > **+ Create exam**
1. **Exam details** – type **Theory** (MCQ) or **Lab** (write-up), title, instructions.
2. **Date and time** – starts at, duration, room closes at, warnings allowed.
3. **Questions and marks** – number of questions (example 50), marks per question, negative marks (theory), **All questions compulsory** (NPTEL style), shuffle.

Then **Manage** > download the template > fill > **Upload questions** > Publish.

### 2. Two Excel templates (in the folder `templates/` and in the site)
* `Theory-MCQ-template.xlsx` – sheet **MCQ**: `Question | A | B | C | D | E | F | Answer | Marks | Negative | Image | Explanation`. Example: `Which data structure uses LIFO? | Queue | Stack | Tree | Graph | | | B | 1 | 0.25`
* `Lab-exam-template.xlsx` – sheet **Lab**: `Question | Image | Marks | Key points | Model answer`. Example: `Write a C program to find the factorial of a number | | 10 | loop 1..n, output 120 for n=5 | …`
* The buttons are also in the Exams tab (⬇ Theory (MCQ) template / ⬇ Lab (write-up) template) and inside every exam. A Lab file cannot be uploaded into a Theory exam (and the other way) – the site tells you.

### 3. Exam room (before the start)
* Students can open the exam link and fill their details **5 minutes before** the start (in the subject Exams tab the button **Enter exam room** appears 5 minutes before). Name comes from the login, they type the Gmail, tick the rules, and can **Test my camera**.
* The **Start** button is **disabled** and turns on **by itself at the exact start time** (the server clock is used, so a wrong computer clock does not matter). More than 5 minutes before the start, only a countdown is shown.
* The **Submit** button turns on only after **half of the exam time** (a 60-minute exam: after 30 minutes). Time up submits automatically.
* "Camera on · not recorded" text removed (the camera still stays on as a live preview).

### 4. Compulsory questions (like NPTEL)
With **All questions compulsory** ticked, Submit is refused (on the page and in the database) while a question is not answered; the page shows which question numbers are empty. When time is over, or after too many warnings, the exam is submitted automatically even if questions are empty.

### 5. Lab exam (write-up)
* You give the lab programs (Excel). Every student writes, for each program: **Aim**, **Algorithm step by step** (Step 1, Step 2 … with + Add step), **Program** (Tab key = 4 spaces) and **Output / Result**. Paste is blocked.
* Results > **Evaluate** (or **Edit marks**): you read each answer, see your *Key points*, type marks (0 to the maximum) and an optional remark. **Save marks** or **Save & next student to mark**.
* Until every answered program has marks, the student sees **Awaiting marks**; when you finish, the marks and the remarks reach the student (Exams page + notification). A program not answered = 0.
* The marks column, rank, Excel and Print/PDF of the results work as before (marks not given yet show *To be marked*).

### 6. 100+ students at the same time – the "Not saved – check the internet" message
Cause: many students saved at the same moment and some requests failed or timed out. Fixed:
* a failed save / start / submit is **retried automatically** with a growing random pause; one save at a time per student;
* saving every ~30 seconds, each student at a different moment (before: every 20 s together) and 5 s after an answer (before 1.5 s);
* answers are also kept **on the student's computer**; after a break they come back;
* the message is now *Server busy – retrying… your answers are safe*, or *No internet – answers are kept on this computer…* only when the browser really is offline;
* the final Submit keeps retrying by itself until it works (before: 4 tries, then the student had to press again); the database accepts the answers up to 5 minutes after the time end;
* the database save function is lighter (no section work for normal exams).
If your Supabase plan is the free one and 150+ students still see "busy", upgrade the Supabase project for the exam day (more connections) – the site is now ready for it.

### 7. Extra fixes and improvements (found while testing with 150 simulated students)
* **Fixed – "duplicate key" error at Start / double Submit:** if a student pressed Start twice (or the site retried while the first request was still running) the database could answer with an error, and a double Submit could send two notifications. Start, Save, Submit and Marking now wait for each other per student. A late Save can no longer overwrite an exam that is already submitted.
* **Fixed – "You can submit only after … minutes" appearing a second too early:** the database allows 5 seconds of network delay and the page waits 2 more seconds.
* **Fixed – typing { } [ ] \\ @ with AltGr keyboards** is no longer blocked in the Lab editor.
* **Admin – live view:** Results refresh by themselves every 20 seconds while students are writing and show **how many questions each student answered** and **when the answers were last saved**. "⚠ no save for 3 min" = that student has a connection problem: call them to reopen the link.
* **Admin – ranks:** equal marks now get the same rank (8, 8, 5 gives ranks 1, 1, 3). Students whose lab marks are pending have no rank yet.
* **Admin – Lab answers (Excel):** one row per student per program (Aim, steps, program, output, marks, remark).
* **Admin – marking:** **Full marks** and **Zero** buttons and a live "Marks so far" total in the Evaluate window.
* The answers of one student may now be bigger (up to 500 KB) – needed for long lab programs.
* Speed check on a small computer: 360 Start requests from 90 students at the same time finished with no error (about 60 per second); 380 Saves per second. The database is not the slow part: a "busy" message is mostly the internet of the student or the Supabase plan.

## What is new in v44  (tasks by Drive link, Submit Work for all subjects, exam name automatic)
**Existing database: run ONLY `sql/06_upgrade_v44.sql` once** (it has everything; no need to run 02 again). Upload the whole folder again. New install: the 3 files as before.

* **Tasks tab (admin):** the admin posts a task with **one Google Drive link** (title, link, optional note + deadline, **visible = true / false**) and can **Edit** or Delete it. Students open the link from the Tasks tab. Old tasks (made before v44) keep working as before.
* **Submit Work tab (students):** in **every subject** (theory, lab, project) a student posts work (Code / Report / PPT / Other) as a Drive link; the admin sees all posts (filter by type) and opens / downloads them. Students can edit / delete their own posts; the admin can delete. The admin can hide the tab with right-click -> visible = false.
* **Exam start page:** the student's **name is shown automatically** (from the login, read-only). Only the **Gmail** is typed (it must match the login).

## What is new in v43  (analytics removed, e-mail delivery fixed)
**No SQL to run.** Upload the whole folder again.

* **Exam Analytics removed.** The *📊 Analytics* button, its page (topper list, histogram, wrong-answer list, time per question, Excel) and its code are gone from Results. Everything else in Results (marks table, answer sheet, Excel, Print / PDF, extra time / re-exam) is unchanged.
* **E-mail (Brevo only).** Sender stays `gaddamvenur@gmail.com` (verified in Brevo > Senders & IP). Changes: each student now gets his / her **own** e-mail (own \"To\"; before, all students were hidden BCC copies of a mail addressed to the admin, which Gmail often drops); after sending, the site asks Brevo whether any message was **blocked / bounced / invalid** and then the history shows **failed** with Brevo's reason instead of a false *sent*; Brevo must also return a message id.
* **Admin > Email > Send test e-mail** sends one message to `gaddamvenur@gmail.com`.
* If mails are still blocked or in Spam: Gmail does not trust other services sending as a `@gmail.com` address. Look at Brevo > Transactional > Logs; the lasting fix is to send from an address on your own domain (verify the domain in Brevo, then change `ADMIN_MAIL`).

## What is new in v42  (login photo, timetable fix)
**No SQL to run. The database was not touched, so there is no new SQL file.** Upload the whole folder again (new file: `assets/venu.jpg`).

* **Login page:** the portrait of Gaddam Venu is on the right panel. Wide screens: tall arch-shaped photo card (yellow offset frame, name + *Dept of CSE · Programmer* on a glass label) beside the headline and tiles. Smaller screens and phones: a compact profile strip above the headline. To change the photo, replace `assets/venu.jpg` (720 x 900, portrait) and the name text in `index.html` (`<figcaption>`). Only `index.html`, `login.css` and the new photo changed; the sign-in code is untouched.
* **Timetable was blank – fixed.** `shell.js` already has a global `KINDS` (subject types) and `timetable.html` declared its own `KINDS`, so the browser rejected the whole timetable script (*Identifier 'KINDS' has already been declared*) and nothing was drawn. The timetable name is now `CELLKINDS`.
* **Timetable on phones:** students and the CR now see **one card per day** (period number, time, subject; today is marked; a day with nothing entered shows one line). A **Table view / Day view** button switches to the full table. The admin always gets the editable table. Print / PDF always prints the table.
* A student whose Year + Semester has no timetable now sees the class name in the message (*No timetable has been published for Year 2 · Semester 3 yet*). The old message about the SQL file `17_marks_publish_timetable.sql` now points to `sql/02_functions.sql`.

## What is new in v41  (task submit modes, deadline, visible true / false)
**Existing database: run `sql/05_upgrade_v41.sql` once, then run `sql/02_functions.sql` again.** (New install: the 3 files as before.) Upload the whole folder again.

* **Tasks – how students submit (radio):** *Drive link* (one Google Drive link, as before) or *Button* (one Submit button, no link, no file). Students can undo until the admin marks OK; after "Needs correction" a button task can be pressed again.
* **Tasks – deadline:** ONE field (date + time). Shown on the card, in the e-mail and the notification. A submission after it is marked **Late** (still accepted). Old "last dates" become the deadline (end of that day).
* **visible = true / false:** the admin right-clicks (phone: press and hold) a **tab** or a **card**, types `true` or `false`, Update. `false` = students and CR do not receive it (the database does not send it); the admin sees it dimmed with a "visible = false" label. Works for every tab except Students / CR, and for cards of Syllabus, Lesson Plan, Materials, Video Lessons, Notices, Lab Programs, Tasks and Formats. The dashboard calendar also skips hidden items.
* Limits: hiding **Teams** / **Work** hides only the tab; hiding **Exams** hides the list, a direct exam link still opens.

## What is new in v40  (exams and tasks)
**Existing database: run `sql/04_upgrade_v40.sql` once, then run `sql/02_functions.sql` again.** (New install: the 3 files as before.) Upload the whole folder again.

### Tasks
* The Word upload is **removed**. In every subject (theory, lab, project) a student (a team in projects) submits **one Google Drive link** of the file (Word / PPT / PDF). Folder links are refused.
* The link is **masked**: no page, table, e-mail or Excel shows it, and the lists sent by the database do not contain it. Admin and student open the file with **View** inside the site (full-screen protected viewer: no download button, copy, print or right-click, watermark with the viewer's name). Old Word files sent with v39 stay and can still be downloaded by the admin / the owner.
* For real protection also set the file in Drive to *“Viewers can't download, print or copy”*; a website cannot hide the link from someone who opens the browser developer tools while viewing.

### Exams
* **Exam date is compulsory**: Opens at + Closes at. A student can start only inside that window (the Start button and the database both check it).
* **Earliest Submit**: Submit works only after half of the duration (2-hour exam = after 1 hour). The admin can change the minutes in Settings. Time up and too many warnings still submit automatically.
* **Marks per question**: the Excel has **Marks** and **Negative** columns on every sheet (empty = the section's default). The total marks of the exam are calculated automatically from the rows, and every student's marks are calculated on the server.
* **MSQ** (more than one right answer, answer like `A,C`) with optional **partial marks** (Partial = Y): all right = full marks, only right options ticked = part of the marks, any wrong option = negative marks. Sheets: MCQ, MSQ, Numerical, FillBlank.
* **Shuffle** (default on): every student gets the questions of a section and the options in his / her own order (made by the database when the student starts; the answer sheet shows the order that student saw).
* **Formulas and pictures**: write formulas between `$` signs: `$x^2+\frac{a}{b}$`, `$\sqrt{b^2-4ac}$`, `$\alpha \le \pi$`, `$v_0\times\theta$`. Supported: `^`, `_`, `\frac`, `\sqrt`, Greek letters and common symbols (a light renderer, not full LaTeX: no matrices / `\begin`). A picture = an `https` image link (or a Google Drive image link) in the **Image** column. `_headers` now allows images from any `https` address.
* **Sectional exam (NPTEL style)**: sections one by one, no going back; every section can have its own time (minutes). When a section time ends the next section opens automatically; the questions of later sections are not even sent to the browser, and answers of a closed section cannot change. If every section has a time, the duration = the sum.
* **Analytics** (Results > Analytics): topper list, marks histogram, questions most students got wrong, average time per question, time per question of each student (Excel too). Time per question is counted only while the exam tab is visible.
* **Extra time / re-exam** (Results > Extra time / re-exam): after a power cut give minutes to one student; a finished attempt is **reopened with all answers kept**, the warning count can be reset. A student who never started can be **allowed a late start** after the window closed. Everything is logged.
* **Warning log**: every warning is saved with its time and reason (admin: in the answer sheet).
* **Print / PDF**: result sheet, answer sheet and analytics have **Print / PDF** buttons (use *Save as PDF* in the print window).
* **Results in the student's login**: right after submitting, the result is in *Exams* (rank, correct / partial / wrong), the answer sheet shows each question with the time spent, and a bell notification is created.

## Exams (v39)
Every subject has an **Exams** tab; the bottom menu has **Exams** (admin: history of all exams, search by Exam ID; student: my results).
- **Admin flow:** Create exam (title, duration, optional open/close time, warnings allowed, number of sections, questions per section, + marks and − negative marks per section) -> Download Excel template (3 sheets: MCQ single-correct, Numerical, Fill in the blank) -> Upload the filled file (checked before saving) -> edit / add / delete single questions -> Publish. Students are notified and e-mailed. Results: marks table per exam, answer sheet of every student, Excel export.
- **Student flow:** open the exam link (Exams tab, dashboard, or the link the teacher shares) in a new tab -> read the rules -> type first name + Gmail (must match the login) -> Start: full screen + camera preview -> NPTEL-style paper (section tabs, question palette: answered / not answered / not visited / marked for review) -> Submit. Marks are calculated on the server. The result, the answers and the right / wrong marks appear in the student's login at once (Exams page).
- **Protected exam:** full screen, camera must stay on (live preview only, **nothing is recorded or stored**), Esc / F11 captured where the browser allows it (Chrome / Edge keyboard lock), copy, paste, right-click, print and developer-tool keys blocked, leaving full screen / switching tab / camera off = a warning, after the allowed warnings the exam is submitted automatically, time up = auto-submit, answers autosaved (a student can reopen the link and continue).
- Browsers cannot technically forbid leaving full screen (Firefox / Safari / phones), so those cases are detected and counted as warnings instead.
- Question types: MCQ (single correct), Numerical (with optional tolerance), Fill in the blank (several accepted answers separated by |).

## Subject types
- **Theory only**, **Theory + Lab**: Students, Syllabus, Lesson Plan, Materials, Video Lessons, Marks, Notices, **Tasks (one Drive link per student, viewed inside the site)**, Lab Programs / Lab Marks (lab), CR.
- **Mini Project**, **Major Project**: Students, **Teams**, **Formats**, Notices, **Tasks**, **Work (Drive link)**, CR.
  - Teams: the admin creates teams (name, project title, guide, members, leader) or auto-makes teams of N students.
  - Formats: the admin posts report / PPT / code formats as Drive links.
  - Tasks: the admin posts a task (notice format); each team submits ONE Google Drive link; admin: Open / Download, Mark OK, marks, needs correction, remove.
  - Work: students post Code / Report / PPT / Other as a Google Drive link; the admin sees every post with Open + Download buttons.
  - Only Google Drive / Docs links are accepted (checked in the database too).

## Students
Login = Gmail + password. Required: name, Gmail, password (6+), mobile. Optional: Reg No, parent mobile. Forgot password: Gmail only (password becomes the mobile number).

---
# Gaddam Venu – Classroom Portal (v36)

## v36 changes  (run SQL file `sql/17_marks_publish_timetable.sql` once)
- **Marks: Publish.** Every new Theory / Lab Marks sheet is hidden from students and the CR until the admin presses **Publish to students** (bell notification is sent). **Unpublish** hides it again. Sheets that existed before stay visible.
- **Marks: Import.** **⬆ Import** reads marks pasted from Excel or an .xlsx / .xls / .csv file (row 1 = headings, one heading = Reg No). Check first, then Import. New headings can become new columns; empty cells keep the old mark; wrong marks block the import.
- **Timetable** (menu: Timetable): one timetable for each Year + Semester, Monday to Saturday, 9 periods (9.00 to 4.30). The admin edits every cell, merges periods (a Lab = 3 periods, 9.00 to 11.30), edits the period times, copies / clears a day, downloads Excel (merged cells kept) or prints. A student sees the timetable of his / her own year + semester; the CR can open any.
- Student marks are shown as a list (no sideways scrolling), smaller consistent buttons, shorter note on the marks page, **Both batches** option for Lab Programs.

## v35 changes
**No SQL. Database not touched.**
* **Inside pages are back to the original white theme** (white background, navy menu, yellow buttons, black / yellow tabs as before v33). The dark inside theme of v33 / v34 and the "Theme color" dots in the menu were removed. The lamp login page keeps its look.
* Everything else of v33 / v34 stays: one login for everybody, row colors, row conditions, column conditions.

## v34 changes
**No SQL to run. The database was not touched, so there is no new SQL file.** (Stored in the existing `mark_sheets.row_colors` field as `rowr`.)
* **Lab Marks – Row conditions:** new button **🎨 Row conditions**. The admin chooses ONE deciding column (for example Total) and writes rules (same conditions as column colors, e.g. *less than 11 = red*, *less than 16 = blue*, *16 or more = green*). The WHOLE ROW is tinted by the first rule that fits that column's value.
* **Priority:** a color set by hand on a specific row (round swatch / 🎨 Row colors) wins over the row conditions; a column rule color wins inside its own cell. The legend under the table shows the row rule too. PDF and Word keep these colors.
* So Lab Marks now has: specific row colors (by hand), row conditions (whole row by one column), and column conditions (cell by its own column).

## v33 changes
## v33 changes
**No SQL to run. The database was not touched, so there is no new SQL file in v33.** (The new colors are stored in the existing `mark_sheets.row_colors` field, which accepts them as it is.)
* **One login for everybody:** the *Student* / *Admin* tabs are removed. There is ONE form (*Reg No / Username* + *Password*). The same database function `unified_login` finds out by itself whether it is an admin, a CR or a student, and the *Forgot password?* link is always shown. The lamp, the six lamp colors and the top bar are unchanged.
* **Inside pages in the same look as the login:** dark glass cards, the accent color of the lamp (Amber, Cyan, Rose, Mint, Violet, Moonlight) on the active menu button, tabs, primary buttons, calendar and fields. The color chosen on the login page is kept inside the site and after logout; it can also be changed in the menu (*Theme color*). Only `style.css` (new section 13), `app.js`, `shell.js` changed for this: no page structure and no database call. The marks table stays a light "sheet" so the cell colors look the same as in the PDF / Word download.
* **Lab Marks colors:**
  * **Row colors** (by hand) stay: the round swatch at the start of a row, or the new button **🎨 Row colors**.
  * **Column colors are now condition based:** the fixed one-color-per-column swatch was removed. Button **🎨 Column colors** (or the 🎨 in a column heading) opens rules for the chosen column, for example *less than 11 = red*, *less than 16 = blue*, *16 or more = green*. Conditions: less than, less than or equal, greater than, greater than or equal, equal to, between, is AB, every cell. Up to 8 rules per column; the first rule that fits a cell gives its color. Works for marks columns and formula columns (Total). **Quick: red / blue / green**, **Copy these rules to all columns** and **Remove all column colors** are there.
  * A cell colored by a rule is solid with black or white text; a legend under the table shows the rules to the admin, CR and students. A cell from a row color and a column rule: the rule color shows.
  * PDF and Word downloads keep the row colors and the rule colors (cell by cell). Excel keeps the formulas only.
  * Old one-color column settings from v32 (`colc`) are no longer used and are dropped the next time colors are saved. Row colors from v32 continue to work.
* Instructions page: section 10 rewritten.

## v32 changes
**No SQL to run. The database was not touched.**
* **New login page (`index.html` + `login.css`):** an interactive lamp. Click the lamp (or its cord) to switch the light on / off. Six lamp colors (Amber, Cyan, Rose, Mint, Violet, Moonlight) – the whole page (tabs, button, glow, floating dust) follows the color; the last color is remembered on that phone. **Student** and **Admin** tabs, a compact card, all extra text removed (no sub-title, no footer, no feature chips). The Admin tab shows *Username*, the Student tab shows *Reg No* and the *Forgot?* link. Strict check: an admin account on the Student tab (or a student on the Admin tab) is refused and the session is closed. A CR logs in on the Student tab. The same database function `unified_login` is used. Layout: lamp on the left and card on the right on a computer; lamp above the card on a phone, always one screen without scrolling. Only system fonts are used, because the site's security policy (`_headers`) does not allow web fonts. The calculator, Android app and refresh buttons are small icons in the top bar.
* **Lab Marks colors are now set by the admin:** the automatic colors by Total (red / blue / green) and their legend were removed, and the pale yellow of the formula column too. Nothing is colored until the admin chooses:
  * **each row separately** – the round swatch at the start of the row;
  * **each column separately** – the round swatch in the column header (the header becomes that color);
  * **🎨 Colors** window – every row and every column in one list, **Set all rows / Set all columns**, ✕ (no color), **Clear all**, **Remove all colors**.
  * In a crossing cell the column color shows. Everybody who can see the marks sees the same colors. PDF and Word keep the colors; Excel keeps the formulas only.
  * Stored in the existing `mark_sheets.row_colors` field as `rowc` (student id → color) and `colc` (column id → color). The old fields `on / col / rows` are still written because `marks_rules_save` checks them, but they are ignored. Needs `sql/14_marks_row_colors.sql` from v28 (already run if you used v28 or later).
* **Phones:** the marks toolbar is a compact grid (Add column + Colors, then Excel / PDF / Word, then Delete), smaller cell padding.
* Instructions page: section 10 rewritten (Colors). Theory Marks is unchanged.

## v31 changes
* **Batches are only for Lab Programs.** The batch buttons, the B1 / B2 tags and the batch-wise downloads were removed from **Lab Marks**; Lab Marks is the same as in v29 (all students, row colors by Total). No new SQL in v31: run `sql/16_lab_batches.sql` (from v30) once if you have not.

## v30 changes
* **Lab batches (Theory + Lab subjects):** in **Lab Programs** the admin first creates **Batch 1** and **Batch 2**: button **+ Create batches** (later **✎ Edit batches**). Choose the batch of every student, or type / paste the Reg Nos of each batch and press **Apply the typed Reg Nos**; **Split in half** and **Clear all** are there too. A student can be in one batch only. Each batch has its own color (default Batch 1 blue, Batch 2 yellow; the admin can change them).
* **Lab Programs – batch first:** the form now starts with **Batch (1 or 2)**, then Lab number, Date, Time, Lab location, Title, Drive link / code and What to do. The program is shown only to the students of that batch (admin and CR see all) and the **e-mail goes only to the students of that batch** (the e-mail says which batch). The bell notification also goes only to that batch. Lab programs posted before v30 have no batch and stay visible to everybody. Until the batches are created the form is hidden and a yellow *Step 1: create the batches* box is shown. The lab list has batch filter buttons (All / Batch 1 / Batch 2), each program shows a colored batch tag and a colored left edge, and a student sees “You are in Batch 1”.
* **SQL:** NEW file `sql/16_lab_batches.sql` – run it ONCE (after 08 to 15, keeps all data, safe to run again). Old files 01 to 15 are not changed. It adds `labs.batch`, `subjects.batch_colors`, the table `lab_batch_members`, the functions `batches_get` and `batches_save`, and replaces `subject_content` (a student gets only his / her batch's lab programs) and `lab_add` (new last value: the batch). **Run it before posting lab programs with v30**, because the new site sends the batch to `lab_add`. `00_ALL_IN_ONE_new_install.sql` already contains it (ONE single file, everything up to v30).
* Instructions page: new section **14. Lab batches**.
* If you ever run `sql/02_functions.sql` again, run `sql/16_lab_batches.sql` again after it (02 contains the older `subject_content` / `lab_add`).
* If a student is removed from the subject and added again, he / she returns to the same batch (the batch list is kept per subject).

## v29 changes
* **Add a column at any place (Theory Marks and Lab Marks):** **+ Add column** has a new choice **Where to add this column**: at the end (default), at the very beginning, or before any column. The column letters list in the window shows the letters after the insert. The column letters inside the OTHER formulas (like `C5:H5`) are updated automatically, as in Excel, so the totals stay correct; a column added inside a range joins that range; formulas that use `[names]` never change. Marks already entered are kept. No SQL change is needed for this.
* **Instructions page updated:** new section "Adding a column at any place", a table of the three ways to refer to columns (`[Name]`, `C5`, `C5:H5`), more formula examples, a table of all functions with examples, and a new section "If a formula shows Err or is refused". All examples were checked against the formula engine.
* **Lab Marks – description for every column:** in the column window (⚙ on a column, or **+ Add column**) there is a new optional field **Description of this column** (up to 200 characters, for example *Record work of experiments 1 to 5*). It is shown in small text under the column name in the table, to the admin, the CR and the student, and in the row **View** window. Works for marks columns and formula columns. Empty = nothing is shown. Theory Marks is unchanged.
* **SQL:** NEW file `sql/15_marks_column_description.sql` – run it ONCE (after 09 to 14, keeps all data, safe to run again). Old files 01 to 14 are not changed. It only makes the database check the description (text, at most 200 characters); no table changes. `00_ALL_IN_ONE_new_install.sql` already contains it (ONE single file, everything up to v29).

## v28 changes
* **Clear table format (Theory Marks and Lab Marks):** full grid lines on every cell, a dark header row (column letters A, B, C… in yellow, formula columns in a lighter blue with a yellow underline), striped rows, centered marks, the header stays visible while you scroll down and Reg No stays visible when you scroll sideways (Name too on a wide screen). PDF and Word downloads also have grid lines.
* **Row colors (Lab Marks only):** the WHOLE ROW (not a column) is colored by the **Total** marks. The Total cell is solid, the rest of the row is a light tint, and a legend is shown under the table. Defaults: **below 11 = red**, **11 to 15 = blue**, **16 and above = green**. A row with no marks entered has no color.
* **Admin can change it (not fixed):** Lab Marks has a new button **🎨 Row colors**. The admin can switch the colors on / off, choose the column that decides (Total by default), change the colors with the color picker, change the marks ranges, add (up to 10) or remove ranges, or go back to the default colors. It is saved per Lab Marks subject and everybody who can see the marks (admin, CR, the student's own row) sees the same colors. Theory Marks has no row colors.
* **Downloads:** PDF and Word keep the row colors. Excel keeps the live formulas but has no row colors.
* **SQL:** NEW file `sql/14_marks_row_colors.sql` – run it ONCE (after 09 to 13, keeps all data, safe to run again). Old SQL files 01 to 13 are not changed. Until you run it the site already shows the default colors, but saving changes in 🎨 Row colors needs it (the site tells you if it is missing).
* **`sql/00_ALL_IN_ONE_new_install.sql` is rewritten as ONE single file** with everything up to v28 in the final form: tables, functions, admin, notices / lab programs and all marks features (formula rules, column maximum, AAT 1, AB absent, CR view, row colors). A new install needs only this one file (it deletes all data first).
* Instructions page has a new section **8. Row colors**.

## v27 changes
* **Login page:** one button **R24 and R26 Calculator** at the top right corner (no login needed) opens `calculator.html` (short links `/calculator`, `/r24`, `/r26`). One page for both regulations, same formulas (`calc.js`), horizontal layout (`calc.css`): all marks fields and the Calculate button in one row on a wide screen, wrapping on a phone. Footer: *Developed by G.VENU*, *Dept of CSE (Programmer)*. The feature chips under the login box were removed.
* **E-mail:** the Brevo box (sender, API key message, test button) is removed from the Email page. The same message goes to the students in ONE Brevo request (BCC, up to 95 per request), and the history shows ONE line per message ("All students of this subject (45)") with the message text, not one line per address. **Notices:** new choice *E-mail this notice to: All students / Specific students* (tick the students; the notice itself is posted as usual). No SQL change. Old history lines (one per student) can be removed with *Clear all*.
* **Dashboard:** the admin's "Recent activity" list is removed.
* **CR login:** can now VIEW the marks of all students in Theory Marks and Lab Marks (view only: no add, edit, delete or download). Needs the NEW file `sql/13_marks_cr_view.sql` (run once, after 12).
* **Removed:** the "Enter marks in table" feature (use ✎ on a column or Edit on a row).
* **AB (absent):** type `AB` as a mark. It is shown as AB and formulas ignore that cell in that student's row (also in the Excel download: AB counts as 0 in + - * / and comparisons, and SUM / AVERAGE / MAX / MIN skip it). Needs the NEW file `sql/12_marks_absent_ab.sql` (run once, after 11).
* **Instructions page:** `instructions.html` (button **📘 Instructions** in the column window) explains formulas, AB, column letters, OUTOF and downloads. The long help text was removed from the column window; the column letters stay there.
* **Theory Marks / Lab Marks – column edit:** every marks column has a **✎** in its header: type or change that one column for all students in one list, with **Fill all** and **Clear all**. **⚙** stays for the column settings. The existing row **View / Edit / Delete** and **Enter marks in table** are unchanged.
* **Maximum marks per column (optional):** set it in ⚙ (for example Lab 1 = 25). Entering more than the maximum is blocked, and formulas can use it: `=SUM([Lab 1],[Lab 2])*15/(OUTOF([Lab 1])+OUTOF([Lab 2]))`. In *Quick build*, SUM + **Scale to** writes this formula for you. Excel download keeps the formula (the maximum is written as a number).
* **Theory Marks:** a new sheet starts with only the inbuilt, mandatory **AAT 1** column (maximum 10, 🔒 cannot be renamed or deleted). All other columns are added by the admin. Old sheets are not changed, except that AAT 1 is added at the end if it is missing.
* **SQL:** run the NEW file `sql/11_marks_column_max.sql` once in Supabase (after 09 and 10). Old SQL files are unchanged. It adds database checks for the column maximum, the mandatory AAT 1 and marks above the maximum. The site works without it, but the checks are then done only by the website.

# (older notes) Materials Portal (v26)
Plain HTML + CSS + JavaScript. Backend: **Supabase**. E-mail: **Brevo**. Hosting: **Netlify**. Installable on phones (PWA / APK-ready).
Developed by Gaddam Venu.

## v26 changes
**Run three new SQL files once (Supabase > SQL Editor), in this order:** `sql/08_notice_labs_update.sql`, `sql/09_marks_tables.sql`, `sql/10_marks_formula_rules.sql`. They keep all data. (New install: `00_ALL_IN_ONE_new_install.sql` already contains them.)

* **E-mail uses Brevo (EmailJS removed).** Put the key in `config.js`: `const BREVO_API_KEY = 'xkeysib-...';`. Sender = `ADMIN_MAIL` (must be verified in Brevo > Senders & IP). Mail goes only to the students of the subject (BCC, admin shown in "To"), only for **Notice, Lab Program, Video Lessons**. Admin > Email shows if the key is found, has a test button and the history.
  * `config.js` is downloaded by every visitor's browser, so the key is readable by anybody who looks. Use a Brevo key made only for this site and delete it in Brevo if it leaks.
  * If Brevo answers "unrecognised IP address", open Brevo > Security > Authorised IPs and deactivate the IP blocking. If the browser reports a CORS / network error, Brevo refuses direct browser calls and the key must move to a server function (`mail()` in `app.js` is the only place to change).
* **Notices:** date only (no time). Message box with Bold, Italic, Underline, Left / Centre / Right / Justify, Bullets, Numbers, Heading. Shown on the site and in the e-mail.
* **Lab programs:** Lab number drop-down (Lab 1 to Lab 50 or "Other number"), date, time-slot drop-down (`LAB_SLOTS` in `config.js`), **lab location typed freely**, Drive link and / or code. The e-mail has only the lab details (no link, no code).
* **Theory Marks** (was "Marks Share") **and Lab Marks are tables.** Every student of the subject is a row; the admin adds columns. Theory starts with AAT 1, AAT 2, AAT 3, Mid 1, Mid 2, Total.
  * **Formulas work like Excel:** `=ROUNDUP(SUM(C5:N5)*20/230,0)`, `=AVERAGE(C2:D2)`, `=IF([Total]>=40,"Pass","Fail")`, `=[AAT 1]+[AAT 2]`. Functions: SUM AVERAGE MAX MIN COUNT ROUND ROUNDUP ROUNDDOWN INT ABS MOD POWER SQRT CEILING FLOOR IF AND OR NOT. Operators + - * / ^ % and = <> < > <= >=.
  * **Column letters** are shown above every column: A = Reg No, B = Name, C = first column, D = second ... The **row number is ignored** (C68:N68 means columns C to N of each student's own row). A formula can use another formula column, so Total, more columns, another Total works.
  * The admin enters marks in the table, can View / Edit / Delete each row, edit or delete columns, and downloads **Excel (live formulas with the real row numbers), PDF, Word**. A student sees only his / her own row. No e-mail for marks.
  * Deleting a column moves the letters of the columns after it, so check formulas that use letters. Formulas that use `[Column name]` follow renames.

## What is new in v24 - Semester, mobile numbers, profile photos
* **Add student** now asks for **Semester (1 to 8)**, **Student mobile number** and **Parent mobile number** (10 digits; +91 / spaces are ignored).
  Same fields in Excel upload (`RegNo, Name, Email, Year, Semester, Mobile, ParentMobile, Password`), the typed list and the Edit popup.
* Semester, Mobile and Parent Mobile show in the student tables (subject page and Admin > Students), in search, in the View popup and in the Excel / PDF / Word download. Admin > Students can filter by semester.
* **Profile photos**: the admin sees the photos of students and CRs; the CR sees student photos; students and CRs see the admin's and the CR's photo at the top of the subject page. Click any photo to enlarge it.
* **Database change: run `sql/07_add_semester_mobile_photos.sql` once** (keeps all data). New install: 00 / 01 / 02 already include it.

## What is new in v23 (was v22) – Download App button
* Login page: an orange **Download App** button (top-left, opposite Refresh) opens the APK download page in a new tab. The link is `APK_URL` in `config.js` (change it there if the APK link changes). The button is hidden inside the installed app. No database change.

## What was new in v21 – protected document viewer
* In Syllabus, Lesson Plan, Materials, Marks Share and Lab Sheet the students/CR get a **View** button: the Google Drive file (PDF, Word, PPT, Excel) opens **inside the website** in a full-screen viewer. The admin also has **Open in Drive**.
* Inside the viewer: no right-click, no copy / cut / select, Ctrl+P / Ctrl+S / Ctrl+C blocked, the "open in new window" icon of Drive is covered, downloads and print dialogs are blocked in the frame, the page cannot be printed (print shows blank), and a faint watermark with the viewer's name + subject is drawn over the file.
* **Important – do this in Google Drive for real protection:** open the file > Share > Settings (gear icon) > untick **“Viewers and commenters can see the option to download, print, and copy”**. A website can only hide the buttons; Drive itself must switch them off.
* Links that are not Google Drive links still open normally in a new tab.
* No database change in v21. (Run `sql/06_add_syllabus_lesson_plan.sql` once if you have not yet, for v20.)

## What was new in v20 – Syllabus and Lesson Plan tabs
Two new tabs in every subject, right after **Students**. Tab order now:
* **Theory only:** Students · Syllabus · Lesson Plan · Materials · Video Lessons · Marks Share · Notices (+ CR for the admin)
* **Theory + Lab:** Students · Syllabus · Lesson Plan · Materials · Video Lessons · Marks Share · Notices · Lab Programs · Lab Sheet (+ CR for the admin)
* **Syllabus** = *Theory Syllabus* (+ *Lab Syllabus* in Theory + Lab subjects). **Lesson Plan** = *Theory Lesson Plan* (+ *Lab Lesson Plan* in Theory + Lab subjects). Drive links, same as Materials; every student gets an e-mail when you post.
* Addresses: `/subject/DS-2026-2027/syllabus` and `/subject/DS-2026-2027/lessonplan`.
* **Database:** run the ONE new file `sql/06_add_syllabus_lesson_plan.sql` (keeps all data). New installs: `00_ALL_IN_ONE_new_install.sql` already includes it.

## What was new in v19
* **New login page design:** dark glass look in the logo colours (navy, cyan glow, orange), big logo and name on top, glass card with icons, gradient Login button, Refresh button top-right. Phone view included.
* **Refresh button on every page:** login page, and every page after login (floating button top-right on computers, icon in the top bar on phones, icon in the left menu).
* No database change.

## What was new in v18
* **New login page layout:** logo top-left, **Refresh** button top-right, the login card in the middle, soft background with big colour circles (same colours as the logo). Phone view included.
* **Refresh button** on the login page and inside the app (in the left menu, and in the top bar on phones) for admin, CR and students. It clears the stored copy of the site and reloads, so the newest version is loaded (useful in the installed app / APK).
* No database change in v18.

## What was new in v17 – clean URLs
No ids and no `.html` in the address bar any more:
| Page | Address |
|---|---|
| Login | `/` |
| Dashboard | `/dashboard` |
| Create Subject | `/subjects` |
| Students | `/students` |
| Email | `/email` |
| A subject | `/subject/DS-2026-2027` and its tabs `/subject/DS-2026-2027/materials` · `/videos` · `/marks` · `/notices` · `/labs` · `/labsheet` · `/students` · `/crs` |

The address follows the tab you open. Old links (`subject.html?id=...`) still open and are changed to the clean form automatically. The rewrite rules are in `_redirects` (Netlify). Upload this file with the site.

## What was new in v15
* **New logo** (high resolution) and the credit line "Developed by Gaddam Venu" everywhere (pages, e-mail template, config).

## What was new in v14
* **New logo** (`assets/logo.png`, icons) and admin name **Gaddam Venu**.
* **Subject code with the academic year:** `DS-2026-2027` (you type the start year 2026). Old codes are converted by `04_update_existing_database.sql`.
* **Subject type when creating a subject:** *Theory only* or *Theory + Lab* (can be changed in Edit).
  * Theory only: Students · Materials · Video Lessons · **Marks Share** · Notices (+ CR for the admin)
  * Theory + Lab: the same + **Lab Programs** + **Lab Sheet** (lab marks sheet link)
  * Materials = Unit 1–6. Marks Share = Mid 1, Mid 2, AAT1, AAT2. Lab Sheet = lab marks. Existing links are sorted into these tabs by their category.
  * Every post (material, marks, video, notice, lab program, lab sheet) e-mails all students of that subject.
* **Profile photo** for admin, CR and students: click your picture (left side / top bar) > Change photo. The admin sees the students' and CRs' photos in the student and CR tables.
* **Passwords**
  * Add student / Excel / typed lines now have a **Password** column. Empty = the Reg No (capital, small or mixed letters all work at login).
  * A **student can change his / her own password** (profile > Change password) or never touch it. A password chosen by the student is not readable by the admin (the admin can Reset it).
  * A **CR cannot change the password**: only the admin sets / edits / resets it (empty = the CR ID).
  * Forgot password (login page): Reg No only, the password goes back to the Reg No.
* **Login page:** the field is simply called *Login*, the note under the form is gone, the password has an eye icon.
* **Dashboard:** every card is a link (admin: subjects / students / e-mail pages; student & CR: their subject or the subject list).

## 1. Setup (SQL) - full instructions are also in `sql/START_HERE.txt`
In Supabase > SQL Editor, paste a whole file, press Run, one file at a time:

**New / empty project (deletes everything):** run `sql/00_ALL_IN_ONE_new_install.sql` (tables + functions + admin).

**Project already running v12 / v13 / v14 (keeps your data):** run in this order
1. `sql/04_update_existing_database.sql`
2. `sql/02_functions.sql`
3. `sql/03_admin_seed.sql`
4. optional: `sql/05_optional_passwords_to_regno.sql` (all student passwords back to the Reg No)

Error "Could not find the function ... in the schema cache": run `sql/99_refresh_api_cache.sql`.
Then upload everything except `sql/`, `README.md`, `EMAILJS_TEMPLATE.txt` and `email-templates/` to Netlify. Put the new EmailJS keys in `config.js` later (see `EMAILJS_TEMPLATE.txt`).

## 2. Logins
| Who | Login | Password |
|---|---|---|
| Admin | `gaddamvenur@gmail.com` | `nagarjuna@2009` (change in `sql/03_admin_seed.sql`, run it again) |
| CR | the ID the admin gives, e.g. `CSE-CR` | set by the admin only |
| Student | Reg No | set by admin / Excel, empty = Reg No; the student may change it |

5 wrong tries lock that ID for 15 minutes.

## 3. E-mail (EmailJS)
One template only (`email-templates/notice.html`), sent only when content is posted. Keys in `config.js`: `EJS_PUBLIC`, `EJS_SERVICE`, `EJS_TEMPLATE_NOTICE`. Admin > Email has a test button and the history.

## 4. Notes
* Passwords are stored hashed and (except those chosen by the student) as readable text for the admin. Keep the admin login private.
* Forgot password needs only the Reg No, so anybody who knows a Reg No can reset that student's password back to the Reg No. A password the student chose is therefore only as private as the Reg No is secret.
* Profile photos are stored in the database as small JPEG text (about 5–10 KB each), no Storage bucket needed.
* Deleting a subject deletes its files, videos, notices, lab programs and the students / CRs that are in no other subject.


## v49 changes
* E-mail now goes for **every category**: Syllabus, Lesson Plan and Materials (when posted) and Theory Marks / Lab Marks (when you press Publish) join Notice, Task, Lab Program, Lab Manual, Video Lessons, Exams, Formats and Zoom Meeting. The marks e-mail only says the marks are published; it never contains marks.

## v25 changes
* (older, replaced in v49) E-mail only for Notice, Lab Program and Video Lessons.
* One e-mail goes to all students of the subject at a time (BCC). Information only - no links. New template: `email-templates/notice.html` (paste it again in EmailJS and add `{{bcc}}` in the template's Bcc field, see EMAILJS_TEMPLATE.txt).
* CR / Admin name strip removed from the subject header (the CR tab for the admin stays).
* Video Lessons form now shows the labels "Lesson title" and "Video link".
* Notifications (bell + page + "Latest updates" list) removed for all logins.
* Footer line is bold on every page.
