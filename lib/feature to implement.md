
# Project Audit Report


## Critical / Must-fix issues (can break app behavior)

### 1\. Auth mismatch: AuthProvider persisted uid vs FirebaseAuth usage causes runtime exceptions

* **Files:** `lib/providers/auth_provider.dart`, `lib/services/invite_service.dart`, `lib/providers/user_provider.dart`
* **Problem:**
    * `AuthProvider` stores a persisted `auth_uid` and returns it from `uid` (used as canonical auth identity in app).
    * Many services (for example `InviteService.getCurrentAppUserDoc`) rely on `FirebaseAuth.instance.currentUser` and throw if `currentUser == null`.
    * In dev mode / non-Firebase flows `AuthService` may return deterministic fake UIDs without setting `FirebaseAuth.currentUser`. That leads to `InviteService.getCurrentAppUserDoc()` throwing "Not authenticated" (because it checks FirebaseAuth) even though `AuthProvider.instance.uid` contains a valid uid for the app's logic.
* **Example call chain:** `UserProvider.refresh()` (which uses `AuthProvider.instance.uid`) may call `InviteService.getCurrentAppUserDoc()` which uses `FirebaseAuth.instance.currentUser` — inconsistent auth sources.
* **Effect:** invites, user refresh, and other flows that expect a user doc will crash or be unreachable in non-Firebase flows.
* **Fix:**
    1.  Decide a single canonical source of truth for auth within the client. Options:
    2.  Prefer `FirebaseAuth.instance.currentUser` everywhere and ensure `AuthService.signIn()` sets `FirebaseAuth` user in dev flow (harder).
    3.  OR prefer `AuthProvider.instance.uid` as canonical for client logic and update service helpers to accept an explicit `uid` (or fallback to `AuthProvider.instance.uid`) instead of using `FirebaseAuth.currentUser`.
* **Minimal safe change:** update `InviteService.getCurrentAppUserDoc()` (and other methods that call `FirebaseAuth.currentUser`) to accept an optional `uid` parameter and fall back to `AuthProvider.instance.uid` when `FirebaseAuth` has no user. Or internally use:
  ```dart
  final authUid = _auth.currentUser?.uid ?? AuthProvider.instance.uid;
  ```
* Also ensure that `UserProvider.refresh()` and others do not call Firebase-backed functions that require real `FirebaseAuth` when running in dev-only mode.
* **Why it's critical:** causes immediate exceptions or broken flows in dev/local mode and inconsistent behavior across environments.

### 2\. Incorrect / non-existent API call: Listenable.merge(...) in router creation

* **File:** `lib/services/router.dart`
* **Problem:**
    * Code uses `refreshListenable: Listenable.merge([ ... ])`.
    * `Listenable.merge` is not a standard Flutter API (and will not compile). GoRouter expects a single `Listenable`; to combine multiple listenables you need to use a `Listenable` wrapper.
* **Effect:** compile-time error / router not buildable.
* **Fix:**
    * Replace with a combined `Listenable` implementation, e.g. create a small `CompositeListenable` (`ChangeNotifier`) that listens to the passed listenables and call `notifyListeners()` when any of them changes, or simply pass `authListenable` and handle other refreshes separately:
    * **Simple:** if `refreshListenable` is nullable, do `refreshListenable ?? authListenable`.
    * **Or create helper:**
      ```dart
      class CompositeListenable extends ChangeNotifier {
        CompositeListenable(List<Listenable> sources) {
          for (var s in sources) s.addListener(notifyListeners);
        }
      }
      ```
* **Minimal patch:** pass `refreshListenable ?? authListenable`.

-----

## High priority (functional correctness / logic bugs)

### 1\. Lecture/time-slot mismatch causes attendance reads to miss records

* **Files:** `lib/screens/attendance_screen.dart`, `lib/services/database_helper.dart`, `lib/providers/attendance_provider.dart`
* **Problem:**
    * `AttendanceScreen._getLectureString()` appends time slot when `_selectedTimeSlot` present:
        * returns `'SUBJECT - Lecture N • 8:00-8:50'` (subject + lecture + slot)
    * `DatabaseHelper.normalizeAttendanceLectures()` normalizes to `'SUBJECT - Lecture N'` (no time slot).
    * `getAttendanceByDateAndLecture()` queries for exact match on `lecture` column. If the screen adds time-slot suffix, query will fail to match DB rows and attendance will not load, resulting in defaults (UI treats as present by default).
* **Effect:** existing attendance entries won't be loaded correctly when time slot is selected. Leads to lost updates and confusing UX.
* **Fix:**
    * Normalize the query string and stored values to a canonical format. Do not append time-slot to the lecture text stored in DB — instead store time slot separately in `lecture` column or store `lectureSubject`, `lectureNumber`, `timeSlot` as distinct columns OR ensure `_getLectureString()` returns the exact string used when saving/loading (i.e., without timeslot) and store timeslot separately if needed.
* **Quick fix:** change `_getLectureString()` to NOT include time slot (return only `'SUBJECT - Lecture N'`), and when saving attendance separately store `timeSlot` to a different column or metadata. Or, when querying DB, try both forms (with and without timeslot).
* **Recommendation:** add a `lecture_time_slot` column if timeslot is important.

### 2\. InviteService local-fallback token generation is fragile and low-entropy

* **File:** `lib/services/invite_service.dart`
* **Problems:**
    * Token generation: `base64Url.encode(uuid.v4().codeUnits).substring(0, 43)` is fragile:
    * Using `uuid.v4().codeUnits` encodes the string characters of the UUID; base64 of ASCII string isn’t a good entropy measure; substring length assumption may break.
    * Not guaranteed URL-safe and consistent length in all locales.
    * Token hashing: they compute `hash = sha256(token)` and store `tokenHash`. OK in principle, but token generation should be simpler and safer.
* **Fix:**
    * Use `TokenGenerator.generate()` (already in the repo) or `Uuid().v4()` directly, or generate random bytes:
      ```dart
      final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      final token = base64UrlEncode(bytes).replaceAll('=', '');
      ```
    * Ensure token length and URL-safety and avoid substringting.
    * Also: `InviteService.createInvite` returns plain token in local fallback — be careful to only expose token in dev or use outbox to email in production.

### 3\. InviteListScreen expects server response shape incorrectly

* **File:** `lib/screens/invite_list_screen.dart` and `lib/services/invite_service.dart`
* **Problem:**
    * `InviteListScreen._load()` expects `final res = await InviteService.listInvites(); final List<Map<String,dynamic>> invites = List<Map<String,dynamic>>.from(res['invites'] ?? []);`
    * `InviteService.listInvites()` returns `Map<String,dynamic>` derived from `result.data` of callable function; server may return different shapes or a straight list. Casting may fail.
* **Fix:**
    * Make `InviteService.listInvites()` return a normalized shape (`List<Map<String,dynamic>>`) or document exact shape; update `InviteListScreen` to handle multiple shapes (Map with `invites` key OR a raw `List`) safely, with null checks.

### 4\. UserProvider.\_startListening swallows errors incorrectly and may create inconsistent AppUser

* **File:** `lib/providers/user_provider.dart`
* **Problem:**
    * On snapshot data, they call `AppUser.fromMap(data)` without validating fields; `fromMap` parsing may throw which is caught and sets `_user = null`, but no logging. Also `hasPermission` uses `_user?.permissions`, but `AppUser.fromMap` returns `permissions` as `List<String>` only if stored as `List`. If Firestore stores permissions as a `Map`, this may fail.
* **Fix:**
    * Add logging, more robust parsing, defensive checks (use `try/catch` around individual fields), and ensure consistent Firestore schema.

-----

## Medium priority (bugs / suboptimal implementations)

* **`ValidationHelper.sanitizeInput` removes apostrophes globally — over-aggressive**

    * **File:** `lib/models/models.dart`
    * **Problem:** `sanitize` replaces `'` with empty string; this strips valid names like "O'Connor".
    * **Fix:** Use stricter encoding escaping or a whitelist approach; avoid removing apostrophes, or provide optional sanitization.

* **Repetitive / duplicated roll-number parsing and sorting logic across providers and DB helper**

    * **Files:** many (`student_provider.dart`, `database_helper.dart`, `students_screen.dart`, `attendance_screen.dart`)
    * **Problem:** similar regex and sorting logic duplicated in multiple places.
    * **Fix:** Extract helper functions in one util file (e.g., `lib/utils/roll_utils.dart`) that parse roll number into `{dept, division, number}` and provide comparator. Reduce duplication to reduce bugs.

* **Many places using raw strings for dates instead of typed helpers**

    * **Files:** many
    * **Problem:** Frequent `toIso8601String().substring(0,10)` and `DateTime.parse(...)` appears across code; it's repetitive and error prone.
    * **Fix:** Create `formatDateYMD(DateTime)` and `parseDateYMD(String)` utilities and use them consistently.


* **`DatabaseHelper._initDB` uses `version: 4` with `onUpgrade` but migrations may be non-atomic or fragile**

    * **File:** `lib/services/database_helper.dart`
    * **Problem:** migration attempts to `ALTER TABLE` with `NOT NULL` default on existing DB could fail on some sqlite builds. Also the inline function `_columnExists` is defined inside `_onUpgrade` making testing harder.
    * **Fix:** Keep safe, catch exceptions (they already do), but consider more explicit migration steps and tests. Use `PRAGMA` to check schema.

* **`AuthService.useFirebase` default `true` but `main.dart`'s env logic is ambiguous**

    * **Files:** `lib/services/auth_service.dart`, `lib/main.dart`
    * **Problem:**
        * `AuthService.useFirebase` default `true`; in `main.dart` they set `useFirebase = true` for prod; in dev they set it to `true` again if emulator exists. However much of the code has complex emulator REST fallback. This leads to ambiguity: is dev using real Firebase or not? Danger of accidentally talking to production.
    * **Fix:**
        * Make default explicit and readable via `--dart-define=ENV`. Provide clear comments and safer defaults (dev=false).

* **`AuthProvider.signIn` fallback network code is long, complex, and can leak resources**

    * **File:** `lib/providers/auth_provider.dart`
    * **Problem:**
        * Large nested `try/catch` branching; some `HttpClient` streams may not be closed in all code paths; logic is hard to maintain.
    * **Fix:**
        * Refactor into smaller helper functions for REST `signIn`, REST `signUp`, and ensure `client.close()` in `finally` blocks. Add unit tests for emulator fallback logic.

* **Deprecated / flagged usage: `Share.shareXFiles` and `Share.share` deprecations**

    * **Files:** `lib/screens/reports_screen.dart`
    * **Problem:**
        * Using deprecated APIs (they suppressed warnings). Might be OK now but plan to update to new stable API.
    * **Fix:**
        * Migrate to the modern `share_plus` API calls per current plugin docs.

* **Many unhandled exceptions bubbled to UI instead of user-friendly messages**

    * **Files:** multiple screens and providers
    * **Problem:**
        * Several service calls rethrow exceptions without user-friendly display. Some UIs display raw `e.toString()` which might leak details.
    * **Fix:**
        * Add uniform error handling: sanitize messages in UI, log details, show friendly messages to users.

-----

## Low priority / style / performance / maintainability

* Large duplication of sample data and CSV parsing logic in `DatabaseHelper` (sample list) and `StudentProvider` import
    * **Suggest:** move sample data into asset CSV and reuse CSV parsing logic for sample load, reduce duplication.
* `TokenGenerator` exists but invite service does not use it (inconsistent)
    * **File:** `lib/utils/token_generator.dart` and `invite_service.dart`
    * **Suggestion:** reuse `TokenGenerator.generate(32)` for tokens to centralize randomness code.
* `ValidationHelper.isValidEmail` regex is permissive / not RFC-complete
    * Could be OK for the app, but consider using robust validation libraries or more permissive checks and let server confirm.
* Many UI helper strings and magic constants scattered; consolidate into `constants.dart`.
* **Minor:** Some variable names and null-safety patterns can be improved (e.g., avoid duplicate `mounted` checks, reduce rebuilds by using providers more selectively).

-----

## Half-implemented / risk areas / to watch

* **Invite / function-based flows:**
    * The cloud functions integration is wrapped with many fallbacks (local Firestore fallback, outbox entries). This is useful but fragile; you should add unit/integration tests that exercise both the callable and the fallback path to make sure shapes are consistent.
* **Debug anonymous sign-in in `AcceptInviteScreen`:**
    * `AcceptInviteScreen._signInAnonymouslyForDemo()` signs in anonymously; then `acceptInvite()` expects the invited user's email to match — anonymous user won't have that email. It's clearly labeled demo, but it may cause acceptance failure because server usually requires email-based validation. Consider clarifying or implementing a complete invite acceptance flow (require entering invited email).
* **`AdminService._initEmulatorIfNeeded()` gating of emulator by `ENABLE_FUNCTIONS` is confusing:** enabling/disabling functions should be clearer.

-----

## Security issues

* Avoid logging full exception stacks in production (some prints exist like `'SIGNIN_ERROR: ${e.toString()}'`).
* Sanitization logic removes apostrophes which may mask legitimate data but not necessarily security — but be careful with SQL and Firestore injection; use parameterized queries (`sqflite` already uses `whereArgs` — good).
* Storing plain tokens in local dev fallback — make sure this is only for dev. Production flow should never show tokens in client.

## Performance suggestions

* For larger classes, fetching all students and filtering on client is expensive. Consider:
    * Querying DB with `where` clauses for selected semester/department/division or indexing tables more depending on scale.
    * Use pagination for student lists.
* The UI sometimes uses `Consumer` that rebuild large widget trees; consider more granular consumers for perf.

## Testing & CI suggestions

* Add unit tests for:
    * `DatabaseHelper` migrations and queries (use `sqflite_common_ffi` in tests).
    * `StudentProvider.bulkImportFromCsv()` for different CSV formats, including duplicate and malformed rows.
    * `InviteService` fallback token generation and Firestore interactions (mock Firestore).
    * `AuthProvider` emulator REST fallback code (mock HTTP).
* Add small integration test that runs DB migrations and sample data load.
