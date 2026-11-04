/* ==========================================================================
   marks.js – Theory Marks and Lab Marks tables with formula columns
   Used by subject.html.   Needs: sid, C, ADM, STU, T, run, toast, esc, modal, closeModal, exportTable, lib, XLSX_URL
   The admin creates the columns (marks columns or formula columns), enters / edits / deletes marks for every student
   and downloads Excel / PDF / Word.  A student sees ONLY his / her own row (the database function guarantees it).
   Formulas are calculated here WITHOUT eval (the site's security policy does not allow eval).
   v28: clear grid table.  v32: no automatic colors.  v33: Lab Marks colors = row colors (by hand) + condition based column colors (rules like "below 11 = red").
   ========================================================================== */
const MK = {};                                                    // MK.theory / MK.lab = { kind, cols, rows }
const FIXED_THEORY = 'AAT 1';                                   // inbuilt, mandatory Theory Marks column (cannot be renamed or deleted)
const isFixed = (kind, c) => kind == 'theory' && c.type != 'formula' && c.name.trim().toLowerCase() == FIXED_THEORY.toLowerCase();
const isAB = x => typeof x == 'string' && x.trim().toUpperCase() == 'AB';                 // AB = absent: shown as AB, ignored by formulas like a blank cell
const rawMark = x => isAB(x) ? 'AB' : fmtN(num(x));
const colMax = c => (c && c.type != 'formula' && num(c.max) != null && num(c.max) > 0) ? num(c.max) : null;   // 'out of' marks fixed by the admin for a column
const colLetter = n => { let s = ''; for (n++; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + (n - 1) % 26) + s; return s; };   // 0 -> A
const letterIdx = L => L.toUpperCase().split('').reduce((a, c) => a * 26 + c.charCodeAt(0) - 64, 0) - 1;                                           // A -> 0
/* A column inserted in the middle moves the letters of the columns after it one place right, so the column letters inside the OTHER
   formulas (C5, C5:H5) are moved too, like Excel.  [Names] and "text" are left alone.  at = letter index of the new column (C = 2). */
const shiftRefs = (f, at) => String(f || '').split(/("[^"]*"|\[[^\]]*\])/).map((seg, k) => k % 2 ? seg :
  seg.replace(/(^|[^A-Za-z0-9_$])(\$?)([A-Za-z]{1,3})(\$?)(\d+)(?![A-Za-z0-9_])/g, (m, pre, d1, L, d2, n) => letterIdx(L) >= at ? pre + d1 + colLetter(letterIdx(L) + 1) + d2 + n : m)).join('');
const cid = () => 'c' + Math.random().toString(36).slice(2, 8);
const num = x => (x === '' || x == null || isNaN(x)) ? null : Number(x);
const fmtN = x => x === undefined ? 'Err' : x == null ? '' : typeof x == 'boolean' ? (x ? 'TRUE' : 'FALSE') : typeof x == 'string' ? x : isNaN(x) ? 'Err' : String(Math.round(x * 100) / 100);

/* ---------- table colors (Lab Marks only) ----------
   ROW colors (v32): set by hand by the admin, one color for each row (the round swatch at the start of the row, or the 🎨 Row colors window).
   COLUMN colors (v33): CONDITION BASED.  For each column the admin writes rules, for example  "less than 11 = red", "less than 16 = blue",
   "16 or more = green".  Every cell is checked from the first rule to the last; the FIRST rule that fits gives the cell its color.  Nothing is colored until the admin writes a rule.
   Saved per Lab Marks sheet inside the existing  row_colors  field (NO database change):
     { on:false, col, rows:[...] (kept only because the database checks them),  rowc:{ <student id>: '#rrggbb' },  colr:{ <column id>: [ {op, a, b, color} ] } }
   op: lt (<)  le (<=)  gt (>)  ge (>=)  eq (=)  bt (between a and b, both included)  ab (the cell is AB)  any (every cell of the column).
   ROW rules (v33.1): the same kind of rules, but they color the WHOLE ROW from the value of ONE deciding column (for example Total):  rowr:{ col:<column id>, rules:[...] }.
   A color set by hand on a specific row wins over the row rules.  In a crossing cell the COLUMN rule color shows (the row color shows where no column rule fits).  The old v32 field  colc  (one fixed color for a whole column) is no longer used. */
const HEX = /^#[0-9a-f]{6}$/i;
const mixW = (hex, k) => '#' + [1, 3, 5].map(i => Math.round(255 - (255 - parseInt(hex.substr(i, 2), 16)) * k).toString(16).padStart(2, '0')).join('');     // light tint of a color (k = strength 0..1)
const inkOn = hex => { const [r, g, b] = [1, 3, 5].map(i => parseInt(hex.substr(i, 2), 16)); return (r * 299 + g * 587 + b * 114) / 1000 > 150 ? '#111827' : '#ffffff'; };   // black or white text on that color
const cleanMap = o => { const r = {}; if (o && typeof o == 'object' && !Array.isArray(o)) Object.keys(o).forEach(k => { if (HEX.test(o[k] || '')) r[k] = o[k].toLowerCase(); }); return r; };
const OPS = { lt: 'is less than', le: 'is less than or equal to', gt: 'is greater than', ge: 'is greater than or equal to', eq: 'is equal to', bt: 'is between', ab: 'is AB (absent)', any: 'every cell of the column' };
const MAXRULES = 8, RULE_COLORS = ['#dc2626', '#2563eb', '#16a34a', '#f59e0b', '#7c3aed', '#0891b2', '#db2777', '#64748b'];
const needA = op => op != 'ab' && op != 'any';
const cleanRules = a => (Array.isArray(a) ? a : []).filter(r => r && OPS[r.op] && HEX.test(r.color || '') && (!needA(r.op) || (num(r.a) != null && (r.op != 'bt' || num(r.b) != null)))).slice(0, MAXRULES)
  .map(r => ({ op: r.op, ...(needA(r.op) ? { a: num(r.a) } : {}), ...(r.op == 'bt' ? { b: num(r.b) } : {}), color: r.color.toLowerCase() }));
const cleanColr = o => { const r = {}; if (o && typeof o == 'object' && !Array.isArray(o)) Object.keys(o).forEach(k => { const x = cleanRules(o[k]); if (x.length) r[k] = x; }); return r; };
const cleanRowr = o => { if (!o || typeof o != 'object' || typeof o.col != 'string') return null; const x = cleanRules(o.rules); return x.length ? { col: o.col, rules: x } : null; };
const tcGet = M => { const rr = cleanRowr((M.rc || {}).rowr); return { rowc: cleanMap((M.rc || {}).rowc), colr: cleanColr((M.rc || {}).colr), rowr: rr && M.cols.some(c => c.id == rr.col) ? rr : null }; };      // { rowc, colr, rowr } of a sheet (empty = no colors)
/* the color of a whole row: the one set by hand, else the first row rule that fits the value of the deciding column */
function rowHex(M, TC, r, v) {
  if (TC.rowc[r.student_id]) return TC.rowc[r.student_id];
  if (!TC.rowr) return null;
  const c = M.cols.find(x => x.id == TC.rowr.col); if (!c) return null;
  return cellColor(TC.rowr.rules, v[c.id], c.type != 'formula' && isAB((r.vals || {})[c.id]));
}                      // { rowc, colr } of a sheet (empty = no colors)
/* does a cell (value x, ab = the cell is AB) fit a rule?  The shown (rounded) value is compared, so what you see is what is checked. */
function ruleHit(r, x, ab) {
  if (r.op == 'any') return true;
  if (r.op == 'ab') return !!ab;
  if (ab || typeof x != 'number' || isNaN(x)) return false;
  x = Math.round(x * 100) / 100;
  return r.op == 'lt' ? x < r.a : r.op == 'le' ? x <= r.a : r.op == 'gt' ? x > r.a : r.op == 'ge' ? x >= r.a : r.op == 'eq' ? x === r.a : (x >= Math.min(r.a, r.b) && x <= Math.max(r.a, r.b));
}
const cellColor = (rules, x, ab) => { for (const r of rules || []) if (ruleHit(r, x, ab)) return r.color; return null; };      // the color of the first rule that fits, or null
const ruleText = r => r.op == 'bt' ? fmtN(r.a) + ' – ' + fmtN(r.b) : r.op == 'ab' ? 'AB' : r.op == 'any' ? 'All cells' : ({ lt: '< ', le: '≤ ', gt: '> ', ge: '≥ ', eq: '= ' })[r.op] + fmtN(r.a);
async function tcSave(kind, rowc, colr, rowr) {                                  // admin: save the colors (rows / columns that no longer exist are dropped)
  const M = MK[kind], ids = new Set(M.cols.map(c => c.id)), sids = new Set(M.rows.map(r => r.student_id));
  Object.keys(rowc).forEach(k => { if (!sids.has(k)) delete rowc[k]; }); Object.keys(colr).forEach(k => { if (!ids.has(k)) delete colr[k]; }); if (rowr && !ids.has(rowr.col)) rowr = null;
  const first = M.cols.find(c => /^[A-Za-z0-9]{1,20}$/.test(c.id)); if (!first) throw Error('Add a column first');
  const rc = { on: false, col: first.id, rows: [{ from: 0, color: '#dc2626' }], rowc, colr }; if (rowr) rc.rowr = rowr;
  try { await T('marks_rules_save', { sid, kd: kind, rc }); }
  catch (er) { throw /marks_rules_save|schema cache/i.test(er.message || '') ? Error('Run the SQL file 14_marks_row_colors.sql once in Supabase (see README), then try again.') : er; }
  M.rc = rc;
}

/* ---------- formula engine (no eval) ----------
   Works like Excel:  numbers, "text", [Column name], cell references C5 and ranges C5:H5, + - * / ^ %, comparisons = <> < > <= >=,
   functions OUTOF([Column]) = maximum marks fixed for a column, SUM AVERAGE(AVG) MAX MIN COUNT ROUND ROUNDUP ROUNDDOWN INT ABS MOD POWER SQRT CEILING FLOOR IF AND OR NOT TRUE FALSE.
   Column letters are the ones shown above the table:  A = Reg No, B = Name, C = first column, D = second ...
   The ROW number of a reference is ignored: C68:M68 simply means "columns C to M of this student's own row".
   Returns a number / text / TRUE-FALSE, null (blank), NaN (maths error such as divide by zero) or undefined (formula not understood). */
function runFormula(f, nameIdx, ref, ncols, maxOf) {
  const src = String(f || '').trim().replace(/^=/, ''),
    re = /\s*(?:(\d+\.?\d*|\.\d+)|"([^"]*)"|\[([^\]]+)\]|\$?([A-Za-z]{1,3})\$?(\d+)(?::\$?([A-Za-z]{1,3})\$?(\d+))?|([A-Za-z_][A-Za-z_0-9]*)|(<=|>=|<>|[-+*\/^(),<>=%]))/y;
  const tk = []; re.lastIndex = 0;
  while (re.lastIndex < src.length && !/^\s*$/.test(src.slice(re.lastIndex))) {
    const m = re.exec(src); if (!m) return undefined;
    tk.push(m[1] != null ? { n: +m[1] } : m[2] != null ? { s: m[2] } : m[3] != null ? { r: m[3].trim().toLowerCase() } : m[4] != null ? { c: [m[4], m[6] || null] } : m[8] != null ? { id: m[8].toUpperCase() } : { o: m[9] });
  }
  if (!tk.length) return undefined;
  let p = 0;
  const N = x => x == null ? 0 : typeof x == 'boolean' ? +x : typeof x == 'number' ? x : (String(x).trim() !== '' && !isNaN(x) ? Number(x) : NaN);
  const nums = a => a.flat().filter(x => typeof x == 'number' && !isNaN(x));
  const rnd = (x, d, mode) => { x = N(x); const k = 10 ** Math.trunc(N(d)), y = +(Math.abs(x) * k).toPrecision(12); return Math.sign(x) * (mode == 'up' ? Math.ceil(y) : mode == 'down' ? Math.floor(y) : Math.round(y)) / k; };
  const truth = x => typeof x == 'boolean' ? x : N(x) != 0;
  const FN = {
    SUM: a => nums(a).reduce((s, x) => s + x, 0), AVERAGE: a => { const v = nums(a); return v.length ? v.reduce((s, x) => s + x, 0) / v.length : null; }, AVG: a => FN.AVERAGE(a),
    MAX: a => { const v = nums(a); return v.length ? Math.max(...v) : 0; }, MIN: a => { const v = nums(a); return v.length ? Math.min(...v) : 0; }, COUNT: a => nums(a).length,
    ROUND: a => rnd(a[0], a[1] || 0, 'n'), ROUNDUP: a => rnd(a[0], a[1] || 0, 'up'), ROUNDDOWN: a => rnd(a[0], a[1] || 0, 'down'),
    INT: a => Math.floor(N(a[0])), ABS: a => Math.abs(N(a[0])), SQRT: a => N(a[0]) < 0 ? NaN : Math.sqrt(N(a[0])), POWER: a => N(a[0]) ** N(a[1]),
    MOD: a => N(a[1]) == 0 ? NaN : N(a[0]) - N(a[1]) * Math.floor(N(a[0]) / N(a[1])),
    CEILING: a => { const s = a[1] == null ? 1 : N(a[1]); return s == 0 ? 0 : Math.ceil(+(N(a[0]) / s).toPrecision(12)) * s; }, FLOOR: a => { const s = a[1] == null ? 1 : N(a[1]); return s == 0 ? NaN : Math.floor(+(N(a[0]) / s).toPrecision(12)) * s; },
    IF: a => truth(a[0]) ? (a.length > 1 ? a[1] : true) : (a.length > 2 ? a[2] : false), AND: a => a.flat().every(truth), OR: a => a.flat().some(truth), NOT: a => !truth(a[0])
  };
  const cmp = (op, a, b) => {
    let x = a, y = b;
    if (typeof x == 'string' && typeof y == 'string') { x = x.toLowerCase(); y = y.toLowerCase(); } else { x = N(x); y = N(y); }
    return op == '=' ? x === y : op == '<>' ? x !== y : op == '<' ? x < y : op == '>' ? x > y : op == '<=' ? x <= y : x >= y;
  };
  const val = (i, rng) => { const v = ref(i, rng); return v === undefined ? NaN : v; };
  const cell = (L, rng) => { const i = letterIdx(L); if (i < 2 || i - 2 >= ncols) { if (rng) return null; throw 0; } return val(i - 2, rng); };
  const eat = o => tk[p] && tk[p].o === o ? (p++, true) : false;
  const CMP = ['=', '<>', '<', '>', '<=', '>='];
  function comp() { let v = add(); for (;;) { const t = tk[p]; if (t && t.o && CMP.includes(t.o)) { p++; v = cmp(t.o, v, add()); } else return v; } }
  function add() { let v = mul(); for (;;) { if (eat('+')) v = N(v) + N(mul()); else if (eat('-')) v = N(v) - N(mul()); else return v; } }
  function mul() { let v = pow(); for (;;) { if (eat('*')) v = N(v) * N(pow()); else if (eat('/')) { const d = N(pow()); v = d === 0 ? NaN : N(v) / d; } else return v; } }
  function pow() { let v = unary(); while (eat('^')) v = N(v) ** N(unary()); return v; }
  function unary() { if (eat('-')) return -N(unary()); if (eat('+')) return unary(); return post(); }
  function post() { let v = prim(); while (eat('%')) v = N(v) / 100; return v; }
  function prim() {
    const t = tk[p++]; if (!t) throw 0;
    if (t.n != null) return t.n;
    if (t.s != null) return t.s;
    if (t.r != null) { if (!(t.r in nameIdx)) throw 0; return val(nameIdx[t.r], false); }
    if (t.c) {
      if (!t.c[1]) return cell(t.c[0], false);
      const a = letterIdx(t.c[0]), b = letterIdx(t.c[1]), out = []; for (let i = Math.min(a, b); i <= Math.max(a, b); i++) out.push(cell(colLetter(i), true)); return out;
    }
    if (t.o === '(') { const v = comp(); if (!eat(')')) throw 0; return v; }
    if (t.id === 'OUTOF' || t.id === 'MAXMARKS') {                       // OUTOF([Lab 1]) = the maximum marks fixed for that column
      if (!eat('(')) throw 0; const q = tk[p++]; if (!q || q.r == null || !(q.r in nameIdx) || !eat(')')) throw 0;
      const m = maxOf ? maxOf(nameIdx[q.r]) : null; return m == null ? NaN : m;
    }
    if (t.id) {
      if (t.id === 'TRUE') return true; if (t.id === 'FALSE') return false;
      if (FN[t.id] && eat('(')) { const a = []; if (!eat(')')) { do a.push(comp()); while (eat(',')); if (!eat(')')) throw 0; } return FN[t.id](a); }
    }
    throw 0;
  }
  try { const v = comp(); return p < tk.length || Array.isArray(v) ? undefined : v; } catch (e) { return undefined; }
}
/* all values of one student row: { colId : value } ; formulas stay empty while no mark is entered in that row */
function calcRow(cols, vals) {
  const idx = {}; cols.forEach((c, i) => idx[c.name.trim().toLowerCase()] = i);
  const any = cols.some(c => c.type != 'formula' && (num(vals[c.id]) != null || isAB(vals[c.id]))), memo = {}, busy = {};
  const get = (i, rng) => {
    const c = cols[i];
    if (c.type != 'formula') return num(vals[c.id]);
    if (!any) return null;
    if (i in memo) return memo[i]; if (busy[i]) return rng ? null : NaN;
    busy[i] = 1; memo[i] = runFormula(c.f, idx, get, cols.length, j => colMax(cols[j])); delete busy[i]; return memo[i];
  };
  const out = {}; cols.forEach((c, i) => out[c.id] = get(i)); return out;
}
/* the formula for the downloaded Excel: [Column name] -> cell, every row number -> this student's Excel row r, AVG -> AVERAGE */
function excelFormula(f, cols, r) {
  const idx = {}; cols.forEach((c, i) => idx[c.name.trim().toLowerCase()] = i);
  return String(f || '').trim().replace(/^=/, '').split(/("[^"]*")/).map((seg, k) => k % 2 ? seg : seg
    .replace(/(?:OUTOF|MAXMARKS)\(\s*\[([^\]]+)\]\s*\)/gi, (m, n) => { const i = idx[n.trim().toLowerCase()]; return i == null ? '0' : String(colMax(cols[i]) || 0); })
    .replace(/\[([^\]]+)\]/g, (m, n) => { const i = idx[n.trim().toLowerCase()]; return i == null ? '0' : colLetter(i + 2) + r; })
    .replace(/\$?([A-Za-z]{1,3})\$?\d+/g, (m, L) => L.toUpperCase() + r)
    .replace(/([A-Za-z]+)\(/g, (m, n) => { const u = n.toUpperCase(); return (u == 'AVG' ? 'AVERAGE' : u) + '('; })).join('');
}
/* an AB cell is the text "AB" in Excel: a single cell used in a calculation or comparison is wrapped as N(C7) (text -> 0, like the website).
   Ranges (C7:H7) and cells given straight to SUM / AVERAGE / MAX / MIN / COUNT stay as they are, because those functions skip text themselves. */
function excelAB(f) {
  const tk = f.match(/"[^"]*"|[A-Za-z]+\(|[A-Za-z]{1,3}\d+(?::[A-Za-z]{1,3}\d+)?|[\s\S]/g) || [], st = [], out = [], SKIP = ['SUM', 'AVERAGE', 'MAX', 'MIN', 'COUNT'];
  const side = (i, d) => { for (i += d; i >= 0 && i < tk.length; i += d) if (!/^\s$/.test(tk[i])) return tk[i]; return ''; };
  tk.forEach((t, i) => {
    if (t.length > 1 && t.endsWith('(')) { st.push(t.slice(0, -1).toUpperCase()); out.push(t); }
    else if (t == '(') { st.push(''); out.push(t); }
    else if (t == ')') { st.pop(); out.push(t); }
    else if (/^[A-Za-z]{1,3}\d+$/.test(t)) {
      const p = side(i, -1), n = side(i, 1);
      out.push(((p == ',' || p.endsWith('(')) && (n == ',' || n == ')') && SKIP.includes(st[st.length - 1])) ? t : 'N(' + t + ')');
    } else out.push(t);
  });
  return out.join('');
}

/* a typed mark must be a number or AB (absent), not negative and not above the maximum fixed for its column */
function readMark(c, text, who) {
  const t = String(text).trim(); if (t === '') return null;
  if (isAB(t)) return 'AB';
  if (isNaN(t)) throw Error('"' + t + '" for ' + who + ' (' + c.name + ') is not a number (type AB for absent)');
  const n = Number(t); if (n < 0) throw Error(c.name + ' for ' + who + ' cannot be negative');
  if (colMax(c) != null && n > colMax(c)) throw Error(c.name + ' for ' + who + ' is ' + n + ', more than the maximum ' + colMax(c));
  return n;
}

/* ---------- page ---------- */
async function marksView(kind) {
  const pane = $('#pane'); pane.innerHTML = '<p class="sm">Loading…</p>';
  const d = await T('marks_get', { sid, kd: kind });
  let cols = d.cols || [];
  if (ADM && kind == 'theory' && !cols.some(c => isFixed(kind, c))) {   // AAT 1 is inbuilt and mandatory; the admin adds the other columns
    const a = { id: cid(), name: FIXED_THEORY, type: 'marks', max: 10 };
    cols = cols.length ? cols.concat([a]) : [a];                       // an old sheet keeps its column letters: AAT 1 is added at the end
    await T('marks_cols_save', { sid, kd: kind, cols });
  }
  MK[kind] = { kind, cols, rows: d.rows || [], rc: d.row_colors || null, pub: d.published };            // pub: true / false (undefined = SQL file 17 not run yet)
  drawMarks(kind);
}
/* a student has only ONE row: show it as a tidy list (column name on the left, mark on the right) that fits any screen, no sideways scrolling */
function myMarks(M, TC, cols, kind) {
  const r = M.rows[0], v = calcRow(cols, r.vals || {}), h = rowHex(M, TC, r, v);
  return '<div class="mymarks"><div class="mmh"><b>' + esc(r.regno) + '</b><span>' + esc(r.name) + '</span></div>' + cols.map(c => {
    const ab = c.type != 'formula' && isAB((r.vals || {})[c.id]), hc = cellColor(TC.colr[c.id], v[c.id], ab) || null,
      val = ab ? 'AB' : (fmtN(v[c.id]) || '–');
    return '<div class="mmr' + (c.type == 'formula' ? ' fc' : '') + '"' + (h ? ' style="--rcs:' + h + '"' : '') + '><div class="mmn">' + esc(c.name) + (colMax(c) ? ' <small>/' + colMax(c) + '</small>' : '') +
      (kind == 'lab' && c.desc ? '<span class="mmd">' + esc(c.desc) + '</span>' : '') + '</div><div class="mmv' + (hc ? ' cv' : '') + '"' + (hc ? ' style="--cb:' + hc + ';--ci:' + inkOn(hc) + '"' : '') + '>' + esc(val) + '</div></div>';
  }).join('') + '</div>';
}
const mkTitle = k => k == 'lab' ? 'Lab Marks' : 'Theory Marks';
function drawMarks(kind) {
  const M = MK[kind], cols = M.cols, pane = $('#pane'), TC = kind == 'lab' ? tcGet(M) : { rowc: {}, colr: {}, rowr: null };
  const sw = (cls, id, hex) => '<label class="sw' + (hex ? '' : ' none') + '" style="--sw:' + (hex || '#ffffff') + '" title="Set the color (use 🎨 Colors to remove it)"><input type="color" class="' + cls + '" data-id="' + id + '" value="' + (hex || '#ffffff') + '" aria-label="Color"></label>';
  const L = t => '<span class="cl">' + t + '</span>';
  const head = '<tr><th>' + L('A') + 'Reg No</th><th>' + L('B') + 'Name</th>' + cols.map((c, i) => { const nr = (TC.colr[c.id] || []).length; return '<th class="' + (c.type == 'formula' ? 'fc' : '') + '">' + L(colLetter(i + 2)) + esc(c.name) + (c.type == 'formula' ? ' <small>ƒ</small>' : colMax(c) ? ' <small>/' + colMax(c) + '</small>' : '') + (isFixed(kind, c) ? ' <small>🔒</small>' : '') + (kind == 'lab' && c.desc ? '<span class="cd">' + esc(c.desc) + '</span>' : '') +
    (ADM ? (c.type != 'formula' ? ' <a class="cedit" onclick="colMarks(\'' + kind + '\',\'' + c.id + '\')" title="Enter / edit this column for all students">✎</a>' : '') + ' <a class="cedit" onclick="colModal(\'' + kind + '\',\'' + c.id + '\')" title="Column settings / delete">⚙</a>' + (kind == 'lab' ? ' <a class="cedit" onclick="condModal(\'lab\',\'' + c.id + '\')" title="Color rules of this column (for example below 11 = red)">🎨' + (nr ? '<sup>' + nr + '</sup>' : '') + '</a>' : '') : '') + '</th>'; }).join('') + (ADM ? '<th>Actions</th>' : '') + '</tr>';
  const body = M.rows.map((r, ri) => {
    const v = calcRow(cols, r.vals || {}), h = rowHex(M, TC, r, v), hm = TC.rowc[r.student_id] || null;                  // h = the color the admin gave this row (or null)
    return '<tr data-ri="' + ri + '"' + (h ? ' data-rc="1" style="--rc:' + mixW(h, .18) + ';--rcs:' + h + '"' : '') + '><td>' + (ADM && kind == 'lab' ? sw('cpr', r.student_id, hm) : '') + '<b>' + esc(r.regno) + '</b></td><td>' + esc(r.name) + '</td>' + cols.map(c => {
      const hc = cellColor(TC.colr[c.id], v[c.id], c.type != 'formula' && isAB((r.vals || {})[c.id])), k = (c.type == 'formula' ? 'fc' : '') + (hc ? ' cv' : ''), st = hc ? ' style="--cb:' + hc + ';--ci:' + inkOn(hc) + '"' : '';          // the first column rule that fits this cell gives its color
      return c.type == 'formula' ? '<td class="' + k + '"' + st + ' data-f="' + c.id + '"><b>' + fmtN(v[c.id]) + '</b></td>' :
        '<td class="' + k + '"' + st + '>' + (isAB((r.vals || {})[c.id]) ? '<b>AB</b>' : esc(fmtN(v[c.id]) || '–')) + '</td>'; }).join('') +
      (ADM ? '<td class="act"><a onclick="rowView(\'' + kind + '\',' + ri + ')">View</a><a onclick="rowEdit(\'' + kind + '\',' + ri + ')">Edit</a><a onclick="rowDel(\'' + kind + '\',' + ri + ')">Delete</a></td>' : '') + '</tr>';
  }).join('');
  const rcol = TC.rowr ? cols.find(c => c.id == TC.rowr.col) : null, lg = kind == 'lab' ? cols.filter(c => (TC.colr[c.id] || []).length) : [];                          // legend under the table: the color rules of every column that has some (students see it too)
  const legend = (lg.length || rcol) ? '<div class="clegend"><b>Colors</b>' + (rcol ? '<div class="clg"><span class="cn">Whole row by ' + esc(rcol.name) + '</span>' + TC.rowr.rules.map(r => '<span class="lgi" style="--cb:' + r.color + ';--ci:' + inkOn(r.color) + '">' + esc(ruleText(r)) + '</span>').join('') + '</div>' : '') + lg.map(c => '<div class="clg"><span class="cn">' + esc(c.name) + '</span>' + TC.colr[c.id].map(r => '<span class="lgi" style="--cb:' + r.color + ';--ci:' + inkOn(r.color) + '">' + esc(ruleText(r)) + '</span>').join('') + '</div>').join('') + '</div>' : '';
  pane.innerHTML =
    '<div class="pagehead" style="margin-bottom:8px"><h3 style="margin:0">' + mkTitle(kind) + (STU ? ' – your marks' : ROLE == 'cr' ? ' – view only' : '') + '</h3>' +
      (ADM ? '<p class="sm">Add columns, enter the marks, then download. <a href="/instructions.html" target="_blank" rel="noopener"><b>📘 Instructions</b></a> explain formulas, AB and colors.</p>' :
       STU ? '<p class="sm">Only you can see this row.</p>' : '<p class="sm">View only: you can see the marks of every student of this subject. Only the admin can change them.</p>') + '</div>' +
    (ADM ? '<div class="pubbar ' + (M.pub ? 'on' : 'off') + '"><span>' + (M.pub === undefined ? '⚠ Run the SQL file <code>17_marks_publish_timetable.sql</code> once in Supabase to use Publish.' : M.pub ? '✔ Published – students see their own marks' : '🔒 Not published – students cannot see these marks yet') + '</span>' +
      (M.pub === undefined ? '' : '<button class="btn ' + (M.pub ? 'alt' : 'y') + '" id="mpb">' + (M.pub ? 'Unpublish' : 'Publish to students') + '</button>') + '</div>' : '') +
    (ADM ? '<div class="row mkbar" style="margin:0 0 8px"><button class="btn y w3" id="mac">+ Add column</button>' + (kind == 'lab' ? '<button class="btn alt w3" id="mrc">🎨 Row colors</button><button class="btn alt w3" id="mrr">🎨 Row conditions</button><button class="btn alt w3" id="mcc">🎨 Column colors</button>' : '') +
      '<button class="btn alt w3" id="mim">⬆ Import</button><b class="mkdl">Download:</b><button class="btn alt w3" id="mdx">Excel</button><button class="btn alt w3" id="mdp">PDF</button><button class="btn alt w3" id="mdw">Word</button>' +
      '<button class="btn alt wf" id="mrs" style="margin-left:auto">Delete whole sheet</button></div>' : '') +
    (!cols.length ? '<p class="sm">' + (ADM ? 'No columns yet. Click <b>+ Add column</b> to create the first one (for example Lab 1, Lab 2, then a Total formula), or <b>⬆ Import</b> marks from Excel.' : M.pub === false ? '🔒 The marks are not published yet. You will get a notification when they are.' : 'No marks have been shared yet.') + '</p>' :
      !M.rows.length ? '<p class="sm">' + (STU ? 'Your marks have not been entered yet.' : kind == 'lab' || ADM || ROLE == 'cr' ? 'There are no students in this subject yet (add them in the Students tab).' : '') + '</p>' :
      (STU ? myMarks(M, TC, cols, kind) : '<div class="tw mk' + (kind == 'lab' ? ' plain' : '') + '"><table><thead>' + head + '</thead><tbody>' + body + '</tbody></table></div>') + legend);
  if (!ADM) return;
  $('#mac').onclick = () => colModal(kind);
  $('#mim').onclick = () => importModal(kind);
  if ($('#mpb')) $('#mpb').onclick = e => run(async () => {
    if (!confirm(M.pub ? 'Unpublish ' + mkTitle(kind) + '? Students will no longer see their marks.' : 'Publish ' + mkTitle(kind) + ' of ' + C.subject.code + '? Every student will see his / her own marks and gets a notification.')) return;
    try { await T('marks_publish', { sid, kd: kind, pub: !M.pub }); }
    catch (er) { throw /marks_publish|schema cache/i.test(er.message || '') ? Error('Run the SQL file 17_marks_publish_timetable.sql once in Supabase (see README), then try again.') : er; }
    const publishing = !M.pub;
    toast(publishing ? 'Published \u2013 students can see their marks' : 'Unpublished'); await marksView(kind);
    if (publishing) toast('Published \u2013 students can see their marks' + await mailPosted(sid, C.subject.code + ' \u2013 ' + mkTitle(kind) + ' published', mkTitle(kind) + ' of ' + C.subject.code + ' are now published.\n\nLog in and open the ' + mkTitle(kind) + ' tab to see your own marks.', mkTitle(kind)));
  }, e.target);
  if (kind == 'lab') { $('#mrc').onclick = () => tcModal(kind); $('#mcc').onclick = () => condModal(kind); $('#mrr').onclick = () => condModal(kind, '__row'); pane.onchange = e => tcQuick(kind, e); }          // 🎨 Row colors, 🎨 Column colors, and the small row swatches in the table
  $('#mdx').onclick = e => run(() => mkDownload(kind, 'xlsx'), e.target); $('#mdp').onclick = e => run(() => mkDownload(kind, 'pdf'), e.target); $('#mdw').onclick = e => run(() => mkDownload(kind, 'doc'), e.target);
  $('#mrs').onclick = e => run(async () => {
    if (!confirm('Delete the whole ' + mkTitle(kind) + ' sheet (all columns and all marks) of ' + C.subject.code + '? This cannot be undone.')) return;
    await T('marks_sheet_del', { sid, kd: kind }); toast('Sheet deleted'); await marksView(kind);
  }, e.target);
}

/* ---------- add / edit / delete a column ---------- */
function colModal(kind, id) {
  const M = MK[kind], c = id ? M.cols.find(x => x.id == id) : { name: '', type: 'marks', f: '' }, others = M.cols.filter(x => x.id != id), fx = !!id && isFixed(kind, c);
  const lettersHtml = pos => { const L = [['A', 'Reg No'], ['B', 'Name']];                              // the letters as they will be after the new column is added at position pos
    M.cols.forEach((x, i) => { if (!id && i == pos) L.push([colLetter(L.length), '(this new column)']); L.push([colLetter(L.length), x.name]); });
    if (!id && pos >= M.cols.length) L.push([colLetter(L.length), '(this new column)']);
    return L.map(x => '<code>' + x[0] + '</code> ' + esc(x[1])).join(' · '); };
  modal('<h3>' + (id ? 'Edit column' : 'Add column') + '</h3>' +
    (fx ? '<p class="sm">🔒 <b>' + esc(c.name) + '</b> is an inbuilt, mandatory column: it cannot be renamed, changed or deleted. You can still set its maximum marks.</p>' : '') +
    '<label class="fld">Column name<input id="kn" maxlength="40" value="' + esc(c.name) + '" placeholder="e.g. Lab 1, AAT 1, Total"' + (fx ? ' disabled' : '') + '></label>' +
    (!id && M.cols.length ? '<label class="fld">Where to add this column<select id="kpos"><option value="' + M.cols.length + '">At the end (after ' + esc(M.cols[M.cols.length - 1].name) + ')</option>' +
      M.cols.map((x, i) => '<option value="' + i + '">' + (i ? 'Before ' : 'At the very beginning, before ') + esc(x.name) + ' (now column ' + colLetter(i + 2) + ')</option>').join('') + '</select></label>' +
      '<p class="sm" id="kpn" hidden>The column letters inside the other formulas (like C5:H5) are updated automatically. A column added <b>inside</b> a range (like C5:E5) becomes part of that range, as in Excel. Formulas that use [names] never change.</p>' : '') +
    (kind == 'lab' ? '<label class="fld">Description of this column (optional)<input id="kds" maxlength="200" value="' + esc(c.desc || '') + '" placeholder="e.g. Record work of experiments 1 to 5"></label>' : '') +
    '<label class="fld">Column type<select id="kt"' + (fx ? ' disabled' : '') + '><option value="marks"' + (c.type != 'formula' ? ' selected' : '') + '>Marks (the admin types the marks)</option><option value="formula"' + (c.type == 'formula' ? ' selected' : '') + '>Formula (calculated, e.g. Total)</option></select></label>' +
    '<div id="km"' + (c.type == 'formula' ? ' hidden' : '') + '><label class="fld">Maximum marks of this column (optional)<input id="kmx" inputmode="decimal" value="' + esc(colMax(c) || '') + '" placeholder="e.g. 10 or 25"></label>' +
      '<p class="sm">Entering more than this is blocked, and formulas can use it: <code>OUTOF([' + esc(c.name || 'Lab 1') + '])</code> gives this maximum.</p></div>' +
    '<div id="kf"' + (c.type == 'formula' ? '' : ' hidden') + '>' +
      (others.length ? '<p class="sm" style="margin:0 0 6px"><b>Quick build:</b> choose a function and tick the columns</p><div class="row" style="margin:0 0 8px"><select id="kfn" style="max-width:140px"><option>SUM</option><option>AVG</option><option>MAX</option><option>MIN</option></select><input id="ksc" inputmode="decimal" placeholder="Scale to (optional)" style="max-width:170px" title="Only with SUM, when every ticked column has maximum marks"></div>' +
        '<div class="pick" style="max-height:150px">' + others.map(o => '<label class="chk"><input type="checkbox" class="kc" value="' + esc(o.name) + '">' + esc(o.name) + (o.type == 'formula' ? ' (formula)' : '') + '</label>').join('') + '</div>' : '') +
      '<label class="fld" style="margin-top:10px">Formula (Excel style)<input id="kfx" value="' + esc(c.f || '') + '" placeholder="=ROUNDUP(SUM(C5:H5)*20/230,0)" spellcheck="false"></label>' +
      '<p class="sm"><b>Column letters:</b> ' + '<span id="klt">' + lettersHtml(M.cols.length) + '</span></p>' +
      '<p class="sm" style="margin-top:12px"><a class="btn alt" href="/instructions.html" target="_blank" rel="noopener">📘 Instructions</a> &nbsp;how to type formulas, AB for absent, OUTOF and examples (opens a new page).</p></div>' +
    '<div class="row" style="margin:0"><button class="btn y" id="ks">' + (id ? 'Save' : 'Add column') + '</button>' + (id && !fx ? '<button class="btn red" id="kd">Delete column</button>' : '') + '<button class="btn alt" onclick="closeModal()">Cancel</button></div>');
  const build = () => {
    const ck = [...document.querySelectorAll('.kc:checked')].map(x => x.value), ch = ck.map(n => '[' + n + ']'); if (!ch.length) return;
    const sc = num($('#ksc') ? $('#ksc').value.trim() : ''), mx = ck.map(n => colMax(M.cols.find(x => x.name == n)));
    $('#kfx').value = ($('#kfn').value == 'SUM' && sc && mx.every(m => m)) ? '=SUM(' + ch.join(',') + ')*' + sc + '/(' + ck.map(n => 'OUTOF([' + n + '])').join('+') + ')' : '=' + $('#kfn').value + '(' + ch.join(',') + ')';
  };
  if ($('#kpos')) $('#kpos').onchange = () => { const p = Number($('#kpos').value); $('#klt').innerHTML = lettersHtml(p); $('#kpn').hidden = p >= M.cols.length; };
  $('#kt').onchange = e => { $('#kf').hidden = e.target.value != 'formula'; $('#km').hidden = e.target.value == 'formula'; };
  document.querySelectorAll('.kc').forEach(x => x.onchange = build); if ($('#kfn')) { $('#kfn').onchange = build; $('#ksc').oninput = build; }
  $('#ks').onclick = e => run(async () => {
    const v = { n: fx ? c.name : $('#kn').value.trim(), t: fx ? 'marks' : $('#kt').value, f: $('#kfx').value.trim(), mx: $('#kmx').value.trim(), d: $('#kds') ? $('#kds').value.trim() : '' }, pos = !id && $('#kpos') ? Number($('#kpos').value) : M.cols.length;            // read before the popup closes
    if (!v.n) throw Error('Enter the column name');
    if (v.t != 'formula' && v.mx !== '' && (isNaN(v.mx) || Number(v.mx) <= 0 || Number(v.mx) > 1000)) throw Error('Maximum marks must be a number between 1 and 1000 (or leave it empty)');
    if (v.t != 'formula' && v.mx !== '' && id) { const bad = M.rows.find(r => num((r.vals || {})[id]) != null && num((r.vals || {})[id]) > Number(v.mx)); if (bad) throw Error(bad.regno + ' already has ' + num(bad.vals[id]) + ', which is more than ' + v.mx + '. Correct that mark first or use a bigger maximum.'); }
    if (v.d.length > 200) throw Error('The description is too long (maximum 200 characters)');
    if (/[\[\]]/.test(v.n)) throw Error('The column name cannot contain [ or ]');
    if (others.some(o => o.name.trim().toLowerCase() == v.n.toLowerCase())) throw Error('A column with this name already exists');
    if (v.t == 'formula' && !v.f) throw Error('Type the formula or tick columns in Quick build');
    if (v.f.length > 300) throw Error('The formula is too long (maximum 300 characters)');
    let cols = M.cols.map(x => ({ ...x })), nid = null;
    if (id) {
      const o = cols.find(x => x.id == id), oldName = o.name;
      if (kind == 'lab') { if (v.d) o.desc = v.d; else delete o.desc; }
      o.name = v.n; o.type = v.t; if (v.t == 'formula') { o.f = v.f; delete o.max; } else { delete o.f; if (v.mx !== '') o.max = Number(v.mx); else delete o.max; }
      if (oldName != v.n) cols.forEach(x => { if (x.type == 'formula' && x.f) x.f = x.f.split('[' + oldName + ']').join('[' + v.n + ']'); });   // formulas follow the new name
    } else { const nc = v.t == 'formula' ? { id: cid(), name: v.n, type: 'formula', f: v.f } : { id: cid(), name: v.n, type: 'marks', ...(v.mx !== '' ? { max: Number(v.mx) } : {}) }; if (kind == 'lab' && v.d) nc.desc = v.d; nid = nc.id;
      if (pos < cols.length) { cols.forEach(x => { if (x.type == 'formula' && x.f) x.f = shiftRefs(x.f, pos + 2); }); cols.splice(pos, 0, nc); } else cols.push(nc); }       // in the middle: the other formulas follow the moved letters
    if (v.t == 'formula') {                                                     // test the formula on a sample row (every marks cell = 1)
      const me = cols.find(x => x.id == (id || nid)), sample = {}; cols.forEach(x => { if (x.type != 'formula') sample[x.id] = 1; });
      if (!Object.keys(sample).length) sample.none = 1;
      const t = calcRow(cols.some(x => x.type != 'formula') ? cols : cols.concat([{ id: 'tmp', name: '\u0000tmp', type: 'marks' }]), cols.some(x => x.type != 'formula') ? sample : { tmp: 1 })[me.id];
      if (t === undefined) throw Error('The formula is not valid. Check the brackets, the [Column names] and the column letters (see the list above).');
      if (typeof t == 'number' && isNaN(t)) throw Error('The formula gives an error (divide by zero, or it uses its own column). Please check it.');
    }
    await T('marks_cols_save', { sid, kd: kind, cols }); closeModal(); toast(id ? 'Column saved' : 'Column added'); await marksView(kind);
  }, e.target);
  if (id && !fx) $('#kd').onclick = e => run(async () => {
    const used = M.cols.filter(x => x.id != id && x.type == 'formula' && (x.f || '').toLowerCase().includes('[' + c.name.toLowerCase() + ']')).map(x => x.name);
    if (!confirm('Delete column "' + c.name + '" and all its marks?\nThe letters of the columns after it move one place left, so formulas that use column letters (like C5:H5) must be checked.' + (used.length ? '\nThese formula columns use it by name and will show Err: ' + used.join(', ') : ''))) return;
    await T('marks_cols_save', { sid, kd: kind, cols: M.cols.filter(x => x.id != id) }); closeModal(); toast('Column deleted'); await marksView(kind);
  }, e.target);
}

/* ---------- colors (admin, Lab Marks) ---------- */
/* a row swatch in the table (.cpr) was changed -> save at once and redraw, the table keeps its scroll position */
function tcQuick(kind, e) {
  const i = e.target.closest && e.target.closest('input.cpr'); if (!i) return;
  const M = MK[kind], T0 = tcGet(M), rowc = { ...T0.rowc }; rowc[i.dataset.id] = i.value.toLowerCase();
  const box = document.querySelector('.tw.mk'), sx = box ? box.scrollLeft : 0, sy = box ? box.scrollTop : 0;
  run(async () => { await tcSave(kind, rowc, T0.colr, T0.rowr); drawMarks(kind); const b = document.querySelector('.tw.mk'); if (b) { b.scrollLeft = sx; b.scrollTop = sy; } toast('Color saved'); });
}
/* 🎨 Row colors: one color for each row, or one color for all rows */
function tcModal(kind) {
  const M = MK[kind], T0 = tcGet(M);
  if (!M.cols.length) return toast('Add a column first', 1);
  if (!M.rows.length) return toast('No students in this subject yet', 1);
  const item = (id, label, hex) => '<div class="tci" data-id="' + esc(id) + '" data-set="' + (hex ? 1 : 0) + '"><span class="tcl">' + label + '</span>' +
    '<input type="color" class="tcc" value="' + (hex || '#ffffff') + '" aria-label="Color"><button type="button" class="btn alt tcx" title="No color">✕</button></div>';
  modal('<h3>🎨 Row colors · ' + esc(C.subject.code) + '</h3>' +
    '<p class="sm">Nothing is colored until you choose. Pick a color for each row, or one color for all rows. These colors win over the <b>Row conditions</b>. A cell that gets a color from a <b>column rule</b> keeps the column color. Students see the same colors.</p>' +
    '<div class="row" style="margin:10px 0 8px"><input type="color" id="tca" value="#fde68a" aria-label="Color for all rows" style="width:58px;padding:3px;min-height:42px;cursor:pointer"><button type="button" class="btn alt" id="tcap">Set all rows</button><button type="button" class="btn alt" id="tcno">Clear all</button></div>' +
    '<div class="pick tcp">' + M.rows.map(r => item(r.student_id, '<b>' + esc(r.regno) + '</b> ' + esc(r.name), T0.rowc[r.student_id])).join('') + '</div>' +
    '<div class="row" style="margin:14px 0 0"><button class="btn y" id="tcs">Save</button><button class="btn alt" onclick="closeModal()">Cancel</button></div>');
  const items = () => [...document.querySelectorAll('.tci')], mark = (d, on) => { d.dataset.set = on ? 1 : 0; };
  items().forEach(d => { d.querySelector('.tcc').oninput = () => mark(d, true); d.querySelector('.tcx').onclick = () => mark(d, false); });
  $('#tcap').onclick = () => { const v = $('#tca').value; items().forEach(d => { d.querySelector('.tcc').value = v; mark(d, true); }); };
  $('#tcno').onclick = () => items().forEach(d => mark(d, false));
  $('#tcs').onclick = e => run(async () => {
    const rowc = {}; items().forEach(d => { if (d.dataset.set == '1') rowc[d.dataset.id] = d.querySelector('.tcc').value.toLowerCase(); });      // read before the popup closes
    await tcSave(kind, rowc, T0.colr, T0.rowr); closeModal(); toast('Row colors saved'); drawMarks(kind);
  }, e.target);
}
/* 🎨 Column colors: condition based rules for every column (the first rule that fits a cell gives its color) */
function condModal(kind, id0) {
  const M = MK[kind], T0 = tcGet(M);
  if (!M.cols.length) return toast('Add a column first', 1);
  const W = {}, cp = a => (a || []).map(r => ({ op: r.op, a: r.a == null ? '' : String(r.a), b: r.b == null ? '' : String(r.b), color: r.color }));
  M.cols.forEach(c => W[c.id] = cp(T0.colr[c.id])); W.__row = cp(T0.rowr && T0.rowr.rules);                    // working copy of the rules of every column + the row rules ('__row')
  let rowCol = T0.rowr ? T0.rowr.col : (M.cols.find(c => c.type == 'formula') || M.cols[0]).id;
  let cur = (id0 == '__row' || (id0 && M.cols.some(c => c.id == id0))) ? id0 : (M.cols.find(c => c.type == 'formula') || M.cols[0]).id;
  const ruleRow = (r, i) => '<div class="rl" data-i="' + i + '"><select class="rop" aria-label="Condition">' + Object.keys(OPS).map(k => '<option value="' + k + '"' + (k == r.op ? ' selected' : '') + '>' + OPS[k] + '</option>').join('') + '</select>' +
    '<input class="ra" inputmode="decimal" value="' + esc(r.a) + '" placeholder="marks" aria-label="Marks"' + (needA(r.op) ? '' : ' hidden') + '>' +
    '<span class="rand"' + (r.op == 'bt' ? '' : ' hidden') + '>and</span><input class="rb2" inputmode="decimal" value="' + esc(r.b) + '" placeholder="marks" aria-label="Upper marks"' + (r.op == 'bt' ? '' : ' hidden') + '>' +
    '<input type="color" class="rcol" value="' + r.color + '" aria-label="Color"><button type="button" class="btn alt xs rx" aria-label="Remove this rule">✕</button></div>';
  modal('<h3>🎨 Column colors · ' + esc(C.subject.code) + '</h3>' +
    '<p class="sm">Color the cells of a column by their value. Rules are checked from top to bottom and the <b>first rule that fits</b> gives the color, so put the smaller limits first (for example <i>less than 11</i> = red, then <i>less than 16</i> = blue, then <i>16 or more</i> = green). Cells that fit no rule stay uncolored. Students see the same colors.</p>' +
    '<label class="fld">Color what<select id="cdc"><option value="__row">★ The WHOLE ROW (decided by one column)</option>' + M.cols.map((c, i) => '<option value="' + c.id + '">' + colLetter(i + 2) + ' · ' + esc(c.name) + '</option>').join('') + '</select></label>' +
    '<label class="fld" id="cdkw" hidden>The row color is decided by the value in column<select id="cdk">' + M.cols.map((c, i) => '<option value="' + c.id + '">' + colLetter(i + 2) + ' · ' + esc(c.name) + '</option>').join('') + '</select></label>' +
    '<div id="cdr"></div>' +
    '<div class="row" style="margin:6px 0 0"><button type="button" class="btn alt" id="cda">+ Add rule</button><button type="button" class="btn alt" id="cdp" title="Below 11 red, 11 to 15 blue, 16 and above green">Quick: red / blue / green</button><button type="button" class="btn alt" id="cdn">Remove this column\'s colors</button></div>' +
    '<div class="row" style="margin:0"><button type="button" class="btn alt" id="cdcp">Copy these rules to all columns</button><button type="button" class="btn alt" id="cdz">Remove all column colors</button></div>' +
    '<div class="row" style="margin:12px 0 0"><button class="btn y" id="cds">Save</button><button class="btn alt" onclick="closeModal()">Cancel</button></div>');
  const read = () => { W[cur] = [...document.querySelectorAll('#cdr .rl')].map(d => ({ op: d.querySelector('.rop').value, a: d.querySelector('.ra').value.trim(), b: d.querySelector('.rb2').value.trim(), color: d.querySelector('.rcol').value.toLowerCase() })); };
  const paint = () => {
    $('#cdc').value = cur;
    [...$('#cdc').options].forEach((o, i) => { const n = W[o.value].length, t = n ? '  (' + n + (n == 1 ? ' rule)' : ' rules)') : ''; o.textContent = i ? colLetter(i + 1) + ' · ' + M.cols[i - 1].name + t : '★ The WHOLE ROW (decided by one column)' + t; });
    $('#cdkw').hidden = cur != '__row'; $('#cdk').value = rowCol;
    $('#cdr').innerHTML = W[cur].length ? W[cur].map(ruleRow).join('') : '<p class="sm" style="margin:8px 0">No rule for this column: nothing is colored. Press <b>+ Add rule</b> or <b>Quick</b>.</p>';
    document.querySelectorAll('#cdr .rop').forEach(x => x.onchange = () => { read(); paint(); });
    document.querySelectorAll('#cdr .rx').forEach(x => x.onclick = () => { read(); W[cur].splice(+x.closest('.rl').dataset.i, 1); paint(); });
  };
  $('#cdc').onchange = e => { read(); cur = e.target.value; paint(); };
  $('#cdk').onchange = e => { rowCol = e.target.value; };
  $('#cda').onclick = () => { read(); if (W[cur].length >= MAXRULES) return toast('A column can have at most ' + MAXRULES + ' rules', 1); W[cur].push({ op: 'lt', a: '', b: '', color: RULE_COLORS[W[cur].length % RULE_COLORS.length] }); paint(); };
  $('#cdp').onclick = () => { W[cur] = [{ op: 'lt', a: '11', b: '', color: '#dc2626' }, { op: 'lt', a: '16', b: '', color: '#2563eb' }, { op: 'ge', a: '16', b: '', color: '#16a34a' }]; paint(); };
  $('#cdn').onclick = () => { W[cur] = []; paint(); };
  $('#cdcp').onclick = () => { read(); if (cur == '__row') return toast('Choose a column first: this copies the rules of a column to all columns', 1); M.cols.forEach(c => { W[c.id] = W[cur].map(r => ({ ...r })); }); paint(); toast('Copied to all columns. Press Save.'); };
  $('#cdz').onclick = () => { M.cols.forEach(c => { W[c.id] = []; }); paint(); };
  $('#cds').onclick = e => run(async () => {
    read(); const colr = {};                                                                  // read before the popup closes
    [{ id: '__row', name: 'Whole row' }, ...M.cols].forEach(c => {
      W[c.id].forEach((r, i) => {
        const who = c.name + ', rule ' + (i + 1) + ': ';
        if (needA(r.op) && (r.a === '' || isNaN(r.a))) throw Error(who + 'type the marks (a number)');
        if (r.op == 'bt' && (r.b === '' || isNaN(r.b))) throw Error(who + 'type both marks (a number in each box)');
        if (needA(r.op) && (Math.abs(Number(r.a)) > 100000 || (r.op == 'bt' && Math.abs(Number(r.b)) > 100000))) throw Error(who + 'the number is too big');
      });
      const x = cleanRules(W[c.id]); if (x.length) colr[c.id] = x;
    });
    const rr = colr.__row; delete colr.__row;
    await tcSave(kind, T0.rowc, colr, rr ? { col: rowCol, rules: rr } : null); closeModal(); toast('Column colors saved'); drawMarks(kind);
  }, e.target);
  paint();
}

/* ---------- column edit (admin): type / change ONE column for every student, or fill the same mark for all ---------- */
function colMarks(kind, id) {
  const M = MK[kind], c = M.cols.find(x => x.id == id); if (!c || !M.rows.length) return toast('No students in this subject yet', 1);
  modal('<h3>Column ' + esc(c.name) + (colMax(c) ? ' <small>(max ' + colMax(c) + ')</small>' : '') + ' · all students</h3>' +
    '<div class="row" style="margin:0 0 10px"><input id="cfv" inputmode="decimal" placeholder="Same mark / AB for all" style="max-width:170px"><button class="btn alt" id="cff">Fill all</button><button class="btn alt" id="cfc">Clear all</button></div>' +
    '<p class="sm" style="margin:0 0 8px">Type <b>AB</b> for an absent student. Formulas ignore an AB cell.</p><div class="pick" style="max-height:52vh">' + M.rows.map((r, i) => '<label class="cmr"><span><b>' + esc(r.regno) + '</b> ' + esc(r.name) + '</span><input class="ce" data-i="' + i + '" inputmode="decimal" value="' + esc(rawMark((r.vals || {})[id])) + '" aria-label="' + esc(c.name) + ' for ' + esc(r.regno) + '"></label>').join('') + '</div>' +
    '<div class="row" style="margin:12px 0 0"><button class="btn y" id="cks">Save column</button><button class="btn alt" onclick="closeModal()">Cancel</button></div>');
  $('#cff').onclick = () => { const v = $('#cfv').value.trim(); if (v === '' || (!isAB(v) && isNaN(v))) return toast('Type the mark to fill (or AB)', 1); document.querySelectorAll('.ce').forEach(i => i.value = isAB(v) ? 'AB' : v); };
  $('#cfc').onclick = () => document.querySelectorAll('.ce').forEach(i => i.value = '');
  $('#cks').onclick = e => run(async () => {
    const rw = [...document.querySelectorAll('.ce')].map(i => {                                   // other columns of each student are kept as they are
      const r = M.rows[+i.dataset.i], vals = { ...(r.vals || {}) }, n = readMark(c, i.value, r.regno);
      if (n == null) delete vals[id]; else vals[id] = n; return { student_id: r.student_id, vals };
    });
    await T('marks_save', { sid, kd: kind, rw }); closeModal(); toast(c.name + ' saved for all students'); await marksView(kind);
  }, e.target);
}

/* ---------- one student row: view / edit / delete (admin) ---------- */
function rowView(kind, ri) {
  const M = MK[kind], r = M.rows[ri], v = calcRow(M.cols, r.vals || {});
  modal('<h3>' + esc(r.regno) + ' · ' + esc(r.name) + '</h3><table class="kv">' + M.cols.map(c => '<tr><th>' + esc(c.name) + (kind == 'lab' && c.desc ? '<br><small class="sm" style="font-weight:400">' + esc(c.desc) + '</small>' : '') + '</th><td>' + (isAB((r.vals || {})[c.id]) ? 'AB' : fmtN(v[c.id]) || '–') + '</td></tr>').join('') + '</table>' +
    '<div class="row" style="margin:14px 0 0"><button class="btn" onclick="closeModal();rowEdit(\'' + kind + '\',' + ri + ')">Edit</button><button class="btn alt" onclick="closeModal()">Close</button></div>');
}
function rowEdit(kind, ri) {
  const M = MK[kind], r = M.rows[ri], mc = M.cols.filter(c => c.type != 'formula'), fc = M.cols.filter(c => c.type == 'formula');
  if (!mc.length) return toast('Add a marks column first', 1);
  modal('<h3>Edit marks · ' + esc(r.regno) + ' · ' + esc(r.name) + '</h3>' +
    mc.map(c => '<label class="fld">' + esc(c.name) + (colMax(c) ? ' <small>(max ' + colMax(c) + ')</small>' : '') + '<input class="re" data-c="' + c.id + '" inputmode="decimal" value="' + esc(rawMark((r.vals || {})[c.id])) + '"></label>').join('') +
    '<p class="sm">Type <b>AB</b> for absent (formulas ignore that cell).</p>' + (fc.length ? '<p class="sm">' + fc.map(c => esc(c.name)).join(', ') + ' will be calculated automatically.</p>' : '') +
    '<div class="row" style="margin:0"><button class="btn y" id="res">Save</button><button class="btn alt" onclick="closeModal()">Cancel</button></div>');
  $('#res').onclick = e => run(async () => {
    const vals = {}; document.querySelectorAll('.re').forEach(i => { const n = readMark(M.cols.find(c => c.id == i.dataset.c), i.value, r.regno); if (n != null) vals[i.dataset.c] = n; });
    await T('marks_save', { sid, kd: kind, rw: [{ student_id: r.student_id, vals }] }); closeModal(); toast('Saved'); await marksView(kind);
  }, e.target);
}
function rowDel(kind, ri) {
  const r = MK[kind].rows[ri];
  if (!confirm('Delete all marks of ' + r.regno + ' (' + r.name + ')?\nThe student stays in the subject; only the marks row is cleared.')) return;
  run(async () => { await T('marks_row_clear', { sid, kd: kind, i: r.student_id }); toast('Marks deleted'); await marksView(kind); });
}

/* ---------- download (admin): Excel keeps the formulas, PDF / Word get the calculated values ---------- */
async function mkDownload(kind, type) {
  const M = MK[kind]; if (!M.cols.length) throw Error('Add at least one column first'); if (!M.rows.length) throw Error('No students in this subject yet');
  const head = ['Reg No', 'Name', ...M.cols.map(c => c.name)], calc = M.rows.map(r => calcRow(M.cols, r.vals || {}));
  const rows = M.rows.map((r, i) => [r.regno, r.name, ...M.cols.map(c => isAB((r.vals || {})[c.id]) ? 'AB' : fmtN(calc[i][c.id]))]);
  const file = C.subject.code + (kind == 'lab' ? '-lab-marks' : '-theory-marks'), title = C.subject.code + ' – ' + mkTitle(kind);
  const TC = tcGet(M), fills = M.rows.map((r, i) => { const h = rowHex(M, TC, r, calc[i]); return h ? mixW(h, .18) : null; }),
    cellFills = M.rows.map((r, i) => [null, null, ...M.cols.map(c => cellColor(TC.colr[c.id], calc[i][c.id], c.type != 'formula' && isAB((r.vals || {})[c.id])))]);   // PDF / Word keep the row colors and the column rule colors (Excel keeps formulas only)
  if (type != 'xlsx') return exportTable(type, head, rows, title, file, { note: C.subject.full_name || C.subject.code, grid: true, fills, cellFills });
  await lib(XLSX_URL);
  const aoa = [head, ...M.rows.map((r, i) => [r.regno, r.name, ...M.cols.map(c => { const x = calc[i][c.id]; if (isAB((r.vals || {})[c.id])) return 'AB'; return x == null || (typeof x == 'number' && isNaN(x)) ? '' : x; })])];
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  M.cols.forEach((c, j) => { if (c.type != 'formula') return;
    M.rows.forEach((r, i) => { const x = calc[i][c.id], a = XLSX.utils.encode_cell({ r: i + 1, c: j + 2 }); ws[a] = { t: 'n', f: excelAB(excelFormula(c.f, M.cols, i + 2)), ...(x != null && !isNaN(x) ? { v: x } : {}) }; }); });
  ws['!cols'] = head.map((h, i) => ({ wch: i == 1 ? 26 : 14 }));
  const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, mkTitle(kind)); XLSX.writeFile(wb, file + '.xlsx');
}


/* ---------- import marks from Excel (paste) or an .xlsx / .xls / .csv file ----------
   Row 1 = headings, one heading is Reg No.  A heading that is the name of a marks column fills that column; a new heading creates a new marks column
   (if the box is ticked).  Name and formula columns are skipped.  An empty cell keeps the mark that is already there.  Marks are checked like typed marks. */
function parseCSV(txt) {
  const rows = []; let row = [], cell = '', q = false;
  for (let i = 0; i < txt.length; i++) {
    const ch = txt[i];
    if (q) { if (ch == '"') { if (txt[i + 1] == '"') { cell += '"'; i++; } else q = false; } else cell += ch; }
    else if (ch == '"') q = true;
    else if (ch == ',') { row.push(cell); cell = ''; }
    else if (ch == '\n') { row.push(cell); rows.push(row); row = []; cell = ''; }
    else if (ch != '\r') cell += ch;
  }
  row.push(cell); rows.push(row); return rows;
}
const gridFromText = txt => { txt = String(txt || '').replace(/^\ufeff/, '').trim(); if (!txt) return []; const g = txt.includes('\t') ? txt.split(/\r?\n/).map(l => l.split('\t')) : parseCSV(txt); return g.filter(r => r.some(x => String(x).trim() !== '')); };
function importModal(kind) {
  const M = MK[kind]; let FILE = null;
  modal('<h3>Import ' + mkTitle(kind) + '</h3>' +
    '<p class="sm" style="margin:0 0 8px">Row 1 = headings. One heading must be <b>Reg No</b>; the other headings are column names (Lab 1, AAT 1 ...). Tip: download the Excel first, fill the marks, and import it back. Type <b>AB</b> for absent. An empty cell keeps the old mark.</p>' +
    '<label class="fld">Paste from Excel<textarea id="imt" rows="6" class="mono" spellcheck="false" placeholder="Reg No\tLab 1\tLab 2\n22A91A0501\t8\t9\n22A91A0502\tAB\t7"></textarea></label>' +
    '<label class="fld" style="margin-top:10px">or choose a file (.xlsx, .xls, .csv)<input id="imf" type="file" accept=".xlsx,.xls,.csv,text/csv"></label>' +
    '<label class="chk" style="margin-top:10px"><input type="checkbox" id="imn" checked>Create a new marks column for a heading that does not exist yet</label>' +
    '<div id="imr" class="sm" style="margin-top:10px"></div>' +
    '<div class="row" style="margin:12px 0 0"><button class="btn alt" id="imc">Check</button><button class="btn y" id="imi" disabled>Import</button><button class="btn alt" onclick="closeModal()">Cancel</button></div>');
  let plan = null;
  const clear = () => { plan = null; $('#imi').disabled = true; };
  $('#imt').oninput = () => { FILE = null; $('#imf').value = ''; clear(); };
  $('#imf').onchange = e => run(async () => {
    const f = e.target.files[0]; clear(); FILE = null; $('#imr').textContent = ''; if (!f) return;
    if (/\.csv$/i.test(f.name)) FILE = gridFromText(await f.text());
    else { await lib(XLSX_URL); const wb = XLSX.read(await f.arrayBuffer(), { type: 'array' }); FILE = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, raw: true, defval: '' }).filter(r => r.some(x => String(x).trim() !== '')); }
    $('#imt').value = ''; $('#imr').innerHTML = '📄 <b>' + esc(f.name) + '</b>: ' + FILE.length + ' row(s) read. Press <b>Check</b>.';
  });
  const REG = /^(reg\.?\s*no\.?|regno|register\s*(no|number)|roll\s*(no|number)|registration\s*(no|number))$/i;
  $('#imc').onclick = () => {
    clear(); const g = FILE || gridFromText($('#imt').value), out = $('#imr'), bad = [], warn = [];
    if (g.length < 2) return out.innerHTML = '<span style="color:#b4202f">Paste (or choose) at least the heading row and one student row.</span>';
    const H = g[0].map(x => String(x).trim()), ri = H.findIndex(h => REG.test(h));
    if (ri < 0) return out.innerHTML = '<span style="color:#b4202f">Row 1 must have a heading <b>Reg No</b>.</span>';
    const byName = {}; M.cols.forEach(c => byName[c.name.trim().toLowerCase()] = c);
    const mk = [], seen = new Set(), made = [];                                                 // mk = [{ i, c, isNew }]
    H.forEach((h, i) => {
      if (i == ri || !h || /^(name|student name|s\.?\s*no\.?|sl\.?\s*no\.?)$/i.test(h)) return;
      const key = h.toLowerCase(); if (seen.has(key)) return warn.push('"' + h + '" appears twice: the second one is skipped'); seen.add(key);
      const c = byName[key];
      if (c && c.type == 'formula') return warn.push('"' + h + '" is a formula column: skipped');
      if (c) return mk.push({ i, c });
      if (!$('#imn').checked) return warn.push('"' + h + '" is not a column: skipped');
      if (/[\[\]]/.test(h) || h.length > 40) return warn.push('"' + h + '" cannot be a column name: skipped');
      const nc = { id: cid(), name: h, type: 'marks' }; made.push(nc); mk.push({ i, c: nc, isNew: true });
    });
    if (!mk.length) return out.innerHTML = '<span style="color:#b4202f">No marks column found in the headings.</span>' + (warn.length ? '<br>' + warn.map(esc).join('<br>') : '');
    if (M.cols.length + made.length > 60) return out.innerHTML = '<span style="color:#b4202f">Too many columns (maximum 60).</span>';
    const stu = {}; M.rows.forEach(r => stu[String(r.regno).toUpperCase()] = r);
    const rw = [], miss = []; let cells = 0;
    g.slice(1).forEach(line => {
      const reg = String(line[ri] == null ? '' : line[ri]).trim().toUpperCase(); if (!reg) return;
      const r = stu[reg]; if (!r) return miss.push(reg);
      const vals = { ...(r.vals || {}) }; let n = 0;
      mk.forEach(m => {
        const raw = line[m.i] == null ? '' : String(line[m.i]).trim(); if (raw === '') return;
        try { const v = readMark(m.c, raw, reg); if (v != null) { vals[m.c.id] = v; n++; } } catch (e) { bad.push(e.message); }
      });
      if (n) { rw.push({ student_id: r.student_id, vals }); cells += n; }
    });
    let h = '<b>' + rw.length + '</b> student(s), <b>' + cells + '</b> mark(s) ready. Columns: ' + mk.map(m => '<b>' + esc(m.c.name) + '</b>' + (m.isNew ? ' <i>(new)</i>' : '')).join(', ') + '.';
    if (miss.length) h += '<br>⚠ Not in this subject (skipped): ' + miss.slice(0, 8).map(esc).join(', ') + (miss.length > 8 ? ' … +' + (miss.length - 8) : '');
    warn.forEach(w => h += '<br>⚠ ' + esc(w));
    if (bad.length) h += '<div style="color:#b4202f;margin-top:6px"><b>' + bad.length + ' mark(s) are wrong; nothing is imported until you correct them:</b><br>' + bad.slice(0, 6).map(esc).join('<br>') + (bad.length > 6 ? '<br>… +' + (bad.length - 6) : '') + '</div>';
    out.innerHTML = h;
    if (!bad.length && rw.length) { plan = { rw, made }; $('#imi').disabled = false; }
    else if (!bad.length) out.innerHTML += '<br><span style="color:#b4202f">No student marks found to import.</span>';
  };
  $('#imi').onclick = e => run(async () => {
    if (!plan) return; const { rw, made } = plan;
    if (made.length) await T('marks_cols_save', { sid, kd: kind, cols: M.cols.concat(made) });
    await T('marks_save', { sid, kd: kind, rw });
    closeModal(); toast('Imported ' + rw.length + ' student(s)' + (M.pub === false ? ' · not published yet: press Publish when ready' : '')); await marksView(kind);
  }, e.target);
}
