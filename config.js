
/* ---- Supabase (database) ----
   Supabase dashboard > Project Settings > API
     SB_URL = "Project URL"
     SB_KEY = "anon / public" key   (never use the service_role key here)      */
const SB_URL = 'https://ngyhutiovvnwssnlzxxi.supabase.co';
const SB_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5neWh1dGlvdnZud3Nzbmx6eHhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM1MjkxNzgsImV4cCI6MjEwOTEwNTE3OH0.3_luhWuv3J-g-5CSvG__uZ_ZRSY_zD1nPWG36eYVjjw';

/* ---- Admin mailbox ----
   Used as the reply-to address of every e-mail and shown in the e-mail footer.  */
const ADMIN_MAIL = 'gaddamvenur@gmail.com';

/* ---- Names shown on the site and in e-mails ---- */
const ORG_NAME = 'Gaddam Venu';
const DEVELOPERS = 'Gaddam Venu';

/* ---- Android app (APK) download link, shown on the login page ---- */
const APK_URL = 'https://web2apkpro.com/download/E80D08C/GADDAM-VENU';

/* ---- E-mail (Brevo) ----
   NO key here any more. The Brevo key is kept in Netlify > Environment variables
   (BREVO_API_KEY, BREVO_SENDER_EMAIL, BREVO_SENDER_NAME) and used only by
   netlify/functions/send-email.js, so it is never sent to the browser or to GitHub.   */

/* NOTE: on Netlify, the environment variables SB_URL, SB_KEY, ADMIN_MAIL, ORG_NAME, DEVELOPERS and APK_URL
   (if you add them) replace the values above at deploy time (scripts/build-config.js). */

/* ---- Lab programs: time-slot drop-down (edit if the periods change). The lab location is typed by the admin. ---- */
const LAB_SLOTS = ['9.00 AM to 11.30 AM', '11.30 AM to 2.00 PM', '2.00 PM to 4.30 PM'];
