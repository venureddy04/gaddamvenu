/* Runs on Netlify before publishing (see netlify.toml).
   If an environment variable exists, it replaces the same constant in config.js.
   Variables that are not set are skipped, so config.js keeps working locally.
   The Brevo key is NOT handled here: it is used only by netlify/functions/send-email.js */
const fs = require('fs'), path = require('path');
const file = path.join(__dirname, '..', 'config.js');
let s = fs.readFileSync(file, 'utf8');
for (const k of ['SB_URL', 'SB_KEY', 'ADMIN_MAIL', 'ORG_NAME', 'DEVELOPERS', 'APK_URL']) {
  const v = (process.env[k] || '').trim();
  if (!v) { console.log('config.js: ' + k + ' not in environment, keeping the value in the file'); continue; }
  const re = new RegExp('^(const ' + k + ' = ).*;[ \\t]*$', 'm');
  if (!re.test(s)) { console.warn('config.js: "const ' + k + ' = ...;" not found, skipped'); continue; }
  s = s.replace(re, (_, p) => p + JSON.stringify(v) + ';');
  console.log('config.js: ' + k + ' set from environment');
}
fs.writeFileSync(file, s);
