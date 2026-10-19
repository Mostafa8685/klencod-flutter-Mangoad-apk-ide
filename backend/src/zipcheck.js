import AdmZip from 'adm-zip';

export function isSafeEntryPath(name) {
  const p = name.replace(/\\/g, '/');
  if (!p || p.includes('\0') || p.startsWith('/') || /^[A-Za-z]:/.test(p)) return false;
  return !p.split('/').includes('..');
}

export function detectType(names) {
  const p = names.map((n) => n.replace(/\\/g, '/'));
  const isRoot = (f, name) => { const parts = f.split('/'); return parts.at(-1) === name && parts.length <= 2; };
  if (p.some((f) => isRoot(f, 'pubspec.yaml')) && p.some((f) => f.endsWith('.dart'))) return 'flutter';
  if (p.some((f) => /build\.gradle(\.kts)?$/.test(f)) && p.some((f) => f.endsWith('AndroidManifest.xml'))) return 'native';
  if (p.some((f) => f.endsWith('index.html'))) return 'web';
  return 'unknown';
}

/**
 * Header-only inspection (nothing is extracted). Header sizes can be forged, so the
 * build runner enforces the same limits again while extracting.
 */
export function checkZip(buf, o = {}) {
  const { maxEntries = 20000, maxTotal = 1024 ** 3, maxFile = 500 * 1024 ** 2, maxRatio = 200 } = o;
  let entries;
  try { entries = new AdmZip(buf).getEntries(); } catch { return { ok: false, code: 'zip_invalid', message: 'Unreadable archive' }; }
  if (entries.length === 0 || entries.length > maxEntries) return { ok: false, code: 'zip_invalid', message: 'Bad entry count' };
  let total = 0;
  const names = [];
  for (const e of entries) {
    if (!isSafeEntryPath(e.entryName)) return { ok: false, code: 'zip_invalid', message: 'Unsafe path in archive' };
    const size = e.header.size;
    if (size > maxFile) return { ok: false, code: 'zip_invalid', message: 'Entry too large' };
    total += size;
    names.push(e.entryName);
  }
  if (total > maxTotal || total / Math.max(buf.length, 1) > maxRatio) {
    return { ok: false, code: 'zip_invalid', message: 'Archive expands too much' };
  }
  return { ok: true, type: detectType(names) };
}
