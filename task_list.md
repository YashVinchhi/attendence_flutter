# Project Task List — Invite-based Role Access & Attendance Features

Purpose: a single source-of-truth task list and implementation plan to add invite-only one-time login, role-based access (CR/CC/HOD/ADMIN), secure backend enforcement, UI flows, testing, and deployment for the attendance app.

---

## Quick checklist (top-level)
- [ ] Define/confirm data model and persistence (users, invites, students, attendance)
- [ ] Implement secure invite creation + email sending (server)
- [ ] Implement invite acceptance flow with one-time sign-in (client + server)
- [ ] Persist AppUser on successful acceptance and map auth uid -> role
- [ ] Implement server-side role-based authorization (Firestore rules / REST guards)
- [ ] Add client-side UI screens & services (Invite creation, Accept invite, role-aware dashboard)
- [ ] Add audit logging, analytics, and admin tools
- [ ] Add tests (unit, integration, e2e) and CI/CD
- [ ] Deploy backend, update security rules, and release client changes

---

## 1) Data model (what to add/update)
Files to update/create: `lib/models/models.dart` (already extended), `lib/models/user_model.dart` (optionally split), server DB collections schema.

Entities:
- users/{uid} (AppUser): { uid, email, name, role, allowed_classes: ["2CEIT-B"], is_active, created_at }
- invites/{tokenId} (InviteToken): { tokenHash, invited_email, role, allowed_classes, expires_at, used, created_by, created_at }
- students/{studentId} (Student): existing model
- classes/{classId} or use embedded ClassInfo strings
- attendance/{attendanceId} or attendance collection per class/date: { student_id, date, is_present, lecture, created_by }
- audit_logs/{id}: { actor_uid, action, target, timestamp, details }

Design notes:
- Store tokenHash (server-side) not plaintext token.
- allowed_classes as string list using `ClassInfo.displayName` (e.g., "2CEIT-B") or normalized map.
- Keep `users/{uid}` collection as the canonical auth->role mapping used by security rules.

---

## 2) Backend architecture
Recommended stack: Firebase (Auth + Firestore) + Cloud Functions (Node.js/TypeScript) or your own REST API.

Why Firebase: tight Flutter integration, Authentication + Firestore Security Rules, Cloud Functions for token creation and email sending.

Core functions to implement (Cloud Functions or REST endpoints):
- createInvite(inviterUid, invitedEmail, role, allowedClasses[], expiresInDays)
  - Server: validate inviter permissions (inviter must be CC/HOD/ADMIN and allowed to invite for classes), generate secure token, store hashed token and metadata in invites collection, send email with one-time link.
- acceptInvite(token, authUid, email)
  - Server: find invite by token hash, validate not used and not expired, ensure invitedEmail equals signed-in user email, create users/{authUid} AppUser document with role and allowedClasses, mark invite used, log audit.
- revokeInvite(tokenId) / listInvites(for inviterUid)
- admin endpoints: listUsers, changeUserRole, deactivateUser, reassignClasses

Implementation details:
- Token generation: use crypto.randomBytes(32) -> base64url encode. Store bcrypt/sha256 hash of token (e.g., sha256(token) hex) in invites doc.
- Email sending: Cloud Function uses SendGrid / SMTP / Mailgun. Use templates and deep link / dynamic link.
- Deep links: configure Firebase Dynamic Links (or universal links) to open app with token param.

Security:
- All invite validation done server-side.
- Cloud Function checks requester role (via callable function or verify admin token) when creating invites.
- Store only token hash in database. Token sent via email only once.

---

## 3) Firestore structure & Security Rules (high level)
Collections:
- /users/{uid}
- /invites/{inviteId}
- /students/{studentId}
- /classes/{classId}
- /attendance/{attendanceId} or /classes/{classId}/attendance/{dateDoc}
- /audit/{id}

Security rules (concepts):
- Read rules: allow read of students/attendance if user exists and `users/{uid}.allowed_classes` contains the class or if user.role in [HOD, ADMIN] and allowed accordingly.
- Write rules:
  - Creating attendance: allowed for CR/CC/HOD if class in allowed_classes. CR cannot create student docs.
  - Students modifications: only CC/HOD/ADMIN allowed (and CC only for classes they manage).
  - Invite creation: only CC/HOD/ADMIN (server-side Cloud Function preferred to avoid rule complexity).

Provide `users/{uid}` lookup in rules to check role and allowed_classes. Keep rules minimal and enforce heavy logic in Cloud Functions.

---

## 4) Invite flow — detailed step-by-step
A: CC creates invite (in-app):
1. CC opens "Create Invite" screen.
2. Select role (CR usually), enter invited email, pick allowed classes and expiry (default 7 days).
3. App calls `createInvite` Cloud Function (callable) with metadata.
4. Cloud Function verifies CC's role and allowed class scope server-side.
5. Server generates secureToken (random), stores sha256(token) as tokenHash, saves invite doc with invitedEmail (lowercased), role, allowedClasses, expiresAt, createdBy.
6. Server sends email with a one-time link to app: https://app.yourdomain.com/invite?token=<plainToken>
   - For mobile, use Firebase Dynamic Links for deep link into the app.

B: CR accepts invite:
1. CR opens link (deep link) and the app reads token param.
2. App shows sign-in screen (email pre-filled) and instructs CR to sign in (passwordless/email link or provider).
3. After successful sign-in, app calls `acceptInvite` Cloud Function with token and the signed-in user's uid and email.
4. Server finds invite by tokenHash (compare sha256(token) with stored tokenHash), checks expiry and used flag, validates invitedEmail == user.email.
5. If valid, server creates `users/{uid}` AppUser doc with role and allowed_classes (or updates existing), marks invite used, sends success ack.
6. Client loads role-aware dashboard.

Edge cases:
- If invite expired: show friendly message with a button to request re-invite.
- If email mismatched: require user to sign-in with invited email or re-initiate.
- Multiple invites for same email: accept the newest valid invite; older tokens must be invalidated.

---

## 5) Client-side (Flutter) implementation
Files to add/update:
- `lib/services/invite_service.dart` (callable HTTPS functions wrapper)
- `lib/screens/invite_create_screen.dart` (CC UI)
- `lib/screens/accept_invite_screen.dart` (deep link handler)
- `lib/widgets/class_picker.dart` (reusable)
- `lib/providers/auth_provider.dart` (if using provider/riverpod) to store AppUser

Behavior:
- When app launches, check for dynamic link token and navigate to AcceptInviteScreen if present.
- `InviteService.createInvite(...)` -> calls Cloud Function `createInvite` and shows success/failure.
- `InviteService.acceptInvite(token)` -> calls `acceptInvite` function and handles result.
- After accept, fetch `users/{uid}` AppUser doc and populate app state.

UI/UX details:
- CRs should have a simplified dashboard without edit controls for student lists.
- CCs get create/edit UI for students and invite management panel (list invites with their status).
- HODs see analytics dashboard (charts per class/semester) and admin tools.
- Show clear error pages for expired/used tokens.

Offline/Sync:
- Allow attendance marking to be queued offline (local SQLite) and synced when online; on sync, server-side must validate timestamp & deduplicate by student+date.

---

## 6) Authorization enforcement (server & client)
- Server-side Cloud Functions must check user role + allowed classes before processing operations that modify data.
- Firestore rules should reject writes that bypass Cloud Functions (for admin-only ops), but some operations are easier via Cloud Functions only (invite creation, token verification).
- On the client, hide UI controls for unauthorized roles but do not trust client logic.

Pseudocode guard (Cloud Function):
- load userDoc = firestore.doc('users/' + request.auth.uid)
- if userDoc.role == 'CR' and trying to edit a student -> throw FORBIDDEN
- if userDoc.allowed_classes doesn't contain class -> throw FORBIDDEN

---

## 7) Tests
Unit tests:
- Model serialization: AppUser <-> Map, InviteToken <-> Map
- Token hashing and verification helpers

Integration tests:
- Cloud Function createInvite/acceptInvite flows (use Firebase emulator)
- Firestore rules tests (with Rules Unit Testing)

End-to-end tests:
- Automated e2e to simulate inviting, accepting, and performing CR vs CC operations.

---

## 8) Auditing, logging, monitoring
- Add an `audit_logs` collection and write log entries for important actions (invite created/accepted, student created/deleted, attendance edits) by Cloud Functions.
- Use Firebase Crashlytics and Analytics for monitoring + event instrumentation for invites and role actions.

---

## 9) Deployment & CI/CD
- Backend: Cloud Functions deploy via CI (GitHub Actions). Use Firebase project staging/production and emulator for tests.
- Client: Flutter CI builds for Android & iOS. Tag releases and publish to app stores or distribute via internal channel.
- Security rules deployment included in pipeline.

---

## 10) Admin tooling & operational tasks
- Admin panel (web or in-app): list users, change role, revoke access, re-issue invites.
- Revoke flows: set `users/{uid}.is_active = false` and Cloud Functions / rules check it.
- Data migrations: provide migration scripts for older attendance -> new schema.

---

## 11) Implementation timeline & priorities (suggested)
Phase A (1-2 weeks) - MVP invite + roles + basic enforcement
- Create models & client services (invite crud wrappers)
- Cloud Functions: createInvite & acceptInvite, token hashing
- Send test emails via SendGrid / emulator
- Firestore users collection and minimal rules
- Basic InviteCreate and AcceptInvite screens

Phase B (1-2 weeks) - permissions, UI polish, auditing
- CC student management UI updates
- Restrict CR UI (no edits)
- Add audit logs and analytics
- Add offline support for attendance queue

Phase C (1-2 weeks) - scale, tests, deployment
- Add rule tests, Cloud Function tests, e2e
- CI/CD pipelines
- Admin panel and reassign tools

---

## 12) Files & code map (what to implement where)
Client (Flutter):
- lib/models/models.dart — AppUser/InviteToken (already present)
- lib/services/invite_service.dart — callable Cloud Function wrappers
- lib/services/auth_service.dart — integrate with Firebase Auth sign-in & email link
- lib/providers/user_provider.dart — load & cache users/{uid}
- lib/screens/invite_create_screen.dart — CC invite UI
- lib/screens/accept_invite_screen.dart — deep link handler & acceptance
- lib/screens/dashboard_cr.dart — CR UI (no edits)
- lib/screens/dashboard_cc.dart — CC UI (with edit tools)
- lib/screens/dashboard_hod.dart — HOD analytics
- test/models_test.dart — model unit tests

Server (Cloud Functions / REST):
- functions/src/index.ts
  - callable function createInvite
  - callable function acceptInvite
  - helpers: token gen, tokenHash (sha256), sendEmail
- firestore.rules — security rules aligned with users/{uid}
- scripts/migration.js — optional migration helpers

---

## 13) Acceptance criteria (clear definition of Done)
- CR can sign in only via a valid invite and can mark attendance, view reports, but cannot change student list or class metadata.
- CC can create invites, manage student lists for their allowed classes, and view/edit attendance.
- HOD can manage all classes and view analytics.
- Invites are single-use, secure (server-side token hash), and expire.
- Firestore rules + Cloud Functions prevent unauthorized changes (verified by tests).
- End-to-end test simulates invite -> accept -> CR takes attendance and cannot edit student list.

---

## 14) Next immediate step I can implement for you now
Pick one and I will implement it next:
- Scaffold `lib/services/invite_service.dart` and `lib/screens/accept_invite_screen.dart` (client-side Flutter) including deep link handling.
- Create Cloud Functions scaffold (Node.js/TypeScript) for `createInvite` and `acceptInvite` with secure token generation and email stub (no external API key required in dev).
- Add Firestore security rules draft and unit tests for them using the emulator.

---

If you want, I'll implement Phase A tasks now (choose Client or Backend start). If you choose "Backend", I'll create the Cloud Functions scaffold and sample email template; if you choose "Client" I'll add the Flutter service + screens and run analyzer/tests.


