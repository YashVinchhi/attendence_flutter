# Attendance Management App — Feature Specification

Last updated: 2025-10-29

This document captures a detailed, screen-wise feature specification for the multi-platform Flutter Attendance Management application. It consolidates UI elements, minute behaviors, provider interactions, data flows, and edge-case handling in one place.

- Tech stack and patterns referenced: Flutter, Provider, go_router, sqflite, csv, file_picker, share_plus, path_provider, shared_preferences.
- Key modules referenced by path (where applicable): `lib/providers/*.dart`, `lib/models/*.dart`, `lib/screens/*.dart`, `lib/services/*.dart`.

---

## Table of Contents
- [Home — HomeScreen](#home--homescreen)
- [Manage Students — StudentsScreen](#manage-students--studentsscreen)
  - [Add Student dialog](#add-student-dialog)
  - [Edit Student dialog](#edit-student-dialog)
  - [Delete flow](#delete-flow)
  - [Search, Sorting, Filtering](#search-sorting-filtering)
  - [CSV Import](#csv-import)
  - [Reset sample data](#reset-sample-data)
  - [UI polish](#ui-polish)
- [Take Attendance — AttendanceScreen](#take-attendance--attendancescreen)
- [Reports — ReportsScreen](#reports--reportsscreen)
- [Settings — SettingsScreen](#settings--settingsscreen)
- [Cross-cutting: Providers, Services, Models](#cross-cutting-providers-services-models)
- [Third-party packages & integrations](#third-party-packages--integrations)
- [UI/UX patterns and small behaviors](#uiux-patterns-and-small-behaviors)
- [Edge cases & error handling](#edge-cases--error-handling)
- [Optional exports and next steps](#optional-exports-and-next-steps)

---

## Home — HomeScreen
Purpose: Main dashboard and navigation hub.

UI features:
- AppBar: title “Attendance Management” (centered).
- Welcome card: “Welcome to Attendance Management System”.
- Today date display from `DateTime.now()`.
- Two stats cards:
  - “Total Students” — `StudentProvider.students.length`.
  - “Today’s Records” — `AttendanceProvider.attendanceRecords.length`.
- Grid menu (2x2):
  - Manage Students → `/students`
  - Take Attendance → `/attendance`
  - View Reports → `/reports`
  - Settings → `/settings`
- Each menu item: Card + InkWell with icon, title, subtitle, and `onTap`.

Minute behaviors:
- Stats update live via `Consumer2<StudentProvider, AttendanceProvider>`.
- Grid `childAspectRatio` tuned for small screens to avoid overflow.
- Cards use subtle elevation and color accents per tile.

---

## Manage Students — StudentsScreen
Purpose: Add, edit, delete, search, import, and manage student records.

Main UI elements:
- AppBar: “Manage Students”.
  - Leading: home/back icon.
  - Actions:
    - Add (plus) → opens Add Student dialog.
    - Upload → starts CSV import (via file picker).
    - Popup menu → “Reset sample data”.
- Search text field:
  - Prefix search icon.
  - Clear button appears when text present.
  - `onChanged` updates `_searchQuery` and filters list.
- Sort segmented button: `Sort: Roll` and `Sort: Name` via `SegmentedButton`.
- “Import CSV” ActionChip CTA.
- List of students (ListView; ListTile per student).
- Pull-to-refresh (`RefreshIndicator`) → `studentProvider.fetchStudents()`.
- FAB → Add Student.

### Add Student dialog
Fields and defaults:
- Student Name (required)
- Roll Number (required)
- Semester (dropdown; default 1)
- Department (dropdown; default ‘CE’)
- Division (dropdown; default ‘A’)
- Time Slot (default ‘8:00-8:50’)

Validation and flow:
- Required: Name and Roll Number; shows SnackBar if missing.
- Duplicate roll-number check via `DatabaseHelper.instance.isRollNumberExists` handled by `StudentProvider.addStudent` → error SnackBar on duplicate.
- Add button shows spinner while adding; dismisses on success.

### Edit Student dialog
- Pre-populates fields with existing student data.
- Update includes same validation and duplicate-roll checks.
- Cancel resets `_editingStudent`.

### Delete flow
- Delete button prompts `AlertDialog` (Cancel/Delete confirmation).
- On success → SnackBar “Student deleted successfully”.

### Search, Sorting, Filtering
- Search covers name, roll number, and department (case-insensitive).
- Clearing search resets the list.
- Default sorting: CE/IT-aware comparator (CE group first, numeric comparisons).
- `Sort: Name` sorts alphabetically.

### CSV Import
Entry points and UX:
- FilePicker restricts to `.csv` (supports bytes or file path).
- Import dialog explains supported CSV formats and tips; user confirms import.
- Loading dialog (linear progress) shown via `NavigationService.showDialogSafely`.

Supported formats:
- Format A (5+ columns): Name, Roll Number, Semester, Department, Division.
- Format B (2 columns):
  - Option 1: `Roll, Name` (CE/IT style — e.g., `CE-B:01, JOHN DOE`).
  - Option 2: `Name, Roll`.

Header detection and empty-row handling:
- `_isHeaderRow` attempts to auto-detect and skip header row.
- `_isRowEmpty` skips empty rows.

Parsing and validation:
- Batch processing (`batchSize = 50`) to keep UI responsive.
- Semester validated as integer 1–8 when provided.
- Roll-number normalization (uppercasing) and DB uniqueness checking.
- For Format B, infer department/division via regex: `^([A-Za-z]+)-([A-Za-z]+):([0-9]+)$`.
- Default semester for missing value in Format B: `3`.
- Default time slot: `8:00-8:50`.
- Accumulate per-row errors: empty fields, invalid pattern, duplicates, etc.

Results and error reporting:
- Larger imports use DB transactions; failures logged per row.
- Structured result returned: `{ success, errors[], imported, total }`.
- If CSV empty or no valid rows → appropriate error message.
- Import result dialog shows summary (success/failed, imported count, errors list in scrollable area).

### Reset sample data
- Menu item shows confirmation.
- On confirm:
  - `DatabaseHelper.instance.clearAllData()`.
  - Update `SharedPreferences` flag `user_cleared_data` to false so app can reload sample data.
  - Re-fetch students.
  - SnackBar: “Sample data reloaded” or error.

### UI polish
- Shimmer skeleton while loading students (custom `AnimationController` + `ShaderMask`).
- ListTile content:
  - Avatar with initial.
  - Title: student.name.
  - Subtitle: `Roll No`, `Sem/Dept/Div`, `Time Slot`.
  - Trailing icons: edit (blue), delete (red).
- Empty state: friendly UI with icon, message, and buttons to Add or Import CSV.
- Provider-level bulk ops: `bulkDeleteStudents` (transaction-backed).
- `StudentProvider` auto-loads built-in sample data if DB empty via `DatabaseHelper.instance.loadSampleData()`.

---

## Take Attendance — AttendanceScreen
Purpose: Take and save attendance for a class on a given date, lecture, and subject.

Main UI elements:
- AppBar: “Take Attendance”
  - Back to home.
  - Save icon → saves attendance for current filtered list.
  - Notifications icon (no-op for now).
- FloatingActionButton: opens quick actions bottom sheet (Mark All Present / Mark All Absent) when students exist.
- `RefreshIndicator` → reload students and attendance.
- Date card:
  - Shows `_selectedDate` (ISO `yyyy-mm-dd`).
  - Edit button → `showDatePicker` (firstDate=2020, lastDate=now).
  - Supports deep-linking via `initialDate` (ignores future dates).
- Class selection chips (Sem, Department, Division) → bottom sheets pickers.
- Subject & Lecture selection:
  - Subject picker: fixed list from `_getSubjects()` → `[DCN, DS, Maths, ADBMS, OOP]`.
  - Lecture number picker: 1..6.
  - Lecture string used for saving/fetching: `<subject> - Lecture <n>`.
- Search field: filters current class list by name or roll.
- Status filter chips (scrollable): All / Present / Absent / Late.
  - Note: “Late” is a filter option; marking UI currently uses present/absent only.
- Sort options via ChoiceChips: By Roll / By Name.
- Summary card: shows Total, Present, Absent counts (with colors & icons).
- Student list: each student card is tappable; tap toggles presence.
  - Avatar color & status badge reflect presence (green/red).
  - Shows name & roll.

Saving attendance:
- Requires subject & lecture selected; else SnackBar alert.
- Saves by calling `AttendanceProvider.markAttendance` for each student.
- Uses `Future.wait` to parallelize saves.
- Success SnackBar: “Attendance saved successfully for X students”.
- Error SnackBar on exception.

Data and provider interactions:
- `_loadStudentsAndAttendance()` fetches students (`StudentProvider`) and attendance for date+lecture (`attendanceProvider.fetchAttendanceByDateAndLecture`).
- `_loadAttendanceStatus()` populates `_attendanceStatus` using `attendanceProvider.isStudentPresent`.
- `isStudentPresent` returns true by default if no record exists (intentional default; assume present unless absent recorded).
- `markAttendance` updates local `_attendanceStatus` optimistically; DB is persisted when Save is invoked.
- `markAllPresent`/`markAllAbsent` update the map; SnackBar feedback.
- Provider maps lecture number to time slot (1..6 → timeslots).

Minute behaviors and validations:
- Prevent marking attendance for future dates (provider rejects).
- Loading skeleton while fetching.
- CE/IT-aware sorting maintained when filters change.
- Save button disabled/no-op if `_filteredStudents` is empty (handler checks list).
- Search input trimmed before filtering.
- Bottom FAB quick actions: bottom sheet with two ListTiles (Mark All Present/Absent).

---

## Reports — ReportsScreen
Purpose: Generate, view, and share attendance reports (daily or date-range). Export as CSV or text.

Main UI elements:
- AppBar: “Attendance Reports”
  - Leading home/back.
  - PopupMenuButton (share options):
    - Daily Report Options (dialog: Present/Absent/All)
    - Daily Absentee Report
    - Share as CSV
    - Share as Text
- Settings card:
  - Dropdowns: Semester, Class Type (from `dbHelper.getCombinedDepartments()` e.g., `CE/IT`), Division.
  - Report Date field (read-only, opens `showDatePicker`, default `DateTime.now()`).
  - Buttons:
    - “Choose Daily Report Type” → dialog for Absent | Present | All → `_shareFormattedAttendanceReport(reportType)`.
    - “Quick Absentee Report” → `_shareFormattedAbsenteeReport()`.
- Overall Attendance Reports card (date range):
  - From Date / To Date pickers → changes trigger `_loadReports()`.
  - Buttons:
    - “Share CSV Report” → generate CSV via `csv` + `path_provider` temp dir + `Share.shareXFiles`.
    - “Share Text Report” → build text report and `Share.share`.
- Report list:
  - If no students: “No students found. Please add students first.”
  - Else: ListView of students; avatar badge shows attendance percentage.
    - Color-coded: ≥75% green; ≥50% orange; else red.
    - Subtitle: Roll, Sem/Department/Division, Present count.
    - Trailing share icon: share a single student’s text report.
- FloatingActionButton.extended: returns to `/home`.

Report generation and sharing:
- Uses `ReportProvider.generateAttendanceReport(from, to)` to compute per-student stats (init + on date change).
- `_shareReport()` compiles CSV with headers and per-student stats using `ListToCsvConverter`, writes a temp file, and shares with `Share.shareXFiles`.
- `_shareTextReport()` builds multi-line textual report and shares via `Share.share`.
- `_shareFormattedAttendanceReport(reportType)` shows loading dialog while generating via `AttendanceProvider.generateFormattedAttendanceReport`, then shares; handles closing dialog and error SnackBars.
- `_shareFormattedAbsenteeReport()` calls `AttendanceProvider.generateFormattedAbsenteeReport` and shares via `Share.share`.

Minute features and formatting:
- Formatted absentee report includes header: `Class, DD/MM/YYYY, DOW`; per-lecture grouping and department grouping (`CE:`, `IT:`).
- Roll digits displayed with leading zeros removed where possible.
- Absentee report includes inferred faculty names per subject (hard-coded mapping inside `AttendanceProvider._facultyFor`).
- Daily report dialog options: “Absent Only | Present Only | Complete Report”.
- Sharing supports both text and CSV file; temp file names include timestamp.
- Loading dialogs via `NavigationService.showDialogSafely`; closed with `popDialog`.
- All share functions use try/catch and show SnackBars on error.

---

## Settings — SettingsScreen
Purpose: App-wide preferences, data management, theme, and app info.

Main UI elements:
- AppBar with back to home.
- Cards:
  - App Settings:
    - Dark Mode toggle → `ThemeProvider.setThemeMode`.
    - “Show Percentage in Lists” toggle → `SettingsProvider.showPercentageInList`.
  - School Information:
    - TextField: School Name → `SettingsProvider.updateSchoolName`.
    - TextField: Academic Year → `SettingsProvider.updateAcademicYear`.
  - Attendance Settings:
    - Slider: Minimum Attendance Percentage (0–100, divisions 20) bound to `SettingsProvider.minimumAttendancePercentage` (label shows current value).
  - App Information:
    - App Version: 1.0.0 (static).
    - About: static text.
    - Developer Info: opens About dialog.
  - Data Management:
    - Backup Data (placeholder) → SnackBar “coming soon”.
    - Restore Data (placeholder) → SnackBar “coming soon”.
    - Clear All Data (destructive, red) → triggers `_clearAllData()`.

Clear All Data flow:
- Confirmation via `NavigationService.showDialogSafely`.
- On confirm:
  - Show loading dialog.
  - `studentProvider.clearAllData()` (clears students and DB tables as applicable).
  - `attendanceProvider.clearRecords()` (clears in-memory records).
  - Close dialog, then SnackBar success/failure.

Minute features:
- Settings loaded into text controllers in `initState`.
- Live updates via `Consumer2<ThemeProvider, SettingsProvider>`.
- Several dialogs use `useRootNavigator: true` to avoid nested navigator issues.

---

## Cross-cutting: Providers, Services, Models

Providers:
- `StudentProvider` (CRUD, bulk import, sorting, sample data load, search, class combos, clearAllData)
  - Batch CSV import with `_processCsvBatch` (`batchSize = 50`).
  - Helpers: `_isHeaderRow`, `_isRowEmpty`, `_extractDeptDivFromRoll`.
  - Error state reporting via `errorMessage` and state enums.
- `AttendanceProvider` (fetch by date/lecture, markAttendance, bulk mark, generate formatted absentee/present/all reports, stats)
  - `isStudentPresent` default true when no record exists (intentional default).
  - Date validation prevents future dates.
  - Formatted absentee report: groups by lecture→subject, then by department; student lines show normalized roll digits.
- `ReportProvider` (generates per-student attendance aggregates by range).
- `SettingsProvider` (school name, academicYear, minimumAttendancePercentage, showPercentageInList).
- `ThemeProvider` (ThemeMode handling).

Services:
- `DatabaseHelper` (DB interactions):
  - Methods used: `insertStudent`, `updateStudent`, `deleteStudent`, `getAllStudents`, `isRollNumberExists`, `getSemesters`, `getDepartments`, `getCombinedDepartments`, `getIndividualDepartments`, `getDivisions`, `getStudentsByCombinedClassOrdered`, `getAttendanceByDate`, `getAttendanceByDateAndLecture`, `insertAttendance`, `updateAttendance`, `getAttendanceRecordWithLecture`, `getAttendanceByDateRange`, `clearAllData`, `loadSampleData`.
- `NavigationService` used to safely show/hide dialogs across contexts.

Models:
- `Student`: `id`, `name`, `rollNumber`, `semester`, `department`, `division`, `timeSlot`, `createdAt`.
- `AttendanceRecord`: `id`, `studentId`, `date`, `isPresent`, `lecture`, `notes`.

---

## Third-party packages & integrations
- `file_picker` — CSV file selection.
- `csv` — parsing/generating CSV.
- `share_plus` — sharing text and files.
- `path_provider` — temporary directory (CSV export).
- `shared_preferences` — used when resetting sample data (flag `user_cleared_data`).
- `go_router` — navigation (`/home`, `/students`, `/attendance`, `/reports`, `/settings`).
- `provider` — state management.

---

## UI/UX patterns and small behaviors
- `RefreshIndicator` pull-to-refresh used across list-heavy screens.
- Loading skeletons (shimmer) while lists are loading.
- SnackBars for success/errors; progress dialogs for longer operations.
- Bottom sheets for picking sem/department/division/subject/lecture.
- Date pickers limited to [2020, now].
- Many dialogs and flows use small `Future.delayed` gaps for smoother transitions.
- Optimistic UI on attendance toggles (local state updates before persisting).
- CE/IT-specific roll parsing and sorting conventions applied consistently.

Minute details and conventions:
- `SegmentedButton` styling to match theme in Students screen.
- `ActionChip` for quick import CTA.
- ListTile trailing actions: explicit colors (edit: blue, delete: red).
- FABs and buttons with consistent paddings and shapes.
- `ListToCsvConverter` used for CSV composition in reports.
- Example CSV format and tips are shown inside Import dialog (monospace text).
- Provider state enums: `idle | loading | error` and `errorMessage` shown via SnackBars.
- `StudentProvider._sortStudents` CE/IT regex: `(CE|IT)-[A-Z]:(\d+)`.
- Percentages in report UI formatted to 1 decimal place; optional display in lists controlled by settings.
- Reports screen supports per-student share (short text with present/absent totals).
- Settings screen shows version `1.0.0` statically.

---

## Edge cases & error handling
- Duplicate roll numbers prevented and surfaced to the user.
- CSV parsing:
  - Header detection (skips header row).
  - Empty rows ignored.
  - Unsupported formats reported in errors list returned to UI.
- DB transactions and batching protect against partial inserts.
- Marking attendance for a future date is rejected and surfaced.
- If no attendance records for date/lecture, `isStudentPresent` defaults to true (intentional; may be surprising to some users).
- Many methods guard against concurrent calls (`if (state == loading) return;`).
- Large imports update UI after each batch; final result dialog summarizes outcomes.

---

## Optional exports and next steps
- Export this specification as:
  - Markdown (this file: `FEATURES.md`).
  - CSV checklist (columns: screen, feature, notes).
  - PDF (printer-friendly; can be generated from Markdown).
- Generate concise in-app “User manual” help pages per screen.
- Add unit tests for critical provider logic (CSV import, attendance calculations).
- Create a single-page feature dashboard UI (`lib/screens/feature_list.dart`) that renders this list in-app.

If you want any of the optional exports or implementations above, request it and the artifacts can be generated and wired into the repo directly.

