/* ==========================================================================
   app.js  –  helpers shared by every page (loaded after config.js)
   ========================================================================== */
/* forget everything about the login (token, name ...) */
function wipeLocal() { try { localStorage.clear(); } catch (e) {} }

const BASE = document.currentScript.src.replace(/[^/]*$/, '');      // site root, e.g. https://yoursite.netlify.app/
/* Netlify gives clean links (/dashboard, /subject/DS-2026). A plain local server (Live Server, python, file://) does not,
   so on this computer the real .html files are used. page() and subUrl() build the right link in both places. */
const LOCAL = /^(localhost|127\.\d+\.\d+\.\d+|\[::1\]|::1|)$/.test(location.hostname) || /^(192\.168|10)\./.test(location.hostname);
const page = n => BASE + n + (LOCAL ? '.html' : '');
const subUrl = (code, tab) => LOCAL ? BASE + 'subject.html?code=' + encodeURIComponent(code) + (tab ? '&tab=' + encodeURIComponent(tab) : '')
                                    : BASE + 'subject/' + encodeURIComponent(code) + (tab ? '/' + encodeURIComponent(tab) : '');
const HOME = BASE + (LOCAL ? 'index.html' : '');                       // login page
const db = supabase.createClient(SB_URL, SB_KEY);
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const tok = () => localStorage.ng_tok;
const ROLE = localStorage.ng_role;                                   // 'admin' | 'cr' | 'student'

/* call a database function (no token) */
async function rpc(f, a = {}) {
  const { data, error } = await db.rpc(f, a);
  if (error) throw new Error(error.message);
  return data;
}
/* call a database function WITH the login token; expired session -> back to login */
const T = (f, a = {}) => rpc(f, { t: tok(), ...a }).catch(e => {
  if (/unauthorized/.test(e.message)) { wipeLocal(); location.href = HOME; }
  throw e;
});

function toast(m, bad) {
  const d = document.createElement('div');
  d.className = 'toast' + (bad ? ' bad' : '');
  d.textContent = m; document.body.append(d);
  setTimeout(() => d.remove(), 3800);
}
function logout() { rpc('logout', { t: tok() }).catch(() => {}); wipeLocal(); location.href = HOME; }

/* run an async action: disables the button meanwhile, shows errors as a toast */
const run = async (fn, b) => {
  try { b && (b.disabled = true); await fn(); }
  catch (e) { toast(e.message || String(e), 1); }
  finally { b && (b.disabled = false); }
};

const fmtDate = d => d ? new Date(String(d).slice(0, 10) + 'T00:00').toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : '';
const fmtTime = t => t ? new Date('1970-01-01T' + String(t).slice(0, 5)).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' }) : '';
const fmtDT = d => d ? new Date(d).toLocaleString('en-IN', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '';
const dt = (d, t) => d ? fmtDate(d) + (t ? ' · ' + fmtTime(t) : '') : '';
const initials = n => String(n || '?').trim().split(/\s+/).slice(0, 2).map(w => w[0]).join('').toUpperCase();

/* ---------- profile photo ---------- */
const avatar = (name, photo, cls) => '<span class="av' + (cls ? ' ' + cls : '') + '">' + (photo ? '<img src="' + esc(photo) + '" alt="' + esc(name || '') + '">' : esc(initials(name))) + '</span>';
/* click a profile photo (not the top-bar button) -> bigger view */
document.addEventListener('click', e => {
  const im = e.target.closest && e.target.closest('.av img');
  if (!im || im.closest('button')) return;
  modal('<div style="text-align:center"><img src="' + esc(im.getAttribute('src')) + '" alt="" style="width:100%;max-width:320px;aspect-ratio:1;object-fit:cover;border-radius:16px"><h3 style="margin:12px 0 4px">' + esc(im.alt) + '</h3>' +
    '<div class="row" style="justify-content:center;margin:10px 0 0"><button class="btn alt" onclick="closeModal()">Close</button></div></div>');
});
/* picture file -> small square JPEG (data URL, about 5-10 KB) */
function photoFromFile(file, size = 160) {
  return new Promise((ok, no) => {
    if (!file || !/^image\//.test(file.type)) return no(new Error('Choose a picture (JPG or PNG)'));
    const img = new Image(), url = URL.createObjectURL(file);
    img.onload = () => {
      const c = document.createElement('canvas'); c.width = c.height = size;
      const m = Math.min(img.width, img.height), x = (img.width - m) / 2, y = (img.height - m) / 2;
      c.getContext('2d').drawImage(img, x, y, m, m, 0, 0, size, size);
      URL.revokeObjectURL(url); ok(c.toDataURL('image/jpeg', 0.8));
    };
    img.onerror = () => no(new Error('This picture cannot be read. Try another one.'));
    img.src = url;
  });
}

/* ---------- e-mail (Brevo) ----------
   The browser never holds the Brevo key. It calls the Netlify Function  /.netlify/functions/send-email,
   which reads BREVO_API_KEY from Netlify > Environment variables and checks that the caller is the admin.
   (On your own computer use  netlify dev  so that the function runs too.)   */
const MAIL_API = BASE + '.netlify/functions/send-email';
const MAIL_API2 = BASE + 'api/send-email';                         // same function, short address (see _redirects)
const emailReady = () => true;
/* what to do when the function cannot be found (404 / 405 / a web page instead of an answer) */
const MAIL_MISSING = () => LOCAL
  ? 'E-mail does not work on a plain local server (Live Server, file://). Run  npx netlify-cli dev  in the project folder and open http://localhost:8888 (put the keys in a .env file). EASIER: run sql/10_upgrade_v48.sql in Supabase and save the Brevo key on the Email page (E-mail settings): then e-mail works here too.'
  : 'The e-mail function is not deployed on this site (not found). Deploy the WHOLE folder from GitHub (or "netlify deploy --prod"), not by drag-and-drop, check that Netlify > Deploys shows a green "Published" deploy and Netlify > Functions lists "send-email", then press Refresh. Adding the environment variables alone is not enough: after adding them, trigger a new deploy. EASIER: run sql/10_upgrade_v48.sql in Supabase, then save the Brevo key on the Email page (E-mail settings): e-mail then works on any address without the Netlify function.';
async function mailCall(url, action, data) {
  const res = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ action, token: tok(), ...data }) });
  const j = await res.json().catch(() => null);
  return { res, j };
}
/* ---- v48: e-mail through the DATABASE (Supabase pg_net -> Brevo). Works on every address, no Netlify function needed.
        Used automatically as soon as the Brevo key is saved on the Email page; otherwise the Netlify function (above) is used. ---- */
let _mailMode = null;                                              // 'db' | 'fn'
async function mailMode() {
  if (_mailMode) return _mailMode;
  try { const c = await T('mail_settings_get'); _mailMode = c && c.configured ? 'db' : 'fn'; } catch (e) { _mailMode = 'fn'; }   // (not run sql/10 yet -> function route)
  return _mailMode;
}
const mailModeReset = () => { _mailMode = null; };
const sleepMs = ms => new Promise(r => setTimeout(r, ms));
function brevoHint(status, msg) {
  const m = String(msg || '').toLowerCase();
  if (status === 401) return ' → The Brevo API key is wrong, or Brevo > Security > Authorised IPs is ON (switch it OFF).';
  if (m.includes('sender')) return ' → The sender e-mail is not verified in Brevo (Senders, Domains & Dedicated IPs > Senders). Verify it, and type exactly that address in Email > E-mail settings.';
  if (status === 403 || m.includes('not yet activated') || m.includes('not activated')) return ' → Your Brevo SMTP account is not activated yet. Ask Brevo support to activate it.';
  if (status === 402 || m.includes('credit') || m.includes('quota') || m.includes('limit')) return ' → The Brevo sending limit is used up (free plan: about 300 e-mails per day).';
  return '';
}
async function mailDbResult(rid, tries = 30) {                      // wait until Brevo has answered
  for (let i = 0; i < tries; i++) {
    const r = await T('mail_result', { rid });
    if (r && !r.pending) return r;
    await sleepMs(i < 4 ? 500 : 1000);
  }
  throw new Error('Brevo did not answer in time. Check Email > Check e-mail setup.');
}
async function mailApiDb(action, data) {
  if (action == 'status') return { events: [] };
  if (action != 'send') throw new Error('Unknown action');
  const rid = await T('mail_send', { subject: data.subject, html: data.htmlContent, txt: data.textContent || '', recipients: data.bcc || [], visible: data.to || [] });
  const r = await mailDbResult(rid), b = r.body || {};
  if (r.error && !r.status) throw new Error('Could not reach Brevo: ' + r.error);
  if (r.status < 200 || r.status >= 300) throw new Error((b.message || 'Brevo error ' + r.status) + brevoHint(r.status, b.message));
  return { messageIds: b.messageIds || (b.messageId ? [b.messageId] : []) };
}
async function mailApi(action, data = {}) {
  if (await mailMode() == 'db') return mailApiDb(action, data);
  let r;
  try {
    r = await mailCall(MAIL_API, action, data);
    if (!r.j && (r.res.status == 404 || r.res.status == 405)) r = await mailCall(MAIL_API2, action, data);       // try the short address once
  } catch (e) { throw new Error('The browser could not reach the e-mail service (' + (e.message || 'network') + '). This usually means the page is opened from a folder or a plain local server where the e-mail function does not exist. FIX: run sql/10_upgrade_v48.sql in Supabase and save the Brevo key on the Email page (E-mail settings). E-mail then works here.'); }
  const { res, j } = r;
  if (!res.ok) {
    if (!j && (res.status == 404 || res.status == 405)) { const er = new Error(MAIL_MISSING()); er.missing = true; throw er; }
    if (!j && res.status >= 500) throw new Error('The e-mail function crashed (error ' + res.status + '). Open Netlify > Logs > Functions > send-email to see why.');
    throw new Error((j && j.message) || 'E-mail error ' + res.status);
  }
  return j || {};
}

/* safe HTML for notices (bold, italic, lists, alignment ...): everything else is removed */
const OK_TAGS = ['B','STRONG','I','EM','U','S','P','DIV','BR','UL','OL','LI','H3','H4','SPAN','BLOCKQUOTE'];
function cleanHtml(h) {
  const t = document.createElement('template'); t.innerHTML = String(h || '');
  const walk = n => [...n.childNodes].forEach(c => {
    if (c.nodeType == 3) return;
    if (c.nodeType != 1 || !OK_TAGS.includes(c.tagName)) { if (c.nodeType == 1 && !['SCRIPT','STYLE','IFRAME','OBJECT'].includes(c.tagName)) { walk(c); c.replaceWith(...c.childNodes); } else c.remove(); return; }
    const al = (c.style && c.style.textAlign) || c.getAttribute('align') || '';
    [...c.attributes].forEach(a => c.removeAttribute(a.name));
    if (/^(left|center|right|justify)$/.test(al)) c.style.textAlign = al;
    walk(c);
  });
  walk(t.content); return t.innerHTML;
}
const isHtml = s => /<\/?(b|strong|i|em|u|s|p|div|br|ul|ol|li|h3|h4|span|blockquote)[\s>\/]/i.test(s || '');
/* message text (old plain notices or new rich ones) -> safe html for the page */
const richHtml = s => isHtml(s) ? cleanHtml(s) : esc(s || '').replace(/\n/g, '<br>');
const htmlText = s => { const d = document.createElement('div'); d.innerHTML = cleanHtml(s); d.querySelectorAll('br').forEach(b => b.replaceWith('\n')); d.querySelectorAll('p,div,li,h3,h4').forEach(e => e.append('\n')); return d.textContent.replace(/\n{3,}/g, '\n\n').trim(); };

/* the e-mail design (same look as the old template): `body` is safe html */
function mailHtml(heading, subject, body, date) {
  return '<!DOCTYPE html><html><body style="margin:0;padding:0;background:#eef2f9;font-family:Arial,Helvetica,sans-serif;color:#1e293b">' +
  '<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#eef2f9"><tr><td align="center" style="padding:30px 12px">' +
  '<table role="presentation" width="600" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:600px;background:#fff;border-radius:14px;overflow:hidden">' +
  '<tr><td style="background:#1d1b3a;padding:28px;text-align:center;border-bottom:5px solid #ffc531"><div style="font-size:26px;font-weight:bold;color:#fff">' + esc(ORG_NAME) + '</div><p style="margin:8px 0 0;color:#d9d6f5;font-size:14px">Student Update</p></td></tr>' +
  '<tr><td style="padding:26px 28px 6px"><table role="presentation" width="100%" style="background:#f3f1ff;border-radius:8px;border-left:4px solid #ffc531"><tr><td style="padding:16px">' +
  '<p style="margin:0 0 5px;font-size:12px;font-weight:bold;letter-spacing:1px;color:#3b2fd9;text-transform:uppercase">' + esc(heading) + '</p><h2 style="margin:0;font-size:20px;line-height:1.4;color:#1d1b3a">' + esc(subject) + '</h2></td></tr></table></td></tr>' +
  '<tr><td style="padding:18px 28px 6px"><p style="margin:0 0 14px;font-size:15px;color:#334155">Dear Students,</p>' +
  '<table role="presentation" width="100%" style="border:1px solid #e2e8f0;border-radius:8px"><tr><td style="padding:18px;font-size:14px;line-height:1.8;color:#334155;word-break:break-word">' + body + '</td></tr></table>' +
  '<p style="margin:14px 0 0;font-size:13px;color:#64748b"><strong style="color:#334155">Date:</strong> ' + esc(date) + '</p></td></tr>' +
  '<tr><td style="padding:20px 28px 24px"><p style="margin:0;font-size:14px;color:#475569">Best Regards,</p><p style="margin:6px 0 3px;font-size:16px;font-weight:bold;color:#1d1b3a">' + esc(ORG_NAME) + '</p>' +
  '<p style="margin:0;font-size:13px;font-weight:bold;color:#64748b">Developed by Gaddam Venu</p></td></tr>' +
  '<tr><td style="background:#f8fafc;border-top:1px solid #e2e8f0;padding:18px 28px;text-align:center"><p style="margin:0 0 6px;font-size:12px;color:#64748b">Questions? Reply to this email: ' + esc(ADMIN_MAIL) + '</p>' +
  '<p style="margin:0;font-size:11px;color:#94a3b8">&copy; ' + esc(ORG_NAME) + ' &middot; You receive this e-mail because something new was posted in your subject.</p></td></tr>' +
  '</table></td></tr></table></body></html>';
}

/* --------------------------------------------------------------------------
   mail(recipients, x)   recipients [{name,email,regno}]   x = { subject, message (plain text), html (optional safe html), heading, kind }
   ONE Brevo request sends the same message to up to BREVO_BATCH students at a time (Brevo allows 99 recipients per request; same method as the Nagarjuna app). The students are in BCC (nobody sees the others); the visible "To" is the admin.
   ONE line per message is saved in the history (x.toLabel = who it went to), not one line per student.
   Information only - no links.  Every attempt is saved in Admin > Email > History.   Returns { sent, failed:[addresses] }
   -------------------------------------------------------------------------- */
const BREVO_BATCH = 95;
async function mail(recipients, x = {}) {
  const today = new Date().toLocaleDateString('en-IN', { day: '2-digit', month: 'long', year: 'numeric' });
  const subj = x.subject || ('New update from ' + ORG_NAME);
  const seen = new Set(), list = recipients.filter(r => /^\S+@\S+\.\S+$/.test(r.email || '') && !seen.has(r.email.toLowerCase()) && seen.add(r.email.toLowerCase()));
  const body = x.html ? cleanHtml(x.html) : esc(x.message || '').replace(/\n/g, '<br>');
  let sent = 0, firstErr = ''; const failed = [], log = [];

  for (let i = 0; i < list.length; i += BREVO_BATCH) {
    const grp = list.slice(i, i + BREVO_BATCH);
    /* SAME METHOD AS THE WORKING NAGARJUNA APP: one Brevo request, the admin is the visible "To", the students are in BCC (nobody sees the others) */
    const isAdminOnly = grp.length == 1 && grp[0].email.toLowerCase() == ADMIN_MAIL.toLowerCase();
    let err = null;
    try {
      await mailApi('send', { subject: subj, htmlContent: mailHtml(x.heading || 'New Update', subj, body, today), textContent: (x.message || htmlText(x.html || '')) + '\n\n' + ORG_NAME,
        to: [{ email: ADMIN_MAIL, name: ORG_NAME }], bcc: isAdminOnly ? [] : grp.map(r => ({ email: r.email, name: r.name || '' })) });
    } catch (e) { err = e.message || String(e); }
    grp.forEach(r => err ? failed.push(r.email) : sent++);
    if (err && !firstErr) firstErr = err;
    if (i + BREVO_BATCH < list.length) await new Promise(s => setTimeout(s, 500));
  }
  if (list.length) log.push({ kind: x.kind || 'content', to_email: x.toLabel || (list.length + ' student(s)'), name: null, subject: subj, status: sent ? 'sent' : 'failed',
    error: failed.length ? failed.length + ' of ' + list.length + ' e-mail(s) failed: ' + firstErr : null, message: (x.message || htmlText(x.html || '')) || null });
  try { if (log.length) await T('email_log_add', { rw: log }); } catch (e) {}
  if (!sent && failed.length) throw new Error('Email failed: ' + firstErr);
  return { sent, failed };
}

/* e-mail every student of subject `sid` at one time (admin only). `info` = { subject, message, html, heading } */
async function mailPosted(sid, subject, message, heading, html, only, label) {      // only = optional list of Reg Nos: e-mail just those students (label = e.g. 'Batch 1')
  try {
    let rec = await T('email_recipients', { sids: [sid] });
    if (only) { const set = new Set(only.map(v => String(v).toUpperCase())); rec = rec.filter(r => set.has(String(r.regno).toUpperCase())); }
    if (!rec.length) return ' · no student e-mail addresses to notify';
    toast('Emailing ' + rec.length + ' student(s)… please wait');
    const m = await mail(rec, { subject, message, html, heading, kind: 'content', toLabel: only ? (label || 'Selected students') + ' (' + rec.length + ')' : 'All students of this subject (' + rec.length + ')' });
    return ' · emailed ' + m.sent + ' student(s)' + (m.failed.length ? ', ' + m.failed.length + ' failed' : '');
  } catch (e) { return ' · email failed: ' + e.message; }
}

/* refresh: forget the cached copy of the site (service worker + cache) and reload, so the newest version is loaded */
const REFRESH_ICO = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>';
async function hardRefresh(btn) {
  if (btn) btn.classList.add('spin');
  try {
    if (navigator.serviceWorker) for (const r of await navigator.serviceWorker.getRegistrations()) await r.unregister();
    if (window.caches) for (const k of await caches.keys()) await caches.delete(k);
  } catch (e) {}
  location.reload();
}

/* installable app (PWA) */
if ('serviceWorker' in navigator) navigator.serviceWorker.register(BASE + 'sw.js').catch(() => {});
