/*
Restore students to Firestore from CSV files.

Usage (Windows cmd.exe):
  cd functions
  npm install csv-parse firebase-admin
  set GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\service-account.json
  node restore_students_from_csv.js ../assets/sample_data/CEIT-A,B,C.csv --dry-run

To target the Firestore emulator (for testing):
  set FIRESTORE_EMULATOR_HOST=localhost:8080
  node restore_students_from_csv.js ../assets/sample_data/CEIT-A,B,C.csv

Notes:
- The script defaults to dry-run and will only print what it WOULD write. Remove --dry-run to perform writes.
- It detects two CSV formats:
  Format A (header): Sem, Division, Branch, Roll No, Full Name
  Format B (2 columns): Roll, Name (e.g., CE-B:01, JOHN DOE)
- Document ID: sanitized rollNumber (non-alphanumeric replaced with '_').
- Existing documents are skipped unless --overwrite is provided.
*/

const fs = require('fs');
const path = require('path');
const { parse } = require('csv-parse/sync');
const admin = require('firebase-admin');

async function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.error('Usage: node restore_students_from_csv.js <csvPath> [--dry-run] [--overwrite]');
    process.exit(1);
  }

  const csvPath = args[0];
  const dryRun = args.includes('--dry-run') || args.includes('-n');
  const overwrite = args.includes('--overwrite') || args.includes('-o');

  // Init firebase-admin
  try {
    // If GOOGLE_APPLICATION_CREDENTIALS set, admin.initializeApp() will pick it up.
    admin.initializeApp();
  } catch (e) {
    // may already be initialized
  }
  const db = admin.firestore();

  const fullCsvPath = path.isAbsolute(csvPath) ? csvPath : path.join(__dirname, '..', csvPath);
  if (!fs.existsSync(fullCsvPath)) {
    console.error('CSV file not found:', fullCsvPath);
    process.exit(1);
  }

  const raw = fs.readFileSync(fullCsvPath, 'utf8');

  // Parse with csv-parse; returns array of records (arrays)
  const records = parse(raw, { relax_column_count: true, skip_empty_lines: false });

  // Remove fully empty rows
  const nonEmpty = records.filter(r => r.some(c => c != null && String(c).trim() !== ''));
  if (nonEmpty.length === 0) {
    console.log('No non-empty rows found in CSV');
    return;
  }

  // Detect optional header row
  function isHeaderRow(row) {
    const cells = row.map(c => (c || '').toString().toLowerCase());
    const keywords = ['sem', 'semester', 'division', 'div', 'branch', 'dept', 'department', 'roll', 'name', 'full name', 'student'];
    let matches = 0;
    for (const k of keywords) if (cells.some(c => c.includes(k))) matches++;
    if (matches >= 2) return true;
    if (cells.length >= 2) {
      const c0 = cells[0], c1 = cells[1];
      if ((c0.includes('roll') && c1.includes('name')) || (c0.includes('name') && c1.includes('roll'))) return true;
    }
    return false;
  }

  let headerIndex = -1;
  for (let i = 0; i < nonEmpty.length; i++) {
    if (isHeaderRow(nonEmpty[i])) { headerIndex = i; break; }
  }

  let headerMap = null;
  let dataRows = [];
  if (headerIndex !== -1) {
    const headerRow = nonEmpty[headerIndex].map(c => (c || '').toString().trim());
    headerMap = {};
    for (let i = 0; i < headerRow.length; i++) {
      const key = headerRow[i].toLowerCase();
      if (key.includes('sem')) headerMap['semester'] = i;
      if (key.includes('div') && !key.includes('division?')) headerMap['division'] = i;
      if (key.includes('branch') || key.includes('dept') || key.includes('department')) headerMap['department'] = i;
      if (key.includes('roll')) headerMap['roll'] = i;
      if (key.includes('name')) headerMap['name'] = i;
    }
    for (let i = headerIndex + 1; i < nonEmpty.length; i++) dataRows.push(nonEmpty[i]);
  } else {
    dataRows = nonEmpty;
  }

  function normalizeRoll(roll) {
    return roll.replace(/[^A-Za-z0-9_\-]/g, '_').toUpperCase();
  }

  function parseRowFallbackTwoColumn(row) {
    const c0 = (row[0] || '').toString().trim();
    const c1 = (row[1] || '').toString().trim();
    // Determine which is roll
    const rollFromC0 = /^[A-Za-z]+-[A-Za-z]+:\d+$/i.test(c0) || /\d+/.test(c0);
    const rollFromC1 = /^[A-Za-z]+-[A-Za-z]+:\d+$/i.test(c1) || /\d+/.test(c1);
    let roll = '', name = '';
    if (rollFromC0 && !rollFromC1) { roll = c0; name = c1; }
    else if (!rollFromC0 && rollFromC1) { roll = c1; name = c0; }
    else if (rollFromC0 && rollFromC1) { roll = c0; name = c1; }
    else { return null; }
    const inferred = /^([A-Za-z]+)-([A-Za-z]+):(\d+)$/i.exec(roll);
    if (!inferred) return null;
    return {
      name: name,
      rollNumber: roll,
      semester: 0,
      department: inferred[1].toUpperCase(),
      division: inferred[2].toUpperCase(),
    };
  }

  const toWrite = [];
  for (let i = 0; i < dataRows.length; i++) {
    const row = dataRows[i].map(c => (c == null ? '' : c.toString().trim()));
    // Skip rows that look like separators: sem+division only
    if (row.every(c => c === '')) continue;
    if (headerMap) {
      const sem = (row[headerMap['semester']] || '').trim();
      const div = (row[headerMap['division']] || '').trim();
      const dept = (row[headerMap['department']] || '').trim();
      const roll = (row[headerMap['roll']] || '').trim();
      const name = (row[headerMap['name']] || '').trim();
      if (sem && div && !roll && !name) continue; // separator
      if (!sem || !div || !roll || !name) { console.warn(`Skipping row ${i+1}: missing fields`); continue; }
      const semester = parseInt(sem) || 0;
      toWrite.push({ name, rollNumber: roll, semester, department: dept, division: div });
    } else {
      // Try 2-column parse
      if (row.length >= 2) {
        const parsed = parseRowFallbackTwoColumn(row);
        if (parsed) { toWrite.push(parsed); continue; }
      }
      console.warn(`Skipping unsupported row ${i+1}: ${JSON.stringify(row)}`);
    }
  }

  console.log(`Parsed ${toWrite.length} students from CSV`);

  if (dryRun) {
    console.log('DRY RUN: showing first 20 parsed entries');
    toWrite.slice(0, 20).forEach((s, idx) => console.log(`${idx+1}. ${s.rollNumber} - ${s.name} (${s.department}-${s.division})`));
    console.log('Dry-run finished. Use --overwrite to allow replacing existing docs, and remove --dry-run to perform writes.');
    return;
  }

  // Perform writes
  for (const s of toWrite) {
    const docId = normalizeRoll(s.rollNumber);
    const ref = db.collection('students').doc(docId);
    const snap = await ref.get();
    if (snap.exists && !overwrite) {
      console.log(`Skipping existing student ${s.rollNumber} (${s.name}) - doc ${docId} exists. Use --overwrite to replace.`);
      continue;
    }
    const payload = {
      name: s.name,
      rollNumber: s.rollNumber,
      semester: s.semester || 0,
      department: s.department || '',
      division: s.division || '',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    try {
      await ref.set(payload, { merge: true });
      console.log(`Wrote student ${s.rollNumber} -> doc ${docId}`);
    } catch (e) {
      console.error(`Failed to write ${s.rollNumber}:`, e);
    }
  }

  console.log('Restore complete.');
}

main().catch(err => { console.error(err); process.exit(1); });

