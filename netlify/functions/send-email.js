/* ==========================================================================
   Netlify Function  /.netlify/functions/send-email
   The Brevo API key lives ONLY here, in Netlify > Environment variables.
   The browser never sees it.

   Environment variables used (Netlify > Project configuration > Environment variables):
     BREVO_API_KEY        Brevo API key (xkeysib-...)                 [mark as secret]
     BREVO_SENDER_EMAIL   verified sender in Brevo > Senders & IP
     BREVO_SENDER_NAME    name shown as the sender
     BREVO_REPLY_TO       (optional) reply-to address, default = sender e-mail
     SB_URL, SB_KEY       Supabase URL + anon key (used to check that the caller is the admin).
                          If they are not set here, config.js (shipped with the function) is used instead.

   Only a logged-in ADMIN of the portal may use this function.
   ========================================================================== */
const BREVO = 'https://api.brevo.com/v3';
const MAX_RECIPIENTS = 99;                       // Brevo limit per request
const MAIL_RE = /^\S+@\S+\.\S+$/;

/* SB_URL / SB_KEY: Netlify environment first, otherwise the values written in config.js (which is shipped with this function, see netlify.toml) */
let _cfg = null;
function fromConfig(k) {
  if (!_cfg) {
    _cfg = {};
    const fs = require('fs'), path = require('path');
    for (const f of [path.join(process.cwd(), 'config.js'), path.join(__dirname, 'config.js'), path.join(__dirname, '..', '..', 'config.js'), path.join(process.env.LAMBDA_TASK_ROOT || '', 'config.js')]) {
      try {
        const t = fs.readFileSync(f, 'utf8');
        for (const n of ['SB_URL', 'SB_KEY']) { const m = t.match(new RegExp("^const " + n + " = ['\"]([^'\"]+)['\"]", 'm')); if (m) _cfg[n] = m[1]; }
        if (_cfg.SB_URL) break;
      } catch (e) {}
    }
  }
  return _cfg[k] || '';
}
const sbUrl = () => (process.env.SB_URL || '').trim() || fromConfig('SB_URL');
const sbKey = () => (process.env.SB_KEY || '').trim() || fromConfig('SB_KEY');

/* plain-words help for the most common Brevo errors */
function brevoHint(status, msg) {
  const m = String(msg || '').toLowerCase();
  if (status === 401) return ' → The Brevo API key is wrong, or Brevo > Security > Authorised IPs is ON (Netlify has no fixed IP: switch it OFF).';
  if (m.includes('sender')) return ' → The sender e-mail is not verified in Brevo (Senders, Domains & Dedicated IPs > Senders). Verify it and set BREVO_SENDER_EMAIL to exactly that address.';
  if (status === 403 || m.includes('not yet activated') || m.includes('not activated')) return ' → Your Brevo SMTP account is not activated yet. Ask Brevo support to activate it (Brevo > SMTP & API).';
  if (status === 402 || m.includes('credit') || m.includes('quota') || m.includes('limit')) return ' → The Brevo sending limit is used up (free plan: about 300 e-mails per day). Try again tomorrow or upgrade.';
  return '';
}

const reply = (statusCode, obj) => ({
  statusCode,
  headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  body: JSON.stringify(obj),
});

/* ask the database who owns this login token (same check the portal uses) */
async function isAdmin(token) {
  const base = sbUrl().replace(/\/$/, ''), key = sbKey();
  if (!base || !key || !token) return false;
  try {
    const r = await fetch(base + '/rest/v1/rpc/profile_get', {
      method: 'POST',
      headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ t: token }),
    });
    if (!r.ok) return false;
    const p = await r.json().catch(() => null);
    return !!p && p.role === 'admin';
  } catch (e) { return false; }
}

exports.handler = async (event) => {
  /* open  /.netlify/functions/send-email  in the browser: if you see {"ok":true...} the function is deployed */
  if (event.httpMethod === 'GET') return reply(200, { ok: true, function: 'send-email', ready: !!((process.env.BREVO_API_KEY || '').trim() && (process.env.BREVO_SENDER_EMAIL || '').trim()) });
  if (event.httpMethod !== 'POST') return reply(405, { message: 'Use POST' });

  const apiKey = (process.env.BREVO_API_KEY || '').trim();
  const senderEmail = (process.env.BREVO_SENDER_EMAIL || '').trim();
  const senderName = (process.env.BREVO_SENDER_NAME || '').trim() || 'Portal';
  let b;
  try { b = JSON.parse(event.body || '{}'); } catch (e) { return reply(400, { message: 'Bad request' }); }
  if (!sbUrl() || !sbKey()) return reply(500, { message: 'SB_URL / SB_KEY are not set in Netlify environment variables (and not found in config.js)' });
  if (!(await isAdmin(b.token))) return reply(401, { message: 'Not allowed: log in as admin' });
  /* the "check" action reports what is missing, so it is allowed to run without the Brevo variables */
  if (b.action !== 'check') {
    if (!apiKey) return reply(500, { message: 'BREVO_API_KEY is not set in Netlify environment variables (then deploy again)' });
    if (!senderEmail) return reply(500, { message: 'BREVO_SENDER_EMAIL is not set in Netlify environment variables (then deploy again)' });
  }

  const headers = { accept: 'application/json', 'api-key': apiKey };

  /* ---- action: check  -> is everything ready?  (used by the "Check e-mail setup" button on the Email page) ---- */
  if (b.action === 'check') {
    const out = {
      function: true,
      env: { BREVO_API_KEY: !!apiKey, BREVO_SENDER_EMAIL: !!senderEmail, BREVO_SENDER_NAME: !!(process.env.BREVO_SENDER_NAME || '').trim(), SB_URL: !!sbUrl(), SB_KEY: !!sbKey() },
      sender: senderEmail, account: null, senderStatus: null,
    };
    if (!apiKey) return reply(200, out);
    try {
      const r = await fetch(BREVO + '/account', { headers }), j = await r.json().catch(() => ({}));
      out.account = r.ok ? { ok: true, email: j.email || '', credits: (j.plan || []).filter(x => x.credits != null).map(x => (x.type || 'plan') + ': ' + x.credits + (x.creditsType ? ' ' + x.creditsType : '')) }
                         : { ok: false, message: (j.message || 'Brevo error ' + r.status) + brevoHint(r.status, j.message) };
    } catch (e) { out.account = { ok: false, message: 'Could not reach Brevo: ' + (e.message || 'network error') }; }
    if (senderEmail) try {
      const r = await fetch(BREVO + '/senders', { headers }), j = await r.json().catch(() => ({}));
      if (r.ok) {
        const me = (j.senders || []).find(x => String(x.email).toLowerCase() === senderEmail.toLowerCase());
        out.senderStatus = me ? { ok: !!me.active, message: me.active ? 'verified and active' : 'found, but NOT active: open Brevo > Senders and verify it' } : { ok: false, message: 'this address is not in your Brevo senders list: add and verify it in Brevo > Senders, Domains & Dedicated IPs' };
      }
    } catch (e) {}
    return reply(200, out);
  }

  /* ---- action: status  -> which of these messages were blocked / bounced? ---- */
  if (b.action === 'status') {
    const want = new Set((Array.isArray(b.ids) ? b.ids : []).map(String));
    if (!want.size) return reply(200, { events: [] });
    const kinds = ['blocked', 'invalid', 'hardBounces', 'error'];
    const lists = await Promise.all(kinds.map(async ev => {
      try {
        const r = await fetch(BREVO + '/smtp/statistics/events?days=1&limit=100&sort=desc&event=' + ev, { headers });
        return r.ok ? ((await r.json()).events || []) : [];
      } catch (e) { return []; }
    }));
    const events = lists.flat().filter(e => want.has(String(e.messageId))).map(e => ({ event: e.event, reason: e.reason || '', messageId: e.messageId }));
    return reply(200, { events });
  }

  /* ---- action: send ----
     Same request as the working Nagarjuna app: visible "To" = the admin, the students are in BCC (b.bcc), ONE Brevo request.
     (Old way still accepted: no b.bcc -> every address in b.to gets its own copy through messageVersions.) */
  if (b.action === 'send') {
    const clean = (a, seen = new Set()) => (Array.isArray(a) ? a : []).filter(r => r && MAIL_RE.test(r.email || '') && !seen.has(r.email.toLowerCase()) && seen.add(r.email.toLowerCase())).map(r => ({ email: r.email, name: r.name || undefined }));
    const subject = String(b.subject || '').slice(0, 300);
    if (!subject || !b.htmlContent) return reply(400, { message: 'Subject and message are required' });
    const replyTo = (process.env.BREVO_REPLY_TO || senderEmail).trim();
    const payload = {
      sender: { name: senderName, email: senderEmail },
      replyTo: { email: replyTo, name: senderName },
      subject,
      htmlContent: String(b.htmlContent),
      textContent: String(b.textContent || ''),
      tags: ['portal'],
    };
    if (Array.isArray(b.bcc)) {
      const bcc = clean(b.bcc), to = clean(b.to);
      if (bcc.length > MAX_RECIPIENTS) return reply(400, { message: 'Too many recipients in one request (max ' + MAX_RECIPIENTS + ')' });
      payload.to = to.length ? to : [{ email: replyTo, name: senderName }];
      if (bcc.length) payload.bcc = bcc;
    } else {
      const to = clean(b.to);
      if (!to.length) return reply(400, { message: 'No valid recipient' });
      if (to.length > MAX_RECIPIENTS) return reply(400, { message: 'Too many recipients in one request (max ' + MAX_RECIPIENTS + ')' });
      payload.messageVersions = to.map(r => ({ to: [r] }));
    }
    try {
      const r = await fetch(BREVO + '/smtp/email', { method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, body: JSON.stringify(payload) });
      const j = await r.json().catch(() => ({}));
      if (!r.ok) return reply(r.status, { message: (j.message || 'Brevo error ' + r.status) + brevoHint(r.status, j.message) });
      return reply(200, { messageIds: j.messageIds || (j.messageId ? [j.messageId] : []) });
    } catch (e) { return reply(502, { message: 'Could not reach Brevo: ' + (e.message || 'network error') }); }
  }

  return reply(400, { message: 'Unknown action' });
};
