# Deploy on Netlify (GitHub -> Netlify)

## FIRST: why e-mail works in the Nagarjuna app but not here (analysis)
Both projects have the SAME e-mail design: the page calls `/.netlify/functions/send-email`, and that function calls Brevo.
The Nagarjuna site works because it is a real **GitHub -> Netlify** site (its folder has a `.git` that points to GitHub, so Netlify builds the function and has the 3 BREVO_ variables).
Here the function was not reachable: the site was opened from a folder / local server / an upload without the function ("not found", "Failed to fetch").
What was also different, and is now the same as the working app: the working app sends **one plain Brevo request (admin in "To", students in BCC)**; this project used a newer per-student format plus a 4-second delivery re-check that could mark a good send as failed. Both are now removed/aligned.

### Make it work exactly like the Nagarjuna site (10 minutes)
1. Put this whole folder on GitHub (section B below).
2. Netlify -> Add new project -> Import from GitHub -> pick this repo (section C). Leave the build boxes alone (they come from `netlify.toml`).
3. Netlify -> Project configuration -> Environment variables: add only these three, with the SAME values as the working Nagarjuna site (open that site's Netlify settings and copy them):
   `BREVO_API_KEY`, `BREVO_SENDER_EMAIL`, `BREVO_SENDER_NAME`
   **Do NOT copy `SB_URL` / `SB_KEY` from the Nagarjuna site**: they belong to the Nagarjuna database. Leave them empty here; this project uses the values in its own `config.js`.
4. Deploys -> Trigger deploy -> Clear cache and deploy site. Wait for green "Published".
5. Open `https://YOUR-SITE.netlify.app/.netlify/functions/send-email` : you must see `{"ok":true,...,"ready":true}`.
6. Log in as admin on that address -> Email -> **Check e-mail setup** -> **Send test e-mail**.
Always use the Netlify address (https://...netlify.app), not a file on your computer.

### No Netlify at all? Use the database route
Run `sql/10_upgrade_v48.sql` once in Supabase, then Email -> E-mail settings: paste the Brevo key + sender. E-mail then works on any address (same Brevo request, sent by the database).

## A. Run it on your computer
1. Install Node.js (LTS) from nodejs.org.
2. Copy `.env.example` to `.env` and fill the values (the file is ignored by git).
3. In PowerShell inside the project folder:
   `npx netlify-cli dev`
   Open the address it prints (http://localhost:8888). Pages AND e-mail work, exactly like the live site.
   (VS Code "Live Server" also opens the pages, but e-mail will not work there because there is no function.)

## B. Push to GitHub (fresh history, no old key)
    cd C:\Users\venur\Documents\gaddamvenu
    Remove-Item -Recurse -Force .git
    git init
    git add .
    git commit -m "v46 netlify"
    git branch -M main
    git remote add origin https://github.com/<your-user>/gaddamvenu.git
    git push -u origin main --force

## C. Netlify
1. app.netlify.com -> Add new project -> Import an existing project -> GitHub -> choose `gaddamvenu`, branch `main`.
2. Build settings are read from `netlify.toml`  (build command `node scripts/build-config.js`, publish directory `.`, functions `netlify/functions`). Leave the boxes as they are.
3. BEFORE the first deploy (or then "Trigger deploy"), Project configuration -> Environment variables -> add:

| Name | Value | Mark "Contains secret values" |
|---|---|---|
| BREVO_API_KEY | your NEW Brevo key | YES |
| BREVO_SENDER_EMAIL | verified sender e-mail | no |
| BREVO_SENDER_NAME | Gaddam Venu | no |
| BREVO_REPLY_TO | reply-to e-mail (optional) | no |
| SB_URL | (optional) this project's Supabase URL - leave empty to use config.js | no |
| SB_KEY | (optional) this project's anon key - leave empty to use config.js | no |
| ADMIN_MAIL | admin mailbox (optional) | no |

4. Brevo -> Security -> Authorised IPs: switch OFF (Netlify has no fixed IP).
5. Deploy -> open the site -> login as admin -> Email -> **Check e-mail setup** (shows what is missing) -> "Send test e-mail".
6. **After adding or changing a variable, deploy again** (Deploys -> Trigger deploy -> Clear cache and deploy site). The function only sees new values after a new deploy.

## E-mail: the EASY way (works on any address, recommended)
No Netlify function, no environment variables, and it also works from Live Server or a folder on your computer.
1. Supabase > SQL editor > run `sql/10_upgrade_v48.sql` once.
2. Brevo > SMTP & API > API keys > generate a key. Brevo > Senders, Domains & Dedicated IPs > add + verify your sender e-mail. Brevo > Security > Authorised IPs > OFF.
3. Site > login as admin > **Email** > "E-mail settings": paste the key, type the sender e-mail, **Save settings**.
4. Press **Check e-mail setup**, then **Send test e-mail**.
The key is stored in a database table that the browser cannot read (it is never sent back to the page). Once saved, the site uses this route automatically; the Netlify function below is only the fallback.

## D. "E-mail function was not found" / "Failed to fetch" (Netlify function route) / mail failed
Quick test: open `https://YOUR-SITE/.netlify/functions/send-email` in the browser. You should see `{"ok":true,"function":"send-email",...}`.
If you get "Page not found", the function is not in the live deploy. Check, in this order:
1. **Deploy method.** Use GitHub -> Netlify (section B/C) or `npx netlify-cli deploy --prod`. Drag-and-drop of a folder does NOT build the function.
2. **Deploys tab.** The newest deploy must be green "Published". A red deploy = the old site is still live. If the log says *"Secrets scanning found secrets"*, that was the cause: `netlify.toml` now ignores BREVO_SENDER_NAME / BREVO_SENDER_EMAIL / BREVO_REPLY_TO. Deploy again.
3. **Functions tab.** `send-email` must be listed. If not, the folder `netlify/functions/send-email.js` was not uploaded.
4. You opened the site with Live Server / file://? Then there is no function. Use `npx netlify-cli dev` (section A).
5. Environment variables must be set for **Functions** (scope "All" is fine).

If the test page shows `"ready":false`, BREVO_API_KEY or BREVO_SENDER_EMAIL is missing: add it and deploy again.
Brevo side: the sender e-mail must be verified (Senders, Domains & Dedicated IPs), Authorised IPs must be OFF, and the free plan sends about 300 e-mails a day.

