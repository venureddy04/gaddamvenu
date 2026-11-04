/* export.js – Excel / PDF / Word downloads and lazy library loader (shared by subject.html and students.html) */
const XLSX_URL = 'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js',
  JSPDF_URL = 'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js',
  AUTOTABLE_URL = 'https://cdnjs.cloudflare.com/ajax/libs/jspdf-autotable/3.8.2/jspdf.plugin.autotable.min.js';
const libs = {};
const lib = u => libs[u] || (libs[u] = new Promise((ok, no) => { const e = document.createElement('script'); e.src = u; e.onload = ok; e.onerror = () => no(Error('Could not load a library. Check the internet connection.')); document.head.append(e); }));

/* black or white text on a colored cell */
const ink = h => { const [r, g, b] = [1, 3, 5].map(i => parseInt(h.substr(i, 2), 16)); return (r * 299 + g * 587 + b * 114) / 1000 > 150 ? '#111827' : '#ffffff'; };

/* kind: 'xlsx' | 'pdf' | 'doc'   head: ['Reg No',...]   rows: [[...],...]   */
async function exportTable(kind, head, rows, title, file, opts = {}) {
  const note = opts.note != null ? opts.note : 'Login page: ' + BASE, sheet = opts.sheet || 'Logins';
  if (!rows.length) throw Error('Nothing to download');
  if (kind == 'xlsx') {
    await lib(XLSX_URL);
    const ws = XLSX.utils.aoa_to_sheet([head, ...rows]); ws['!cols'] = head.map(() => ({ wch: 22 }));
    const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, sheet); XLSX.writeFile(wb, file + '.xlsx');
  } else if (kind == 'pdf') {
    await lib(JSPDF_URL); await lib(AUTOTABLE_URL);
    const d = new window.jspdf.jsPDF({ orientation: head.length > 5 ? 'landscape' : 'portrait' }); d.setFontSize(15); d.text(title, 14, 16);
    d.setFontSize(9); d.text(note, 14, 22);
    const rgb = h => [1, 3, 5].map(i => parseInt(h.substr(i, 2), 16));
    d.autoTable({ head: [head], body: rows, startY: 27, theme: opts.grid ? 'grid' : 'striped', styles: opts.grid ? { fontSize: 9, lineColor: [150, 160, 185], lineWidth: 0.2 } : { fontSize: 9 }, headStyles: { fillColor: [10, 27, 69], textColor: 255 },
      didParseCell: (opts.fills || opts.colFills || opts.cellFills) ? (h => { if (h.section != 'body') return; const cf = opts.cellFills && opts.cellFills[h.row.index] && opts.cellFills[h.row.index][h.column.index]; const f = cf || (opts.colFills && opts.colFills[h.column.index]) || (opts.fills && opts.fills[h.row.index]); if (f) h.cell.styles.fillColor = rgb(f); if (cf) { h.cell.styles.textColor = rgb(ink(cf)); h.cell.styles.fontStyle = 'bold'; } }) : undefined }); d.save(file + '.pdf');
  } else {
    const c = 'border:1px solid #444;padding:4px 8px;font-size:11pt';
    const html = '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word"><head><meta charset="utf-8"><title>' + esc(title) + '</title></head><body>' +
      '<h2>' + esc(title) + '</h2><p>Login page: ' + esc(BASE) + '</p><table style="border-collapse:collapse"><tr>' + head.map(h => '<th style="' + c + ';background:#0A1B45;color:#fff">' + esc(h) + '</th>').join('') + '</tr>' +
      rows.map((r, i) => '<tr>' + r.map((v, j) => { const cf = opts.cellFills && opts.cellFills[i] && opts.cellFills[i][j], f = cf || (opts.colFills && opts.colFills[j]) || (opts.fills && opts.fills[i]); return '<td style="' + c + (f ? ';background:' + f : '') + (cf ? ';color:' + ink(cf) + ';font-weight:bold' : '') + '">' + esc(v) + '</td>'; }).join('') + '</tr>').join('') + '</table></body></html>';
    const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['\ufeff', html], { type: 'application/msword' })); a.download = file + '.doc'; document.body.append(a); a.click(); a.remove();
  }
}
