/* ==========================================================================
   shell.js – sidebar + mobile top bar for every logged-in page
   buildShell('dash' | 'create' | 'email' | 'sub:<subjectId>')
   Sidebar:  Dashboard · Create Subject · Email · Logout   (admin)
             Dashboard · Logout                            (CR / student)
             + one button for every subject (loaded from the database)
   ========================================================================== */
const ICONS = {
  clip:'<path d="M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2"/><rect x="9" y="3" width="6" height="4" rx="1"/><path d="M9 13l2 2 4-4"/>',
  home:'<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>',
  plus:'<line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>',
  mail:'<path d="M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z"/><polyline points="22,6 12,13 2,6"/>',
  logout:'<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>',
  menu:'<line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="18" x2="21" y2="18"/>',
  book:'<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>',
  users:'<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  bell:'<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/>',
  flask:'<path d="M9 3h6"/><path d="M10 3v6L4 19a2 2 0 0 0 2 3h12a2 2 0 0 0 2-3l-6-10V3"/>',
  layers:'<polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/><polyline points="2 12 12 17 22 12"/>',
  clock:'<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
  shield:'<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>'
};
const ico = n => '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + ICONS[n] + '</svg>';

function buildShell(active) {
  const name = localStorage.ng_name || 'User', sub = localStorage.ng_sub || '';
  const items = [{ k: 'dash', l: 'Home', i: 'home', h: 'dashboard' }];
  items.push({ k: 'subjects', l: 'Subjects', i: 'layers', pick: 1 });
  items.push({ k: 'timetable', l: 'Timetable', i: 'clock', h: 'timetable' });
  if (ROLE == 'admin') items.push({ k: 'create', l: 'Create', i: 'plus', h: 'subjects' }, { k: 'students', l: 'Students', i: 'users', h: 'students' }, { k: 'email', l: 'Email', i: 'mail', h: 'email' });
  const on = k => (k == active || (k == 'subjects' && /^sub:/.test(active))) ? ' on' : '';

  /* bottom dock = the main navigation */
  $('#side').innerHTML = '<nav class="dock" aria-label="Main">' + items.map(x => x.pick
    ? '<button type="button" class="dk' + on(x.k) + '" onclick="pickSubject()">' + ico(x.i) + '<span>' + esc(x.l) + '</span></button>'
    : '<a class="dk' + on(x.k) + '" href="' + page(x.h) + '">' + ico(x.i) + '<span>' + esc(x.l) + '</span></a>').join('') + '</nav>';

  /* slim top bar */
  $('#top').innerHTML =
    '<a class="brand" href="' + page('dashboard') + '"><img src="' + BASE + 'assets/logo.png" alt=""><b>Gaddam Venu</b></a>' +
    '<span class="top-t" id="topt"></span>' +
    '<button type="button" class="tb" aria-label="Refresh" title="Refresh" onclick="hardRefresh(this)">' + REFRESH_ICO + '</button>' +
    '<button type="button" class="avb" id="topav" onclick="openProfile()" aria-label="My profile (' + esc(name) + ')">' + avatar(name, localStorage.ng_photo) + '</button>' +
    '<button type="button" class="tb out" aria-label="Logout" title="Logout" onclick="logout()">' + ico('logout') + '</button>';

  loadSide(active);
  T('profile_get').then(p => { if (!p) return; localStorage.ng_name = p.name; if (p.photo) localStorage.ng_photo = p.photo; else delete localStorage.ng_photo; refreshMe(); }).catch(() => {});

  /* log out after 30 minutes without activity */
  let idle; const reset = () => { clearTimeout(idle); idle = setTimeout(() => { toast('Logged out after 30 minutes of inactivity', 1); setTimeout(logout, 1200); }, 30 * 60 * 1000); };
  ['click', 'keydown', 'touchstart', 'scroll', 'mousemove'].forEach(ev => addEventListener(ev, reset, { passive: true }));
  reset();
}

function refreshMe() {
  const n = localStorage.ng_name || 'User';
  if ($('#topav')) $('#topav').innerHTML = avatar(n, localStorage.ng_photo);
  const b = document.querySelector('.me-t b'); if (b) b.textContent = n;
}

/* my profile: photo for everybody, own password for students (CR and admin passwords: only the admin / SQL file) */
function openProfile() {
  const n = localStorage.ng_name || 'User';
  modal('<h3>My profile</h3><div class="prof">' + avatar(n, localStorage.ng_photo, 'lg') +
    '<div><b>' + esc(n) + '</b><br><span class="sm">' + esc(localStorage.ng_sub || '') + '</span>' +
    '<div class="row" style="margin:10px 0 0"><label class="btn alt" style="cursor:pointer">Change photo<input type="file" id="pf" accept="image/*" hidden></label>' +
    (localStorage.ng_photo ? '<button class="btn alt" id="pr">Remove photo</button>' : '') + '</div></div></div>' +
    (ROLE == 'student' ? '<h3 style="margin-top:20px;font-size:17px">Change password</h3>' +
      '<label class="fld">Current password<input id="po" type="password" autocomplete="current-password"></label>' +
      '<label class="fld">New password<input id="pn" type="password" autocomplete="new-password"></label>' +
      '<label class="fld">New password again<input id="pn2" type="password" autocomplete="new-password"></label>' +
      '<div class="row" style="margin:0"><button class="btn y" id="ps">Change password</button></div>' +
      '<p class="sm">You do not have to change it. If you forget it, use "Forgot password" on the login page: it goes back to your mobile number.</p>' :
      ROLE == 'cr' ? '<p class="sm" style="margin-top:14px">Your password is set by the admin. Only the admin can reset it.</p>' : '') +
    '<div class="row" style="margin:14px 0 0"><button class="btn alt" onclick="closeModal()">Close</button></div>');
  const save = async p => { await T('profile_photo_set', { p }); if (p) localStorage.ng_photo = p; else delete localStorage.ng_photo; refreshMe(); openProfile(); toast(p ? 'Photo saved' : 'Photo removed'); };
  $('#pf').onchange = e => run(async () => save(await photoFromFile(e.target.files[0])));
  if ($('#pr')) $('#pr').onclick = e => run(() => save(null), e.target);
  if ($('#ps')) $('#ps').onclick = e => run(async () => {
    const v = { o: $('#po').value, n: $('#pn').value, n2: $('#pn2').value };       // read before the popup closes
    if (v.n != v.n2) throw new Error('The two new passwords are not the same');
    await T('password_change', { old: v.o, nw: v.n });
    closeModal(); toast('Password changed');
  }, e.target);
}

/* the subject list (window.SUBS). Pages call loadSide() again after creating / deleting a subject. */
const KINDS = { theory: 'Theory only', lab: 'Theory + Lab', mini: 'Mini Project', major: 'Major Project' };
const isProj = k => k == 'mini' || k == 'major';
function loadSide(active) {
  window.SUBS = T('subjects_list');
  return SUBS.then(list => {
    const s = list.find(x => 'sub:' + x.code == active); if (s && $('#topt')) $('#topt').textContent = s.code;
    return list;
  }).catch(e => toast(e.message, 1));
}
/* "Subjects" button of the dock: every subject, grouped by type */
function pickSubject() {
  const groups = [['theory', 'Theory'], ['lab', 'Theory + Lab'], ['mini', 'Mini Projects'], ['major', 'Major Projects']];
  modal('<h3>Subjects</h3><div id="pk"><p class="sm">Loading…</p></div><div class="row" style="margin:14px 0 0"><button class="btn alt" onclick="closeModal()">Close</button></div>');
  (window.SUBS || T('subjects_list')).then(list => {
    $('#pk').innerHTML = groups.map(g => { const l = list.filter(x => x.kind == g[0]); return l.length ? '<div class="pkg"><div class="pkh">' + g[1] + '</div>' +
      l.map(x => '<a class="pki" href="' + subUrl(x.code) + '"><b>' + esc(x.code) + '</b><span>' + esc(x.full_name || '') + '</span></a>').join('') + '</div>' : ''; }).join('') ||
      '<p class="sm">' + (ROLE == 'admin' ? 'No subjects yet. Use Create.' : 'No subjects assigned yet.') + '</p>';
  }).catch(e => { $('#pk').innerHTML = '<p class="sm">' + esc(e.message) + '</p>'; });
}

/* simple modal */
function modal(html) { const m = $('#modal'); m.innerHTML = '<div class="mb">' + html + '</div>'; m.hidden = false; m.onclick = e => { if (e.target == m) closeModal(); }; }
function closeModal() { $('#modal').hidden = true; $('#modal').innerHTML = ''; }

/* shared page frame: every page calls needLogin(roles) first */
function needLogin(roles) {
  if (!tok()) { location.href = HOME; return false; }
  if (roles && !roles.includes(ROLE)) { location.href = page('dashboard'); return false; }
  return true;
}
